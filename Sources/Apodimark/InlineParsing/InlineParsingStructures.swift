//
//  InlineParsingStructures.swift
//  Apodimark
//

enum EmphasisKind {
    case asterisk, underscore, tilde
}

enum DelimiterKind {
    case emph(EmphasisKind, DelimiterState, Int32)  // run of * or _
    
    case code(Int32)         // run of `

    case refOpener          // [
    case unwrappedRefOpener // ![
    case refCloser          // ]


    case refValueOpener     // ( after a ]
    case leftParen          // ( used to allow pair of brackets in direct reference value definition. e.g. [link]((here))
    case rightParen         // ) used to close a direct reference value definition

    case escapingBackslash  // \ followed by punctuation
}


/// Returns true iff a token between `prev` and `next` is considered "left-flanking"
private func leftFlanking(prev: TokenKind, next: TokenKind) -> Bool {
    return (next != .punctuation || prev != .neither)
}

/// Returns true iff a token between `prev` and `next` is considered "right-flanking"
private func rightFlanking(prev: TokenKind, next: TokenKind) -> Bool {
    return leftFlanking(prev: next, next: prev)
}


/// An option set giving the state of a delimiter (opening, closing, neither, or both)
struct DelimiterState: OptionSet {

    let rawValue: UInt8

    init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    static let closing = DelimiterState(rawValue: 0b01)
    static let opening = DelimiterState(rawValue: 0b10)

    init <Codec: MarkdownParserCodec> (token: Codec.CodeUnit, prev: TokenKind, next: TokenKind, codec: Codec.Type) {
        var state: DelimiterState = []
        let isLeftFlanking = leftFlanking(prev: prev, next: next)
        let isRightFlanking = rightFlanking(prev: prev, next: next)

        switch token {

        case Codec.asterisk:
            fallthrough
        case Codec.tilde:
            if isRightFlanking { state.formUnion(.closing) }
            if isLeftFlanking  { state.formUnion(.opening) }

        case Codec.underscore:
            if isRightFlanking && (!isLeftFlanking  || prev == .punctuation) { state.formUnion(.closing) }
            if isLeftFlanking  && (!isRightFlanking || next == .punctuation) { state.formUnion(.opening) }

        default:
            fatalError()
        }

        self = state
    }
}

/// An enumeration describing the type of a token (character):
/// either whitespace, punctuation, or neither.
enum TokenKind {
    case whitespace, punctuation, neither
}

extension MarkdownParser {

    static func tokenKind(_ token: Codec.CodeUnit) -> TokenKind {
        switch token {

        case Codec.space, Codec.linefeed:
            return .whitespace

        case let t where Codec.isPunctuation(t):
            return .punctuation

        default:
            return .neither
        }

    }
}



