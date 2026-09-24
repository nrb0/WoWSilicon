import Foundation

enum GameArgumentsError: LocalizedError {
    case unterminatedQuote(String)
    case trailingEscape

    var errorDescription: String? {
        switch self {
        case .unterminatedQuote(let quoteCharacter):
            return "Unterminated \(quoteCharacter) quote."
        case .trailingEscape:
            return "Trailing backslash with nothing to escape."
        }
    }
}

// Splits command-line text into individual arguments and renders arguments back as a
// POSIX shell fragment.
enum GameArguments {
    /// Splits text into arguments using POSIX shell word-splitting rules: unquoted
    /// whitespace separates arguments, single quotes preserve their content literally,
    /// double quotes preserve their content except that a backslash escapes `"` and `\`,
    /// and an unquoted backslash escapes the character that follows it.
    ///
    /// - Parameter rawValue: Text to split.
    /// - Returns: Arguments in the order they appear. Empty when the text contains no arguments.
    /// - Throws: `GameArgumentsError.unterminatedQuote` when a quote is never closed,
    ///   `GameArgumentsError.trailingEscape` when the text ends with an unquoted backslash.
    static func parse(_ rawValue: String) throws -> [String] {
        var arguments: [String] = []
        var currentArgument = ""
        var hasCurrentArgument = false
        var activeQuote: Character?
        var pendingEscape = false

        for character in rawValue {
            if pendingEscape {
                // Inside double quotes a backslash is literal unless it precedes `"` or `\`.
                if activeQuote == "\"" && character != "\"" && character != "\\" {
                    currentArgument.append("\\")
                }
                currentArgument.append(character)
                hasCurrentArgument = true
                pendingEscape = false
                continue
            }

            if let quote = activeQuote {
                if quote == "\"" && character == "\\" {
                    pendingEscape = true
                } else if character == quote {
                    activeQuote = nil
                } else {
                    currentArgument.append(character)
                }
                continue
            }

            if character == "\\" {
                pendingEscape = true
                hasCurrentArgument = true
            } else if character == "\"" || character == "'" {
                activeQuote = character
                hasCurrentArgument = true
            } else if character.isWhitespace {
                if hasCurrentArgument {
                    arguments.append(currentArgument)
                    currentArgument = ""
                    hasCurrentArgument = false
                }
            } else {
                currentArgument.append(character)
                hasCurrentArgument = true
            }
        }

        if let quote = activeQuote {
            throw GameArgumentsError.unterminatedQuote(String(quote))
        }
        if pendingEscape {
            throw GameArgumentsError.trailingEscape
        }
        if hasCurrentArgument {
            arguments.append(currentArgument)
        }
        return arguments
    }

    /// Renders arguments as a space-separated shell fragment in which each argument is
    /// wrapped in single quotes, so no character in an argument is subject to shell
    /// expansion, word splitting, or filename globbing.
    ///
    /// - Parameter arguments: Arguments to render.
    /// - Returns: Shell fragment. Empty string when `arguments` is empty.
    static func makeShellFragment(_ arguments: [String]) -> String {
        arguments
            .map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            .joined(separator: " ")
    }
}
