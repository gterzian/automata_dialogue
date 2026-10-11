import Foundation
import MLXLMCommon
import Tokenizers

/// Bridges the concrete `swift-transformers` types to the `mlx-swift-lm`
/// protocols. `mlx-swift-lm` ships a macro that generates the same conformance;
/// writing it out keeps the build independent of the macro plugin, and pins the
/// exact API surface this target relies on.
///
/// Only the tokenizer bridge is needed: the engine loads a local snapshot
/// directory and never downloads, so it supplies no `Downloader`.
public enum HuggingFaceBridges {
    /// A `TokenizerLoader` backed by `Tokenizers.AutoTokenizer`.
    public static func tokenizerLoader() -> any TokenizerLoader { TransformersTokenizerLoader() }

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
