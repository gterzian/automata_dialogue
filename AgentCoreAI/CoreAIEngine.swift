import Core
import CoreAILanguageModels
import Foundation
import Tokenizers

/// A configuration error that stops a run before generation. The engine loads
/// a directory and never downloads, so a configuration with no bundle
/// directory is fatal instead of something to fetch.
public enum CoreAIEngineError: Error, LocalizedError {
    case noBundleDirectory
    case requiresAnImage
    case notAVisionBundle
    case noImagePlaceholder

    public var errorDescription: String? {
        switch self {
        case .noBundleDirectory:
            "No local Core AI bundle configured. Set RATER_AIMODEL_PATH or pass --aimodel <dir>; network downloads are disabled."
        case .requiresAnImage:
            "The Core AI backend needs an image for every run; this input carried none."
        case .notAVisionBundle:
            "The Core AI bundle has no vision encoder, so it cannot read the drawing. Export a vision-language bundle; see AgentCoreAI/README.md."
        case .noImagePlaceholder:
            "The bundle's chat template produced no image placeholder, so the vision embeddings have nowhere to go."
        }
    }
}

/// The Core AI implementation of `AgentSession`. It runs an exported Core AI
/// bundle (`.aimodel` files plus their resources) on the same system prompt, the
/// same normalized image, and the same answer parsing as the MLX engine, so
/// `rater-cli bench` can time the two runtimes on the same inputs.
///
/// A bundle must carry a vision encoder: every input here is a drawing. The
/// bundle's own tokenizer renders the chat template, so this backend submits
/// the system prompt as the first chat turn too.
public actor CoreAIEngine: AgentSession {
    public struct Configuration: Sendable {
        /// The exported bundle directory. Models are never downloaded: a
        /// configuration with no directory fails the run. See
        /// `Models/README.md` for the bundles and `AgentCoreAI/README.md` for
        /// how one is exported.
        public var bundleDirectory: URL?
        public var maxTokens: Int
        public var temperature: Float

        public init(
            bundleDirectory: URL? = nil,
            maxTokens: Int = 100,
            temperature: Float = 0.2
        ) {
            self.bundleDirectory = bundleDirectory
            self.maxTokens = maxTokens
            self.temperature = temperature
        }

        /// Reads `RATER_AIMODEL_PATH` (a local bundle directory). Downloads are
        /// disabled, so an unset path leaves `bundleDirectory` nil and the run
        /// fails when it tries to load.
        public static func fromEnvironment(
            _ environment: [String: String] = ProcessInfo.processInfo.environment
        ) -> Configuration {
            var configuration = Configuration()
            if let path = environment["RATER_AIMODEL_PATH"], !path.isEmpty {
                configuration.bundleDirectory = URL(
                    fileURLWithPath: NSString(string: path).expandingTildeInPath,
                    isDirectory: true)
            }
            return configuration
        }
    }

    public nonisolated let backend = AgentBackend.coreAI

    private let configuration: Configuration
    /// One load shared by every run; cleared on failure so a later run retries.
    private var bundleTask: Task<LoadedBundle, Error>?
    /// Recent choices, carried across runs, so the dialogue never repeats an
    /// automaton. Shared with the MLX engine through `AgentDialogue`.
    private var dialogue = AgentDialogue()
    /// The tokens the previous run submitted successfully, used to report how
    /// much of this run's prompt an engine with a token history reused.
    private var previousPromptTokens: [Int32]?
    /// The bundle's engine holds one KV cache and one generation at a time, so
    /// a second run waits instead of resetting the first one's state.
    private var isGenerating = false
    private var waitingForEngine: [CheckedContinuation<Void, Never>] = []

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Loads the bundle and builds its engine so the first `run` does not also
    /// pay that cost. A failure is retried by the first `run`.
    public func prepare() async throws {
        _ = try await loadedBundle()
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

    /// The loaded bundle plus the pieces a prompt needs. Everything here is
    /// immutable after loading, so runs can share it.
    private struct LoadedBundle: Sendable {
        let engine: any MultimodalInferenceEngine
        let tokenizer: any Tokenizer
        let vision: VisionConfig
        let stopTokenIDs: Set<Int32>

        /// Whether this bundle's engine keeps a token history, so a run that
        /// repeats an earlier prompt's prefix prefills only from the first
        /// difference. `EngineFactory` picks the engine from `vision.tokenMerge`:
        /// the static-shape engine for `decoderGather` bundles reuses a prefix,
        /// while the sequential engine `separateEmbedding` bundles get (the
        /// Qwen-VL family) takes the whole token array on every prefill.
        var reusesPrefix: Bool { vision.tokenMerge == .decoderGather }

        /// The prompt tokens for one submission. The bundle's chat template
        /// renders the system prompt and the user turn the model was trained
        /// to read, and the single image placeholder becomes one token per
        /// visual embedding the encoder produces. This is the prompt shape
        /// Core AI's own `CoreAIVisionLanguageModel` builds.
        func promptTokens(system: String, user: String, imageTokenCount: Int) throws -> [Int32] {
            let placeholder = tokenizer.convertIdToToken(Int(vision.imageTokenId))
                ?? "<|image_pad|>"
            let messages: [[String: any Sendable]] = [
                ["role": "system", "content": system],
                ["role": "user", "content": "\(placeholder)\n\(user)"],
            ]
            var tokens: [Int32] = []
            var expanded = false
            for token in try tokenizer.applyChatTemplate(messages: messages) {
                let id = Int32(token)
                guard id == vision.imageTokenId else {
                    tokens.append(id)
                    continue
                }
                // The template writes one placeholder for the whole image; the
                // decoder scatters the encoder's embeddings into that run.
                guard !expanded else { continue }
                tokens.append(contentsOf: [Int32](repeating: id, count: imageTokenCount))
                expanded = true
            }
            guard expanded else { throw CoreAIEngineError.noImagePlaceholder }
            return tokens
        }
    }

    private func perform(
        _ input: AgentInput,
        into continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async {
        do {
            let turn = dialogue.turn(for: input.text)
            let bundle = try await loadedBundle()
            let result = try await answer(bundle, to: turn.prompt, imageURL: input.imageURL)
            let response = result.text
            if !response.isEmpty { continuation.yield(.text(response)) }
            continuation.yield(.metrics(result.metrics))

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

    /// One generation pass over `prompt`. When the engine keeps a token history
    /// the run submits the whole prompt and the engine prefills only what
    /// followed the previous one; otherwise the prompt is prefilled in full.
    private func answer(
        _ bundle: LoadedBundle,
        to prompt: String,
        imageURL: URL?
    ) async throws -> (text: String, metrics: GenerationMetrics) {
        guard let imageURL else { throw CoreAIEngineError.requiresAnImage }
        await acquireEngine()
        defer { releaseEngine() }

        let clock = ContinuousClock()
        let started = clock.now
        let image = try await bundle.engine.encodeImage(at: imageURL)
        let tokens = try bundle.promptTokens(
            system: SystemPrompt.build(),
            user: prompt,
            imageTokenCount: image.tokenCount)
        // The system prompt is the same on every run, so it is the reusable
        // prefix. The image's embeddings are this run's own, so the engine's
        // history reaches only to the first image placeholder.
        let cachedTokens = bundle.reusesPrefix
            ? PromptPrefix.reusableLength(
                of: tokens,
                after: previousPromptTokens ?? [],
                imageTokenID: bundle.vision.imageTokenId)
            : 0
        if !bundle.reusesPrefix {
            try await bundle.engine.reset()
        }
        let stream = try await bundle.engine.generate(
            with: image,
            tokens: tokens,
            samplingConfiguration: SamplingConfiguration(
                temperature: Double(configuration.temperature)),
            inferenceOptions: .extend(maxTokens: configuration.maxTokens))

        var generated: [Int] = []
        var promptSeconds: Double?
        do {
            for try await output in stream {
                if promptSeconds == nil { promptSeconds = started.seconds(to: clock.now) }
                if bundle.stopTokenIDs.contains(output.tokenId) { break }
                generated.append(Int(output.tokenId))
            }
        } catch {
            // A pass that failed partway leaves the engine's history shorter than
            // the prompt, so the next run must not claim a prefix it cannot rely
            // on until it has submitted the whole prompt once again.
            previousPromptTokens = nil
            throw error
        }
        let totalSeconds = started.seconds(to: clock.now)
        previousPromptTokens = tokens
        // The first token marks the end of the prefill, which includes the
        // vision encoder and the prompt processing.
        let promptTime = promptSeconds ?? totalSeconds
        return (
            text: bundle.tokenizer.decode(tokens: generated),
            metrics: GenerationMetrics(
                promptTokenCount: tokens.count - cachedTokens,
                cachedPromptTokenCount: cachedTokens,
                generationTokenCount: generated.count,
                promptTime: promptTime,
                generationTime: max(0, totalSeconds - promptTime))
        )
    }

    private func acquireEngine() async {
        guard isGenerating else {
            isGenerating = true
            return
        }
        await withCheckedContinuation { waitingForEngine.append($0) }
    }

    private func releaseEngine() {
        guard !waitingForEngine.isEmpty else {
            isGenerating = false
            return
        }
        // Hand the engine straight to the next waiter, which stays "generating".
        waitingForEngine.removeFirst().resume()
    }

    private func loadedBundle() async throws -> LoadedBundle {
        if let bundleTask {
            return try await bundleTask.value
        }
        guard let directory = configuration.bundleDirectory else {
            throw CoreAIEngineError.noBundleDirectory
        }
        let task = Task { try await Self.loadBundle(at: directory) }
        bundleTask = task
        do {
            return try await task.value
        } catch {
            bundleTask = nil
            throw error
        }
    }

    private nonisolated static func loadBundle(at directory: URL) async throws -> LoadedBundle {
        let bundle = try LanguageModelBundle(at: directory)
        guard let vision = bundle.visionConfig else {
            throw CoreAIEngineError.notAVisionBundle
        }
        let tokenizer = try await bundle.loadTokenizer()
        let engine = try await EngineFactory.createEngine(
            bundle: bundle, options: EngineOptions())
        guard let multimodal = engine as? any MultimodalInferenceEngine else {
            throw CoreAIEngineError.notAVisionBundle
        }
        return LoadedBundle(
            engine: multimodal,
            tokenizer: tokenizer,
            vision: vision,
            stopTokenIDs: stopTokenIDs(for: bundle, tokenizer: tokenizer))
    }

    /// The tokens that end a turn: the bundle's own end-of-turn ids, the
    /// tokenizer's EOS, and the chat template's `<|im_end|>`. The bundle's
    /// helper for this is internal, so the set is assembled here.
    private nonisolated static func stopTokenIDs(
        for bundle: LanguageModelBundle,
        tokenizer: any Tokenizer
    ) -> Set<Int32> {
        var ids = Set<Int32>()
        if let directory = bundle.tokenizerPath {
            ids.formUnion(LanguageConfig.additionalStopTokenIds(
                from: directory, tokenizer: tokenizer))
        }
        if let eos = tokenizer.eosTokenId { ids.insert(Int32(eos)) }
        if let endOfTurn = tokenizer.convertTokenToId("<|im_end|>") {
            ids.insert(Int32(endOfTurn))
        }
        return ids
    }
}

private extension ContinuousClock.Instant {
    /// Seconds elapsed from this instant to `end`.
    func seconds(to end: ContinuousClock.Instant) -> Double {
        let duration = self.duration(to: end)
        return Double(duration.components.seconds)
            + Double(duration.components.attoseconds) * 1e-18
    }
}
