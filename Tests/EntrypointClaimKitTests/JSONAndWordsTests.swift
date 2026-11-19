import Testing
@testable import EntrypointClaimKit

@Suite("Strict JSON arrays")
struct JSONArrayTests {
    @Test("Arrays of strings", arguments: [
        ("[]", [String]()), ("[ ]", []), (#"["a"]"#, ["a"]), (#"[ "a" , "b c" ]"#, ["a", "b c"]),
        (#"["say \"hi\""]"#, [#"say "hi""#]), (#"["C:\\dir"]"#, [#"C:\dir"#]), (#"["a\/b"]"#, ["a/b"]),
        (#"["\b\f\n\r\t"]"#, ["\u{8}\u{C}\n\r\t"]), (#"["\u00e9"]"#, ["é"]), (#"["\ud83d\ude00"]"#, ["😀"]),
        (#"["\ud83dx"]"#, ["\u{FFFD}x"]), (#"["\ud83d\u0041"]"#, ["\u{FFFD}A"]), ("[\"a\"]\n ", ["a"])
    ])
    func strings(_ text: String, _ words: [String]) {
        #expect(JSONArray.parse(text) == .strings(words))
    }

    @Test("Valid JSON that is not an array of strings", arguments: [
        #"["a", 1]"#, "[true]", "[false, null]", "[-1.5e+3]", "[0, 10, 2.25, 3E2]", #"[{}]"#, #"[{"a": [1, "b"], "c": {}}]"#,
        #"[["x"]]"#, "{}", #""text""#
    ])
    func notStrings(_ text: String) {
        #expect(JSONArray.parse(text) == .notStrings)
    }

    @Test("Not JSON", arguments: [
        "", "['a']", #"["a",]"#, #"["a""#, #"["a"] x"#, "[01]", "[1.]", "[1e]", "[-]", "[tru]", #"["\q"]"#,
        #"["\u12"]"#, #"["\u12zz"]"#, "[\"a\u{1}\"]", #"[{"a" 1}]"#, #"[{"a": 1,}]"#, "[{1: 2}]", #"[{"a": }]"#,
        #"[{"a": 1 "b": 2}]"#, "[1 2]", #"["\"#, "[", "[nul]", "[\"abc", "{\"a\": 1", "[1,"
    ])
    func invalid(_ text: String) {
        #expect(JSONArray.parse(text) == .invalid)
    }
}

@Suite("Shell words")
struct ShellWordsTests {
    @Test("Words as a shell splits them", arguments: [
        ("node server.js", ["node", "server.js"]), ("  a   b  ", ["a", "b"]), ("'a b' c", ["a b", "c"]),
        (#""a \"b\" \\ \$ \q" c"#, [#"a "b" \ $ \q"#, "c"]), (#"a\ b"#, ["a b"]), ("''", [""]), (#"x"y"z"#, ["xyz"]),
        ("", [])
    ])
    func split(_ text: String, _ words: [String]) {
        #expect(ShellWords.split(text) == words)
    }

    @Test("An open quote is not a command line", arguments: ["'a", #""a"#, #""a\""#])
    func open(_ text: String) {
        #expect(ShellWords.split(text) == nil)
    }

    @Test("Compound scripts")
    func compound() {
        #expect(ShellWords.isCompound("npm run migrate && npm start"))
        #expect(ShellWords.isCompound("echo $HOME"))
        #expect(!ShellWords.isCompound("node server.js --port 80"))
    }
}
