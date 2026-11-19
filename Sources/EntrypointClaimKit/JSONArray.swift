/// A strict JSON reader for the one shape Docker cares about, matching Go's `encoding/json`: a top-level array. No
/// trailing commas, no comments, no single quotes, no raw control characters in strings (Foundation's reader is more
/// lenient, so it is not used).
enum JSONArray {
    enum Result: Equatable {
        /// An array of strings.
        case strings([String])
        /// Valid JSON, but an array holding something else, or not an array.
        case notStrings
        /// Not JSON.
        case invalid
    }

    static func parse(_ text: String) -> Result {
        var reader = Reader(Array(text.unicodeScalars))
        guard let value = reader.value() else { return .invalid }
        reader.skipSpace()
        guard reader.atEnd else { return .invalid }
        guard case let .array(items) = value else { return .notStrings }
        let strings = items.compactMap { item -> String? in
            if case let .string(string) = item { return string }
            return nil
        }
        return strings.count == items.count ? .strings(strings) : .notStrings
    }

    indirect enum Value {
        case string(String)
        case array([Value])
        case other
    }

    struct Reader {
        let scalars: [Unicode.Scalar]
        var index = 0

        init(_ scalars: [Unicode.Scalar]) {
            self.scalars = scalars
        }

        var atEnd: Bool { index == scalars.count }
        var current: Unicode.Scalar? { atEnd ? nil : scalars[index] }

        mutating func skipSpace() {
            while let scalar = current, [" ", "\t", "\n", "\r"].contains(scalar) { index += 1 }
        }

        mutating func value() -> Value? {
            skipSpace()
            switch current {
            case "[": return array()
            case "{": return object()
            case "\"": return string().map(Value.string)
            case "t": return literal("true")
            case "f": return literal("false")
            case "n": return literal("null")
            default: return number()
            }
        }

        mutating func array() -> Value? {
            index += 1
            skipSpace()
            var items: [Value] = []
            if current != "]" {
                repeat {
                    guard let item = value() else { return nil }
                    items.append(item)
                    skipSpace()
                } while consume(",")
            }
            return consume("]") ? .array(items) : nil
        }

        mutating func object() -> Value? {
            index += 1
            skipSpace()
            if current != "}" {
                repeat {
                    skipSpace()
                    guard current == "\"", string() != nil else { return nil }
                    skipSpace()
                    guard consume(":"), value() != nil else { return nil }
                    skipSpace()
                } while consume(",")
            }
            return consume("}") ? .other : nil
        }

        mutating func consume(_ scalar: Unicode.Scalar) -> Bool {
            guard current == scalar else { return false }
            index += 1
            return true
        }

        mutating func literal(_ word: String) -> Value? {
            let expected = Array(word.unicodeScalars)
            guard index + expected.count <= scalars.count,
                  Array(scalars[index..<index + expected.count]) == expected else { return nil }
            index += expected.count
            return .other
        }

        /// `-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?`
        mutating func number() -> Value? {
            if current == "-" { index += 1 }
            if current == "0" {
                index += 1
            } else {
                guard digits() else { return nil }
            }
            if current == "." {
                index += 1
                guard digits() else { return nil }
            }
            if current == "e" || current == "E" {
                index += 1
                if current == "+" || current == "-" { index += 1 }
                guard digits() else { return nil }
            }
            return .other
        }

        mutating func digits() -> Bool {
            let start = index
            while let scalar = current, ("0"..."9").contains(scalar) { index += 1 }
            return index > start
        }

        mutating func string() -> String? {
            index += 1
            var result = String.UnicodeScalarView()
            while let scalar = current {
                index += 1
                switch scalar {
                case "\"": return String(result)
                case "\\":
                    guard let escaped = escape() else { return nil }
                    result.append(escaped)
                default:
                    guard scalar.value >= 0x20 else { return nil }
                    result.append(scalar)
                }
            }
            return nil
        }

        mutating func escape() -> Unicode.Scalar? {
            guard let scalar = current else { return nil }
            index += 1
            let simple: [Unicode.Scalar: Unicode.Scalar] = ["\"": "\"", "\\": "\\", "/": "/", "b": "\u{8}",
                                                            "f": "\u{C}", "n": "\n", "r": "\r", "t": "\t"]
            if let mapped = simple[scalar] { return mapped }
            guard scalar == "u", let high = hex() else { return nil }
            if (0xD800...0xDBFF).contains(high), current == "\\", index + 1 < scalars.count, scalars[index + 1] == "u" {
                let saved = index
                index += 2
                if let low = hex(), (0xDC00...0xDFFF).contains(low) {
                    return Unicode.Scalar(0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00))
                }
                index = saved
            }
            return Unicode.Scalar(high) ?? "\u{FFFD}"
        }

        mutating func hex() -> UInt32? {
            guard index + 4 <= scalars.count else { return nil }
            let text = String(String.UnicodeScalarView(scalars[index..<index + 4]))
            guard let value = UInt32(text, radix: 16), text.allSatisfy(\.isHexDigit) else { return nil }
            index += 4
            return value
        }
    }
}
