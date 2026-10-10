import Core
import Foundation
import MLXLMCommon
import MLXVLM

/// A malformed model id reaching the downloader. Validation outcomes are never
/// errors: a reply without a catalog id is emitted as `.failed`, not thrown.
public enum AgentEngineError: Error, LocalizedError {
    case invalidRepositoryID(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRepositoryID(let id):
            "Invalid Hugging Face repository id: \(id). Expected \"namespace/name\"."
        }
    }
}

/// The MLX VLM implementation of `AgentRunning` (design doc §3, §11.6). Each run
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
        /// The smallest model that held up on the reference set: fast enough to
        /// feel like a dialogue and strong enough to honour the no-repeat list.
        /// The 9B is more capable but too slow; the 2B cannot follow the list.
        /// See `Agent/README.md`.
        public static let defaultModelID = "mlx-community/Qwen3.5-4B-MLX-4bit"

        /// The snapshot commit a download resolves to when the caller does not
        /// pin one. A mutable ref like `main` would let the hub serve different
        /// weights on a later run; the commits keep the download reproducible.
        /// Both hashes are verified in `Models/README.md`. An unrecognized id
        /// stays on `main`.
        static func pinnedRevision(for modelID: String) -> String {
            switch modelID {
            case "mlx-community/Qwen3.5-4B-MLX-4bit": "32f3e8ecf65426fc3306969496342d504bfa13f3"
            case "mlx-community/Qwen3.5-9B-4bit": "8b2b98c00a6b4d291155e4890773ca8f769aee53"
            default: "main"
            }
        }

        public var modelID: String
        public var revision: String
        /// When set, the model is loaded from this local snapshot directory and
        /// nothing is downloaded. `loadModelContainer` ignores the downloader
        /// for a `.directory` configuration, so the app can run fully offline.
        public var modelDirectory: URL?
        public var maxTokens: Int
        public var temperature: Float
        public var downloader: any Downloader
        public var tokenizerLoader: any TokenizerLoader
        public var progressHandler: @Sendable (Progress) -> Void

        public init(
            modelID: String = Configuration.defaultModelID,
            revision: String? = nil,
            modelDirectory: URL? = nil,
            maxTokens: Int = 900,
            temperature: Float = 0.2,
            downloader: any Downloader = HuggingFaceBridges.downloader(),
            tokenizerLoader: any TokenizerLoader = HuggingFaceBridges.tokenizerLoader(),
            progressHandler: @escaping @Sendable (Progress) -> Void = { _ in }
        ) {
            self.modelID = modelID
            self.revision = revision ?? Configuration.pinnedRevision(for: modelID)
            self.modelDirectory = modelDirectory
            self.maxTokens = maxTokens
            self.temperature = temperature
            self.downloader = downloader
            self.tokenizerLoader = tokenizerLoader
            self.progressHandler = progressHandler
        }

        /// Reads `RATER_MODEL_PATH` (a local snapshot directory). When it is
        /// unset the engine downloads `modelID` through `HubDownloader` instead.
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

        /// The configuration `loadModelContainer` resolves: a local snapshot
        /// directory when set, otherwise a hub id to download.
        func modelConfiguration() -> ModelConfiguration {
            if let modelDirectory {
                return ModelConfiguration(directory: modelDirectory)
            }
            return ModelConfiguration(id: modelID, revision: revision)
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
        let configuration = self.configuration
        let task = Task {
            try await loadModelContainer(
                from: configuration.downloader,
                using: configuration.tokenizerLoader,
                configuration: configuration.modelConfiguration(),
                progressHandler: configuration.progressHandler
            )
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
