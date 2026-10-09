import Core
import Foundation
import MLXLMCommon
import MLXVLM

/// Failures specific to driving the model. Validation outcomes are never errors:
/// `ToolDispatcher` returns corrective strings, so only these two conditions
/// end a run.
public enum AgentEngineError: Error, LocalizedError {
    case invalidRepositoryID(String)
    case toolCallLimit

    public var errorDescription: String? {
        switch self {
        case .invalidRepositoryID(let id):
            "Invalid Hugging Face repository id: \(id). Expected \"namespace/name\"."
        case .toolCallLimit:
            "The model exceeded the tool-call limit before choosing an automaton."
        }
    }
}

/// The MLX VLM implementation of `AgentRunning` (design doc §3, §11.6). Each run
/// is one self-contained turn: a fresh `ChatSession` carries the immutable system
/// prompt, the current input, and the tool exchange, so latency is constant and
/// the prompt prefix is cacheable. The model container is loaded once and shared
/// across runs.
///
/// The `toolDispatch` closure converts `mlx-swift-lm`'s `ToolCall` into `Core`'s
/// `ToolInvocation` and hands it to the shared `ToolDispatcher`, which emits the
/// rating and choice cards and returns a corrective string for anything invalid.
public actor AgentEngine: AgentRunning {
    public struct Configuration: Sendable {
        /// Default for the target machines; the 4B entry is the 16 GB fallback.
        public static let defaultModelID = "mlx-community/Qwen3.5-9B-4bit"
        public static let fallbackModelID = "mlx-community/Qwen3.5-4B-4bit"

        /// The snapshot commit a download resolves to when the caller does not
        /// pin one. A mutable ref like `main` would let the hub serve different
        /// weights on a later run; the commit keeps the download reproducible.
        /// Only the default is pinned — its hash is verified in
        /// `Models/README.md`. An unrecognized id (including `fallbackModelID`)
        /// stays on `main`.
        static func pinnedRevision(for modelID: String) -> String {
            modelID == defaultModelID ? "8b2b98c00a6b4d291155e4890773ca8f769aee53" : "main"
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
            let container = try await modelContainer()
            let dispatcher = ToolDispatcher(catalog: Catalog.all) { event in
                continuation.yield(event)
            }
            let session = ChatSession(
                container,
                instructions: SystemPrompt.build(),
                generateParameters: GenerateParameters(
                    maxTokens: configuration.maxTokens,
                    temperature: configuration.temperature
                ),
                additionalContext: ["enable_thinking": false],
                tools: ToolSchemas.all,
                toolDispatch: { call in
                    let result = await dispatcher.handle(Self.invocation(from: call))
                    if await dispatcher.didFail {
                        // The dispatcher already emitted `.failed`; ending the
                        // stream stops the model from looping on the limit.
                        throw AgentEngineError.toolCallLimit
                    }
                    return result
                }
            )

            let images = input.imageURL.map { [UserInput.Image.url($0)] } ?? []
            var closingSentence = ""
            for try await chunk in session.streamResponse(to: input.text, images: images) {
                // Buffer the assistant text so the closing sentence always lands
                // after the rating and choice cards, whatever the model emits
                // before its tool calls.
                closingSentence += chunk
            }

            let phase = await dispatcher.phase
            if await dispatcher.didFail {
                continuation.finish()
            } else if phase.isDone {
                if !closingSentence.isEmpty { continuation.yield(.text(closingSentence)) }
                continuation.yield(.finished)
                continuation.finish()
            } else {
                continuation.yield(.failed("the model finished without rating and choosing"))
                continuation.finish()
            }
        } catch {
            if let agentError = error as? AgentEngineError, case .toolCallLimit = agentError {
                // `.failed` was emitted by the dispatcher.
                continuation.finish()
            } else {
                continuation.yield(.failed(error.localizedDescription))
                continuation.finish()
            }
        }
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

    /// Converts one `mlx-swift-lm` tool call into the `Core` value the dispatcher
    /// validates. The two `JSONValue` enums are structurally identical.
    static func invocation(from call: ToolCall) -> ToolInvocation {
        ToolInvocation(
            name: call.function.name,
            arguments: call.function.arguments.mapValues(jsonValue),
            id: call.id
        )
    }

    private static func jsonValue(_ value: MLXLMCommon.JSONValue) -> Core.JSONValue {
        switch value {
        case .null: .null
        case .bool(let bool): .bool(bool)
        case .int(let int): .int(int)
        case .double(let double): .double(double)
        case .string(let string): .string(string)
        case .array(let array): .array(array.map(jsonValue))
        case .object(let object): .object(object.mapValues(jsonValue))
        }
    }
}
