//
//  HTMLTokenizer.swift
//  Feed Me, Seymour!
//
//  A forgiving, dependency-free scanner. Feed HTML is written by a thousand
//  different CMSes, so the rule here is never to throw: anything unparseable
//  becomes text.
//

import Foundation

enum HTMLToken {
    case startTag(name: String, attributes: [String: String], isSelfClosing: Bool)
    case endTag(name: String)
    case text(String)
}

enum HTMLTokenizer {

    /// Elements whose contents are not prose and should never reach the reader.
    static let discardedContentTags: Set<String> = ["script", "style", "noscript", "svg", "head", "template", "form", "button", "select", "textarea"]

    /// Elements that never have a closing tag.
    static let voidTags: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"]

    static func tokenize(_ html: String) -> [HTMLToken] {
        let characters = Array(html)
        var tokens: [HTMLToken] = []
        var index = 0
        var textBuffer = ""

        func flushText() {
            guard !textBuffer.isEmpty else { return }
            tokens.append(.text(HTMLEntities.decode(textBuffer)))
            textBuffer = ""
        }

        while index < characters.count {
            let character = characters[index]

            guard character == "<" else {
                textBuffer.append(character)
                index += 1
                continue
            }

            // `<` that isn't the start of a tag is literal text (maths, code, sloppy CMSes).
            guard index + 1 < characters.count, isTagOpener(characters[index + 1]) else {
                textBuffer.append(character)
                index += 1
                continue
            }

            if matches(characters, at: index, "<!--") {
                flushText()
                index = skip(characters, from: index + 4, until: "-->") + 3
                continue
            }

            if matches(characters, at: index, "<![CDATA[") {
                let end = skip(characters, from: index + 9, until: "]]>")
                textBuffer += String(characters[(index + 9)..<min(end, characters.count)])
                index = end + 3
                continue
            }

            if matches(characters, at: index, "<!") || matches(characters, at: index, "<?") {
                flushText()
                index = skip(characters, from: index + 2, until: ">") + 1
                continue
            }

            flushText()

            let isEnd = characters[index + 1] == "/"
            var cursor = index + (isEnd ? 2 : 1)

            var name = ""
            while cursor < characters.count, isNameCharacter(characters[cursor]) {
                name.append(characters[cursor])
                cursor += 1
            }
            name = name.lowercased()

            if isEnd {
                cursor = skip(characters, from: cursor, until: ">")
                tokens.append(.endTag(name: name))
                index = cursor + 1
                continue
            }

            let (attributes, afterAttributes, selfClosing) = parseAttributes(characters, from: cursor)
            index = afterAttributes

            let isVoid = selfClosing || voidTags.contains(name)
            tokens.append(.startTag(name: name, attributes: attributes, isSelfClosing: isVoid))

            // Raw-text elements: swallow everything up to the matching close tag so
            // JavaScript never leaks into the article body.
            if discardedContentTags.contains(name), !isVoid {
                let closing = "</\(name)"
                index = skipCaseInsensitive(characters, from: index, until: closing)
                index = skip(characters, from: index, until: ">") + 1
                tokens.append(.endTag(name: name))
            }
        }

        flushText()
        return tokens
    }

    // MARK: - Scanning primitives

    private static func isTagOpener(_ character: Character) -> Bool {
        character.isLetter || character == "/" || character == "!" || character == "?"
    }

    private static func isNameCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-" || character == "_" || character == ":"
    }

    private static func matches(_ characters: [Character], at index: Int, _ needle: String) -> Bool {
        let needleCharacters = Array(needle)
        guard index + needleCharacters.count <= characters.count else { return false }
        for offset in 0..<needleCharacters.count where characters[index + offset] != needleCharacters[offset] {
            return false
        }
        return true
    }

    /// Returns the index at which `needle` begins, or `count` if it never does.
    private static func skip(_ characters: [Character], from index: Int, until needle: String) -> Int {
        var cursor = max(index, 0)
        while cursor < characters.count {
            if matches(characters, at: cursor, needle) { return cursor }
            cursor += 1
        }
        return characters.count
    }

    private static func skipCaseInsensitive(_ characters: [Character], from index: Int, until needle: String) -> Int {
        let lowered = Array(needle.lowercased())
        var cursor = max(index, 0)
        outer: while cursor + lowered.count <= characters.count {
            for offset in 0..<lowered.count where String(characters[cursor + offset]).lowercased() != String(lowered[offset]) {
                cursor += 1
                continue outer
            }
            return cursor
        }
        return characters.count
    }

    private static func parseAttributes(_ characters: [Character], from start: Int) -> (attributes: [String: String], nextIndex: Int, isSelfClosing: Bool) {
        var attributes: [String: String] = [:]
        var index = start
        var selfClosing = false

        while index < characters.count {
            while index < characters.count, characters[index].isWhitespace { index += 1 }
            guard index < characters.count else { break }

            if characters[index] == ">" {
                index += 1
                break
            }
            if characters[index] == "/" {
                selfClosing = true
                index += 1
                continue
            }

            var name = ""
            while index < characters.count, isNameCharacter(characters[index]) {
                name.append(characters[index])
                index += 1
            }
            if name.isEmpty {
                // Garbage inside the tag; step over it rather than spin.
                index += 1
                continue
            }

            while index < characters.count, characters[index].isWhitespace { index += 1 }

            var value = ""
            if index < characters.count, characters[index] == "=" {
                index += 1
                while index < characters.count, characters[index].isWhitespace { index += 1 }
                if index < characters.count, characters[index] == "\"" || characters[index] == "'" {
                    let quote = characters[index]
                    index += 1
                    while index < characters.count, characters[index] != quote {
                        value.append(characters[index])
                        index += 1
                    }
                    index += 1
                } else {
                    while index < characters.count, !characters[index].isWhitespace, characters[index] != ">" {
                        value.append(characters[index])
                        index += 1
                    }
                }
            }

            attributes[name.lowercased()] = HTMLEntities.decode(value)
        }

        return (attributes, index, selfClosing)
    }
}

// MARK: - Plain text

enum HTMLTextExtractor {
    /// Strips markup for list summaries, search and accessibility labels.
    static func plainText(from html: String) -> String {
        guard html.contains("<") || html.contains("&") else { return html.squeezedWhitespace }
        var output = ""
        for token in HTMLTokenizer.tokenize(html) {
            switch token {
            case .text(let text):
                output += text
            case .startTag(let name, _, _):
                if ["p", "br", "div", "li", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "tr"].contains(name) {
                    output += " "
                }
            case .endTag:
                break
            }
        }
        return output.squeezedWhitespace
    }
}
