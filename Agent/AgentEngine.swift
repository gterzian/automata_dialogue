import Core
import Foundation
import MLXLMCommon
import MLXVLM

/// A configuration error that stops a run before generation. Downloads are
/// disabled, so a configuration with no local snapshot directory is fatal
/// instead of something to fetch.
public enum AgentEngineError: Error, LocalizedError {
    case noModelDirectory

    public var errorDescription: String? {
        switch self {
        case .noModelDirectory:
            "No local model snapshot configured. Set RATER_MODEL_PATH or pass --model <dir>; network downloads are disabled."
        }
    }
}

/// The MLX VLM implementation of `AgentRunning`. Each run
/// is one self-contained turn: a fresh `ChatSession` carries the immutable system
/// prompt, the current input, and a single plain-text answer, so latency is
/// constant and the prompt prefix is cacheable. The model container is loaded
/// once and shared across runs.
///
/// There is no tool call and no tool-dispatch round: the model replies with an
/// `id:` line, and `ChoiceParser` reads the chosen entry out of the text. A
/// reply without a catalog id gets one repair turn; a second miss fails the
/// run.
public actor AgentEngine: AgentRunning {
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
    /// Recent choices, carried across runs. `perform` turns it into the
    /// user-turn exclusion note, so the dialogue never repeats an automaton.
    private var history = ChoiceHistory()

    /// One repair turn when the model's answer names no usable id (an unknown
    /// id, or one the harness excluded). The session still holds the image, so
    /// the retry sees the same input.
    private static let repairPrompt = """
    Your previous answer did not name a usable id. Reply with exactly three lines and nothing else:
    class: <one of repetition, nesting, randomness, complexity>
    id: <one id from the list whose class is the class on the first line, not one of the recently used ids>
    reason: <one full sentence, not just the class name: the visible feature you matched, then the class it puts the drawing in>
    """

    /// Keeps the already chosen id and asks only for the sentence the answer
    /// format requires.
    private static let reasonRepairPrompt = """
    Your previous answer's reason was not a full sentence. Reply with exactly three lines and nothing else, keeping the same id:
    class: <the class printed after that id in the list>
    id: <the id from your previous answer>
    reason: <one full sentence, not just the class name: the visible feature you matched, then the class it puts the drawing in>
    """

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Loads the shared container so the first `run` does not also pay the
    /// weight load. The load is cached and a failure is retried, so a failed
    /// preload is not fatal: the first `run` reports the error again.
    public func prepare() async throws {
        try await modelContainer()
    }

    /// Drops the recent-choice window, so the next run is not asked to avoid
    /// earlier ids. `classify` uses it to measure each image's class
    /// independently of the others.
    public func resetHistory() {
        history = ChoiceHistory()
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
            let excluded = Set(history.excludedIDs)
            let prompt = history.userTurn(input.text)
            let container = try await modelContainer()
            let session = ChatSession(
                container,
                instructions: SystemPrompt.build(),
                generateParameters: GenerateParameters(
                    maxTokens: configuration.maxTokens,
                    temperature: configuration.temperature
                ),
                processing: UserInput.Processing(
                    resize: CGSize(
                        width: configuration.imageDimension,
                        height: configuration.imageDimension)),
                // Thinking is off, so the model answers instead of spending
                // tokens on a reasoning preamble before the `id:` line.
                additionalContext: ["enable_thinking": false]
            )

            let image = input.imageURL.map { UserInput.Image.url($0) }
            let first = try await answer(session, to: prompt, image: image)
            var response = first.text
            var choice = Self.allowed(ChoiceParser.choice(from: response), excluding: excluded)
            var passes = first.metrics.map { [$0] } ?? []
            // One repair turn if the model named no usable id (an unknown id,
            // or one the history excluded); the dispatcher-era repair, kept as
            // a single retry. The session still holds the image.
            if choice == nil, !response.isEmpty {
                let repaired = try await answer(session, to: Self.repairPrompt, image: nil)
                response = repaired.text
                if let metrics = repaired.metrics { passes.append(metrics) }
                choice = Self.allowed(ChoiceParser.choice(from: response), excluding: excluded)
            }
            // A usable id with a label instead of a reason gets one more turn.
            // Keep the first choice when the retry does not improve it; the
            // exchange is about the automaton, and a terse reason must not end
            // it.
            if let valid = choice, !valid.hasFullReason, !response.isEmpty {
                let repaired = try await answer(session, to: Self.reasonRepairPrompt, image: nil)
                if let metrics = repaired.metrics { passes.append(metrics) }
                if let retried = Self.allowed(
                    ChoiceParser.choice(from: repaired.text), excluding: excluded),
                   retried.hasFullReason {
                    response = repaired.text
                    choice = retried
                }
            }
            if !response.isEmpty { continuation.yield(.text(response)) }
            for metrics in passes { continuation.yield(.metrics(metrics)) }

            if let choice {
                history.record(choice.id)
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

    private nonisolated static func allowed(_ choice: Choice?, excluding excluded: Set<String>) -> Choice? {
        guard let choice, !excluded.contains(choice.id) else { return nil }
        return choice
    }

    /// One generation pass over `prompt`; returns the full text and, when the
    /// model reported it, the completion metrics. `image` is nil on the repair
    /// turn because the session already holds the image from the first turn.
    private func answer(
        _ session: ChatSession,
        to prompt: String,
        image: UserInput.Image?
    ) async throws -> (text: String, metrics: GenerationMetrics?) {
        var text = ""
        var metrics: GenerationMetrics?
        for try await generation in session.streamDetails(
            to: prompt, images: image.map { [$0] } ?? []
        ) {
            switch generation {
            case .chunk(let chunk):
                text += chunk
            case .info(let info):
                metrics = GenerationMetrics(
                    promptTokenCount: info.promptTokenCount,
                    cachedPromptTokenCount: info.cachedPromptTokenCount,
                    generationTokenCount: info.generationTokenCount,
                    promptTime: info.promptTime,
                    generationTime: info.generateTime)
            case .toolCall, .rejectedToolCall:
                break
            }
        }
        return (text, metrics)
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
