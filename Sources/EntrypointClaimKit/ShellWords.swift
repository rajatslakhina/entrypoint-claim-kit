/// Splits a command line into words the way a POSIX shell does for plain words: single quotes keep everything,
/// inside double quotes a backslash escapes only `$`, `` ` ``, `"` and `\`, and outside quotes a backslash keeps the
/// next character.
/// Expansions (`$VAR`, globs) are not performed: the words come back as written.
enum ShellWords {
    /// The words, or `nil` when a quote is left open.
    static func split(_ text: String) -> [String]? {
        var words: [String] = []
        var current = ""
        var inWord = false
        var quote: Character?
        var escaped = false
        for character in text {
            if escaped {
                if quote == "\"", !"$`\"\\".contains(character) { current.append("\\") }
                current.append(character)
                escaped = false
            } else if let open = quote {
                inQuote(character, open: open, quote: &quote, escaped: &escaped, current: &current)
            } else if character == "\\" {
                escaped = true
                inWord = true
            } else if character == "'" || character == "\"" {
                quote = character
                inWord = true
            } else if character.isWhitespace {
                if inWord { words.append(current) }
                current = ""
                inWord = false
            } else {
                current.append(character)
                inWord = true
            }
        }
        guard quote == nil else { return nil }
        if inWord { words.append(current) }
        return words
    }

    /// One character inside quotes: the closing quote ends them, a backslash in double quotes may escape the next.
    static func inQuote(_ character: Character, open: Character, quote: inout Character?, escaped: inout Bool,
                        current: inout String) {
        if character == open {
            quote = nil
        } else if open == "\"", character == "\\" {
            escaped = true
        } else {
            current.append(character)
        }
    }

    /// Whether a shell script does more than run one plain command: lists, pipes, redirections, expansions or
    /// subshells. Such a script is compared as text, never word by word.
    static func isCompound(_ script: String) -> Bool {
        script.contains { "&|;<>$`(){}*?[~#\n".contains($0) }
    }
}
