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
/// There is no tool call and no second generation round: the model replies with
/// an `id:` line, and `ChoiceParser` reads the chosen entry out of the text. A
/// reply without a catalog id fails the run.
public actor AgentEngine: AgentRunning {
    public struct Configuration: Sendable {
        /// The local Hugging Face snapshot directory to load. Models are never
        /// downloaded: a configuration with no directory fails the run. See
        /// `Models/README.md` for the snapshots and `Agent/README.md`.
        public var modelDirectory: URL?
        public var maxTokens: Int
        public var temperature: Float
        public var tokenizerLoader: any TokenizerLoader

        public init(
            modelDirectory: URL? = nil,
            maxTokens: Int = 900,
            temperature: Float = 0.2,
            tokenizerLoader: any TokenizerLoader = HuggingFaceBridges.tokenizerLoader()
        ) {
            self.modelDirectory = modelDirectory
            self.maxTokens = maxTokens
            self.temperature = temperature
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
    Your previous answer did not name a usable id. Reply with exactly two lines and nothing else:
    id: <one id from the list, not one of the recently used ids>
    reason: <one sentence naming the class you matched and why it fits>
    """

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
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
                // Thinking is off, so the model answers instead of spending
                // tokens on a reasoning preamble before the `id:` line.
                additionalContext: ["enable_thinking": false]
            )

            let image = input.imageURL.map { UserInput.Image.url($0) }
            var response = try await session.respond(to: prompt, image: image)
            var choice = Self.allowed(ChoiceParser.choice(from: response), excluding: excluded)
            // One repair turn if the model named no usable id (an unknown id,
            // or one the history excluded); the dispatcher-era repair, kept as
            // a single retry. The session still holds the image.
            if choice == nil, !response.isEmpty {
                response = try await session.respond(to: Self.repairPrompt)
                choice = Self.allowed(ChoiceParser.choice(from: response), excluding: excluded)
            }
            if !response.isEmpty { continuation.yield(.text(response)) }

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
