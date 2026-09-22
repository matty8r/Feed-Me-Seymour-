//
//  HTMLEntities.swift
//  Feed Me, Seymour!
//
//  Named references worth knowing, plus the numeric forms. Typographic
//  punctuation matters more here than completeness: curly quotes, dashes and
//  spaces are most of what publishers actually escape.
//

import Foundation

enum HTMLEntities {

    static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "ensp": "\u{2002}", "emsp": "\u{2003}", "thinsp": "\u{2009}",
        "zwnj": "\u{200C}", "zwj": "\u{200D}", "shy": "\u{00AD}",
        "ndash": "–", "mdash": "—", "horbar": "―", "minus": "−",
        "lsquo": "‘", "rsquo": "’", "sbquo": "‚", "ldquo": "“", "rdquo": "”", "bdquo": "„",
        "laquo": "«", "raquo": "»", "lsaquo": "‹", "rsaquo": "›",
        "hellip": "…", "bull": "•", "middot": "·", "sdot": "⋅",
        "prime": "′", "Prime": "″", "dagger": "†", "Dagger": "‡",
        "copy": "©", "reg": "®", "trade": "™", "sect": "§", "para": "¶",
        "deg": "°", "plusmn": "±", "times": "×", "divide": "÷", "frac12": "½", "frac14": "¼", "frac34": "¾",
        "sup1": "¹", "sup2": "²", "sup3": "³",
        "cent": "¢", "pound": "£", "yen": "¥", "euro": "€", "curren": "¤",
        "larr": "←", "uarr": "↑", "rarr": "→", "darr": "↓", "harr": "↔", "crarr": "↵",
        "lArr": "⇐", "rArr": "⇒", "hArr": "⇔",
        "infin": "∞", "ne": "≠", "le": "≤", "ge": "≥", "asymp": "≈", "equiv": "≡",
        "sum": "∑", "prod": "∏", "radic": "√", "int": "∫", "part": "∂", "nabla": "∇",
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "zeta": "ζ",
        "eta": "η", "theta": "θ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ",
        "nu": "ν", "xi": "ξ", "pi": "π", "rho": "ρ", "sigma": "σ", "tau": "τ",
        "upsilon": "υ", "phi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Alpha": "Α", "Beta": "Β", "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ",
        "Pi": "Π", "Sigma": "Σ", "Phi": "Φ", "Omega": "Ω",
        "agrave": "à", "aacute": "á", "acirc": "â", "atilde": "ã", "auml": "ä", "aring": "å",
        "aelig": "æ", "ccedil": "ç", "egrave": "è", "eacute": "é", "ecirc": "ê", "euml": "ë",
        "igrave": "ì", "iacute": "í", "icirc": "î", "iuml": "ï", "ntilde": "ñ",
        "ograve": "ò", "oacute": "ó", "ocirc": "ô", "otilde": "õ", "ouml": "ö", "oslash": "ø",
        "ugrave": "ù", "uacute": "ú", "ucirc": "û", "uuml": "ü", "yacute": "ý", "yuml": "ÿ",
        "Agrave": "À", "Aacute": "Á", "Acirc": "Â", "Atilde": "Ã", "Auml": "Ä", "Aring": "Å",
        "AElig": "Æ", "Ccedil": "Ç", "Egrave": "È", "Eacute": "É", "Ecirc": "Ê", "Euml": "Ë",
        "Igrave": "Ì", "Iacute": "Í", "Icirc": "Î", "Iuml": "Ï", "Ntilde": "Ñ",
        "Ograve": "Ò", "Oacute": "Ó", "Ocirc": "Ô", "Otilde": "Õ", "Ouml": "Ö", "Oslash": "Ø",
        "Ugrave": "Ù", "Uacute": "Ú", "Ucirc": "Û", "Uuml": "Ü", "szlig": "ß",
        "hearts": "♥", "diams": "♦", "clubs": "♣", "spades": "♠", "star": "☆", "check": "✓"
    ]

    /// Resolves `&…;` references, leaving anything unrecognized exactly as written.
    static func decode(_ input: String) -> String {
        guard input.contains("&") else { return input }

        var output = ""
        output.reserveCapacity(input.count)
        var index = input.startIndex

        while index < input.endIndex {
            let character = input[index]
            guard character == "&" else {
                output.append(character)
                index = input.index(after: index)
                continue
            }

            // A reference is at most a few characters; don't scan the whole string.
            let limit = input.index(index, offsetBy: 34, limitedBy: input.endIndex) ?? input.endIndex
            guard let semicolon = input[index..<limit].firstIndex(of: ";") else {
                output.append(character)
                index = input.index(after: index)
                continue
            }

            let body = String(input[input.index(after: index)..<semicolon])
            if let replacement = resolve(body) {
                output.append(replacement)
                index = input.index(after: semicolon)
            } else {
                output.append(character)
                index = input.index(after: index)
            }
        }
        return output
    }

    private static func resolve(_ body: String) -> String? {
        guard !body.isEmpty else { return nil }

        if body.hasPrefix("#") {
            let digits = String(body.dropFirst())
            let value: UInt32?
            if digits.lowercased().hasPrefix("x") {
                value = UInt32(digits.dropFirst(), radix: 16)
            } else {
                value = UInt32(digits)
            }
            guard let value, let scalar = Unicode.Scalar(value) else { return nil }
            return String(Character(scalar))
        }

        if let exact = named[body] { return exact }
        // Some publishers lowercase everything, including &Eacute;.
        let lowered = body.lowercased()
        for (key, value) in named where key.lowercased() == lowered {
            return value
        }
        return nil
    }
}
