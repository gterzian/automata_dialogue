import Core
import Foundation
import MLX
import MLXLMCommon
import MLXVLM

/// A configuration error that stops a run before generation. Downloads are
/// disabled, so a configuration with no local snapshot directory is fatal
/// instead of something to fetch.
public enum AgentEngineError: Error, LocalizedError {
    case noModelDirectory
    case noCacheableSystemPrefix
    case systemPromptCacheMismatch

    public var errorDescription: String? {
        switch self {
        case .noModelDirectory:
            "No local model snapshot configured. Set RATER_MODEL_PATH or pass --model <dir>; network downloads are disabled."
        case .noCacheableSystemPrefix:
            "The model's chat template does not expose a cacheable system-prompt prefix."
        case .systemPromptCacheMismatch:
            "The system-prompt cache did not cover the prefilled system tokens."
        }
    }
}

/// The MLX VLM implementation of `AgentRunning`. Each run is one self-contained
/// turn over the immutable system prompt and the current input. The model
/// container and a KV cache holding the system-prompt prefix are built once and
/// shared; each run copies that prefix and prefills only the current input.
///
/// There is no tool call and no tool-dispatch round: the model replies with a
/// `class:` line and an `id:` line, and `ChoiceParser` reads the chosen entry
/// out of the text. A reply without a usable catalog id fails the run; there is
/// no repair pass.
///
/// The Core AI backend (`AgentCoreAI`) is the other `AgentSession`; both hand
/// their answer to `AgentDialogue`, so the dialogue is the same on either.
public actor AgentEngine: AgentSession {
    public nonisolated let backend = AgentBackend.mlx

    public struct Configuration: Sendable {
        /// The local Hugging Face snapshot directory to load. Models are never
        /// downloaded: a configuration with no directory fails the run. See
        /// `Models/README.md` for the snapshots and `Agent/README.md`.
        public var modelDirectory: URL?
        public var maxTokens: Int
        public var temperature: Float
        /// The square side, in pixels, the image is resized to before the model
        /// sees it. Qwen3.5 turns this into `(side / 32)²` vision tokens, so
        /// 512 costs 256 prompt tokens. See `Core/Import/README.md`.
        public var imageDimension: Int
        public var tokenizerLoader: any TokenizerLoader

        public init(
            modelDirectory: URL? = nil,
            maxTokens: Int = 100,
            temperature: Float = 0.2,
            imageDimension: Int = 512,
            tokenizerLoader: any TokenizerLoader = HuggingFaceBridges.tokenizerLoader()
        ) {
            self.modelDirectory = modelDirectory
            self.maxTokens = maxTokens
            self.temperature = temperature
            self.imageDimension = imageDimension
            self.tokenizerLoader = tokenizerLoader
        }

        /// Reads `RATER_MODEL_PATH` (a local snapshot directory). Downloads are
        /// disabled, so an unset path leaves `modelDirectory` nil and the run
        /// fails when it tries to load.
        public static func fromEnvironment(
            _ environment: [String: String] = ProcessInfo.processInfo.environment
        ) -> Configuration {
            var configuration = Configuration()
            if let path = environment["RATER_MODEL_PATH"], !path.isEmpty {
                configuration.modelDirectory = URL(
                    fileURLWithPath: NSString(string: path).expandingTildeInPath, isDirectory: true)
            }
            return configuration
        }
    }

    private let configuration: Configuration
    /// One load shared by every run; cleared on failure so a later run retries.
    private var containerTask: Task<ModelContainer, Error>?
    /// The system-prompt KV cache, built once after the container loads. Each
    /// run copies it, so the prefix arrays are never mutated by a run.
    private var promptCacheTask: Task<PromptCacheHolder, Error>?
    /// Recent choices, carried across runs. `perform` turns it into the
    /// user-turn exclusion note, so the dialogue never repeats an automaton.
    private var dialogue = AgentDialogue()

    /// Carries the built system-prompt cache out of `ModelContainer.perform`.
    /// SAFETY: the snapshot is built from a fresh cache inside the container's
    /// lock, transferred to `AgentEngine`, and only read there; each run copies
    /// the cache before generation, so neither the prefix arrays nor the model
    /// state are mutated concurrently.
    private struct PromptCacheHolder: @unchecked Sendable {
        let snapshot: PromptCacheSnapshot
    }

    /// Thinking is off, so the model answers instead of spending tokens on a
    /// reasoning preamble before its `class:` line.
    private static let answerContext: [String: any Sendable] = ["enable_thinking": false]
    /// The system-prefix render stops before the assistant turn, so the cached
    /// prefix contains only the system message and any tokens before it.
    private static let systemPrefixContext: [String: any Sendable] = [
        "enable_thinking": false,
        "add_generation_prompt": false,
    ]

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Loads the shared container and builds the system-prompt cache so the
    /// first `run` does not also pay either cost. Both are cached and a failure
    /// is retried, so a failed preload is not fatal: the first `run` reports the
    /// error again.
    public func prepare() async throws {
        _ = try await modelContainer()
        _ = try await promptCache()
    }

    /// Drops the recent-choice window, so the next run is not asked to avoid
    /// earlier ids. `classify` uses it to measure each image's class
    /// independently of the others.
    public func resetHistory() {
        dialogue.reset()
    }

    public nonisolated func run(_ input: AgentInput) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { await self.perform(input, into: continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Private

    private func perform(
        _ input: AgentInput,
        into continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async {
        do {
            let turn = dialogue.turn(for: input.text)
            let cache = try await promptCache()

            let result = try await answer(
                cache: cache, to: turn.prompt, imageURL: input.imageURL)
            let response = result.text
            if !response.isEmpty { continuation.yield(.text(response)) }
            if let metrics = result.metrics { continuation.yield(.metrics(metrics)) }

            if let choice = dialogue.accept(response, excluding: turn.excluded) {
                continuation.yield(.choice(choice))
                continuation.yield(.finished)
            } else {
                continuation.yield(.failed("the model did not name a catalog id"))
            }
            continuation.finish()
        } catch {
            continuation.yield(.failed(error.localizedDescription))
            continuation.finish()
        }
    }

    /// One generation pass over `prompt`; returns the full text and, when the
    /// model reported it, the completion metrics. The pass starts from a copy of
    /// the system-prefix cache, so only the user turn is prefilled.
    private func answer(
        cache: PromptCacheHolder,
        to prompt: String,
        imageURL: URL?
    ) async throws -> (text: String, metrics: GenerationMetrics?) {
        let container = try await modelContainer()
        let parameters = generateParameters
        let cacheCopy = cache.snapshot.cache.map { $0.copy() }
        let prefixTokenCount = cacheCopy.map(\.offset).max() ?? 0
        let image = imageURL.map { UserInput.Image.url($0) }
        let userInput = UserInput(
            chat: [.user(prompt, images: image.map { [$0] } ?? [])],
            processing: UserInput.Processing(
                resize: CGSize(
                    width: configuration.imageDimension,
                    height: configuration.imageDimension)),
            additionalContext: Self.answerContext)
        let stream = try await container.perform(
            nonSendable: (userInput, cacheCopy, cache.snapshot.state)
        ) { context, values in
            let input = try await context.processor.prepare(input: values.0)
            return try generate(
                input: input,
                cache: values.1,
                state: values.2,
                parameters: parameters,
                context: context)
        }
        var text = ""
        var metrics: GenerationMetrics?
        for try await generation in stream {
            switch generation {
            case .chunk(let chunk):
                text += chunk
            case .info(let info):
                metrics = GenerationMetrics(
                    promptTokenCount: info.promptTokenCount,
                    cachedPromptTokenCount: info.cachedPromptTokenCount + prefixTokenCount,
                    generationTokenCount: info.generationTokenCount,
                    promptTime: info.promptTime,
                    generationTime: info.generateTime)
            case .toolCall, .rejectedToolCall:
                break
            }
        }
        return (text, metrics)
    }

    private var generateParameters: GenerateParameters {
        GenerateParameters(
            maxTokens: configuration.maxTokens,
            temperature: configuration.temperature)
    }

    /// The system-prefix cache, built once. A failure clears the task so the
    /// next run retries it.
    private func promptCache() async throws -> PromptCacheHolder {
        if let promptCacheTask {
            return try await promptCacheTask.value
        }
        let container = try await modelContainer()
        let parameters = generateParameters
        let task = Task {
            try await Self.makePromptCache(container: container, parameters: parameters)
        }
        promptCacheTask = task
        do {
            return try await task.value
        } catch {
            promptCacheTask = nil
            throw error
        }
    }

    /// Prefills the system prefix into a fresh cache. The chat template renders
    /// the system message with a sentinel user turn; subtracting that user turn
    /// leaves the system prefix, which is the part every run shares.
    private nonisolated static func makePromptCache(
        container: ModelContainer,
        parameters: GenerateParameters
    ) async throws -> PromptCacheHolder {
        let systemPrompt = SystemPrompt.build()
        return try await container.perform(nonSendable: ()) { context, _ in
            let prefixTokens = try await systemPrefixTokens(context: context, prompt: systemPrompt)
            let input = LMInput(tokens: MLXArray(prefixTokens).expandedDimensions(axis: 0))
            let cache = try context.model.newCache(parameters: parameters)
            let iterator = try TokenIterator(
                input: input, model: context.model, cache: cache, parameters: parameters)
            guard cache.map(\.offset).max() == prefixTokens.count else {
                throw AgentEngineError.systemPromptCacheMismatch
            }
            return PromptCacheHolder(
                snapshot: PromptCacheSnapshot(cache: cache, state: iterator.state))
        }
    }

    private nonisolated static func systemPrefixTokens(
        context: ModelContext,
        prompt: String
    ) async throws -> [Int] {
        // A user turn is needed for the template to render at all; the same
        // sentinel in both renders makes the user turn a suffix of the full
        // render, so dropping it leaves the system prefix.
        let sentinel = "prefix"
        let full = try await context.processor.prepare(input: UserInput(
            chat: [.system(prompt), .user(sentinel)],
            additionalContext: systemPrefixContext))
        let userOnly = try await context.processor.prepare(input: UserInput(
            chat: [.user(sentinel)],
            additionalContext: systemPrefixContext))
        let fullTokens = full.text.tokens.asArray(Int.self)
        let userTokens = userOnly.text.tokens.asArray(Int.self)
        guard !userTokens.isEmpty,
              fullTokens.count > userTokens.count,
              Array(fullTokens.suffix(userTokens.count)) == userTokens
        else {
            throw AgentEngineError.noCacheableSystemPrefix
        }
        return Array(fullTokens.dropLast(userTokens.count))
    }

    @discardableResult
    private func modelContainer() async throws -> ModelContainer {
        if let containerTask {
            return try await containerTask.value
        }
        guard let directory = configuration.modelDirectory else {
            throw AgentEngineError.noModelDirectory
        }
        // The directory overload takes no `Downloader`, so the engine has no
        // path to the network even by mistake.
        let tokenizerLoader = configuration.tokenizerLoader
        let task = Task {
            try await loadModelContainer(from: directory, using: tokenizerLoader)
        }
        containerTask = task
        do {
            return try await task.value
        } catch {
            containerTask = nil
            throw error
        }
    }
}
