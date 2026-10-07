import Foundation
import HuggingFace
import MLXLMCommon
import Tokenizers

/// Bridges the concrete `swift-huggingface` and `swift-transformers` types to the
/// `mlx-swift-lm` protocols. `mlx-swift-lm` ships macros that generate the same
/// two conformances; writing them out keeps the build independent of the macro
/// plugin, and pins the exact API surface this target relies on.
public enum HuggingFaceBridges {
    /// A `Downloader` backed by the default `HubClient` (cache plus HF endpoint).
    public static func downloader() -> any Downloader { HubDownloader() }

    /// A `TokenizerLoader` backed by `Tokenizers.AutoTokenizer`.
    public static func tokenizerLoader() -> any TokenizerLoader { TransformersTokenizerLoader() }

    struct HubDownloader: Downloader {
        private let client = HuggingFace.HubClient()

        func download(
            id: String,
            revision: String?,
            matching patterns: [String],
            useLatest: Bool,
            progressHandler: @Sendable @escaping (Progress) -> Void
        ) async throws -> URL {
            guard let repo = HuggingFace.Repo.ID(rawValue: id) else {
                throw AgentEngineError.invalidRepositoryID(id)
            }
            // `useLatest` is ignored: the hub client reconciles a cached snapshot
            // with the requested revision itself.
            return try await client.downloadSnapshot(
                of: repo,
                revision: revision ?? "main",
                matching: patterns,
                progressHandler: { @MainActor progress in progressHandler(progress) }
            )
        }
    }

    struct TransformersTokenizerLoader: TokenizerLoader {
        func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
            let upstream = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
            return TokenizerBridge(upstream: upstream)
        }
    }

    /// Maps `Tokenizers.Tokenizer` onto `MLXLMCommon.Tokenizer`. The two
    /// protocols differ only in `decode`'s label and in the error type.
    struct TokenizerBridge: MLXLMCommon.Tokenizer {
        let upstream: any Tokenizers.Tokenizer

        func encode(text: String, addSpecialTokens: Bool) -> [Int] {
            upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
        }

        func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
            upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
        }

        func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }

        func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

        var bosToken: String? { upstream.bosToken }
        var eosToken: String? { upstream.eosToken }
        var unknownToken: String? { upstream.unknownToken }

        func applyChatTemplate(
            messages: [[String: any Sendable]],
            tools: [[String: any Sendable]]?,
            additionalContext: [String: any Sendable]?
        ) throws -> [Int] {
            do {
                return try upstream.applyChatTemplate(
                    messages: messages, tools: tools, additionalContext: additionalContext)
            } catch Tokenizers.TokenizerError.missingChatTemplate {
                throw MLXLMCommon.TokenizerError.missingChatTemplate
            }
        }
    }
}
