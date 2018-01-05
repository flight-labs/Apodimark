//
//  LineLexer.swift
//  Apodimark
//

/*
 HOW TO READ THE COMMENTS:
 
 Example:
 Lorem Ipsum blah blah
        |_<---

 Means that scanner points to “s”
 Therefore:
 - “p” has already been read
 - scanner.startIndex is the index of “s”
 - the next scanner.peek() will return “s”
 */

/// Error type used for parsing a List line
fileprivate enum ListParsingError: Error {
    case notAListMarker
    case emptyListItem(ListKind)
}

extension MarkdownParser {

    /// Advances the scanner to the end of the valid marker, or throws an error and leaves the scanner intact
    /// if the list marker is invalid.
    /// - parameter scanner: a scanner whose `startIndex` points to the first token of the list marker
    ///   (e.g. a hyphen, an asterisk, a digit)
    /// - throws: `ListParsingError.notAListMarker` if the list marker is invalid
    /// - returns: the kind of the list marker
    fileprivate static func readListMarker(_ scanner: inout Scanner<View>) throws -> ListKind {

        guard case let firstToken? = scanner.pop() else {
            preconditionFailure()
        }

        var value: Int = 0
        var bulletKind: ListKind?
        switch firstToken {
        case Codec.hyphen     : bulletKind = .bullet(.hyphen)
        case Codec.asterisk   : bulletKind = .bullet(.star)
        case Codec.plus       : bulletKind = .bullet(.plus)
        case Codec.zero...Codec.nine: value = Codec.digit(representedByToken: firstToken)
        case _          : preconditionFailure()
        }

        // *
        // |_<---
        if let bullet = bulletKind {
          guard let token = scanner.peek(), token == Codec.space else {
            throw ListParsingError.notAListMarker // An asterisk requires a space after it
          }
          return bullet
        }

        // 1234)
        // |_<---
        var length = 1
        try scanner.popWhile { token in

            guard case let token? = token, token != Codec.linefeed else {
                throw ListParsingError.notAListMarker // e.g. 1234 followed by end of line / end of string
            }

            switch token {

            case Codec.fullstop, Codec.rightparen:
                return .stop // e.g. 1234|)| -> hurray! confirm and stop now

            case Codec.zero...Codec.nine:
                guard length < 9 else {
                    throw ListParsingError.notAListMarker // e.g. 123456789|0| -> too long
                }
                length += 1
                value = value * 10 + Codec.digit(representedByToken: token)
                return .pop // e.g. 12|3| -> ok, keep reading

            case _:
                throw ListParsingError.notAListMarker // e.g. 12|a| -> not a list marker
            }
        }

        // will not crash because popWhile threw an error if lastToken is not fullstop or rightparen
        let lastToken = scanner.pop()!

        guard let token = scanner.peek(), token == Codec.space else {
         throw ListParsingError.notAListMarker // An number with dot/parenthesis requires a space after it
        }

        switch lastToken {
        case Codec.fullstop  : return .number(.dot, value)
        case Codec.rightparen: return .number(.parenthesis, value)
        default        : fatalError()
        }
    }

    /// Tries to parse a List. Advances the scanner to the end of the line and return the parsed line.
    /// - parameter scanner: a scanner whose `startIndex` points to the start of potential List line
    /// - parameter indent: the indent of the line being parsed
    /// - return: the parsed Line
    fileprivate static func parseList(_ scanner: inout Scanner<View>, indent: Indent, context: LineLexerContext<Codec>) -> Line {

        let indexBeforeList = scanner.startIndex
        // let initialSubView = scanner
        //  1234)
        // |_<---

        do {
            let kind = try MarkdownParser.readListMarker(&scanner)
            //  1234)
            //      |_<---

            guard case let token? = scanner.pop(ifNot: Codec.linefeed) else {
                throw ListParsingError.emptyListItem(kind)
            }
            guard token == Codec.space else {
                throw ListParsingError.notAListMarker
            }
            //  1234)
            //       |_<---

            let rest = parseLine(&scanner, context: context)
            return Line(.list(kind, rest), indent, indexBeforeList ..< scanner.startIndex)
        }
        catch ListParsingError.notAListMarker {
            // xxxxx…
            //    |_<--- scanner could point anywhere but not past the end of the line
            scanner.popUntil(Codec.linefeed)
            return Line(.text, indent, indexBeforeList ..< scanner.startIndex)
        }
        catch ListParsingError.emptyListItem(let kind) {
            // 1234)\n
            //     |__<---
            let finalIndices = indexBeforeList ..< scanner.startIndex
            let rest = Line(.empty, indent, finalIndices)
            return Line(.list(kind, rest), indent, finalIndices)
        }
        catch {
            fatalError()
        }
    }
}

/// State used for read the content of a Header line
fileprivate enum HeaderTextReadingState { // e.g. for # Hello  World ####    \n
    case text         // # He|_
    case textSpaces   // # Hello |_
    case hashes       // # Hello   World #|_
    case endSpaces    // # Hello   World #### |_
}

extension MarkdownParser {
    /// Reads the content of a Header line
    /// - parameter scanner: a scanner whose `startIndex` points to to the start of the text in a Header line
    /// - returns: the index pointing to the end of the text in the header
    fileprivate static func readHeaderText(_ scanner: inout Scanner<View>) -> View.Index {

        var state = HeaderTextReadingState.textSpaces
        var end = scanner.startIndex

        while case let token? = scanner.pop(ifNot: Codec.linefeed) {
            switch state {

            case .text:
                if token == Codec.space { state = .textSpaces }
                else { end = scanner.startIndex }

            case .textSpaces:
                if token == Codec.space { break }
                else if token == Codec.hash { state = .hashes }
                else { (state, end) = (.text, scanner.startIndex) }

            case .hashes:
                if token == Codec.hash { state = .hashes }
                else if token == Codec.space { state = .endSpaces }
                else { (state, end) = (.text, scanner.startIndex) }

            case .endSpaces:
                if token == Codec.space { break }
                else if token == Codec.hash { (state, end) = (.hashes, scanner.data.index(before: scanner.startIndex)) }
                else { (state, end) = (.text, scanner.startIndex) }
            }
        }

        return end
    }
}

/// Error type used for parsing a header line
fileprivate enum HeaderParsingError: Error {
    case notAHeader
    case emptyHeader(Int32)
}

extension MarkdownParser {

    /// Tries to parse a Header. Advances the scanner to the end of the line.
    /// - parameter scanner: a scanner whose `startIndex` points the start of a potential Header line
    /// - parameter indent: the indent of the line being parsed
    /// - return: the parsed Line
    fileprivate static func parseHeader(_ scanner: inout Scanner<View>, indent: Indent) -> Line {

        let indexBeforeHeader = scanner.startIndex
        //  xxxxxx
        // |_<--- (start of line)

        do {
            var level: Int32 = 0
            try scanner.popWhile { token in

                guard case let token? = token else {
                    throw HeaderParsingError.emptyHeader(level)
                }

                switch token {

                case Codec.hash where level < 6:
                    level = level + 1
                    return .pop

                case Codec.space:
                    return .stop

                case Codec.linefeed:
                    throw HeaderParsingError.emptyHeader(level)

                default:
                    throw HeaderParsingError.notAHeader
                }
            }
            // ##  Hello
            //  |_<---

            scanner.popWhile(Codec.space)
            // ##  Hello
            //    |_<---

            let start = scanner.startIndex
            let end = readHeaderText(&scanner)
            // ##  Hello World ####\n
            //    |          |    |__<---
            //    |_         |_
            //    start    end

            let headerkind = LineKind.header(start ..< end, level)
            return Line(headerkind, indent, indexBeforeHeader ..< scanner.startIndex)
        }
        catch HeaderParsingError.notAHeader {
            // scanner could point anywhere but not past end of line
            scanner.popUntil(Codec.linefeed)
            return Line(.text, indent, indexBeforeHeader ..< scanner.startIndex)
        }
        catch HeaderParsingError.emptyHeader(let level) {
            // scanner could point anywhere but not past end of line
            scanner.popUntil(Codec.linefeed)
            let lineKind = LineKind.header(scanner.startIndex ..< scanner.startIndex, level)
            return Line(lineKind, indent, indexBeforeHeader ..< scanner.startIndex)
        }
        catch {
            fatalError()
        }
    }
}

/// Error type used for a parsing a Fence
fileprivate enum FenceParsingError: Error {
    case notAFence
    case emptyFence(FenceKind, Int32)
}

extension MarkdownParser {

    /// Tries to read the name of Fence line. 
    ///
    /// Advances the scanner to the end of the line if it succeeded, throws an error otherwise.
    ///
    /// - parameter scanner: a scanner pointing to the first letter of a potential Fence’s name
    /// - throws: `FenceParsingError.notAFence` if the line is not a Fence line
    /// - returns: the index pointing to the end of the name
    fileprivate static func readFenceName(_ scanner: inout Scanner<View>) throws -> View.Index {

        // ```  name
        //     |_<---
        var end = scanner.startIndex

        while case let token? = scanner.pop(ifNot: Codec.linefeed) {
            switch token {

            case Codec.space:
                break

            case Codec.backtick:
                throw FenceParsingError.notAFence

            case _:
                end = scanner.startIndex
            }
        }
        // ```  name    \n
        //         |_  |__<---
        //        end
        return end
    }
}

extension MarkdownParser {

    /// Tries to parse a Fence line.
    ///
    /// Advances the scanner to the end of the line.
    ///
    /// - parameter scanner: a scanner whose pointing to the start of what might be a Fence line
    /// - parameter indent: the indent of the line being parsed
    /// - returns: the parsed line
    fileprivate static func parseFence(_ scanner: inout Scanner<View>, indent: Indent) -> Line {

        let indexBeforeFence = scanner.startIndex

        guard let firstLetter = scanner.pop() else { preconditionFailure() }
        let kind: FenceKind = firstLetter == Codec.backtick ? .backtick : .tilde

        // ```   name
        // |_<---

        do {
            var level: Int32 = 1
            try scanner.popWhile { token in

                guard case let token? = token else {
                    throw FenceParsingError.emptyFence(kind, level)
                }

                switch token {

                case firstLetter:
                    level = level + 1
                    return .pop

                case Codec.linefeed:
                    guard level >= 3 else {
                        throw FenceParsingError.notAFence
                    }
                    throw FenceParsingError.emptyFence(kind, level)

                case _:
                    guard level >= 3 else {
                        throw FenceParsingError.notAFence
                    }
                    return .stop
                }
            }
            // ```   name
            //   |_<---

            scanner.popWhile(Codec.space)
            // ```   name
            //      |_<---

            let start = scanner.startIndex
            let end = try readFenceName(&scanner)
            // ```   name    \n
            //      |   |   |__<---
            //      |_  |_
            //  start   end

            let linekind = LineKind.fence(kind, start ..< end, level)
            return Line(linekind, indent, indexBeforeFence ..< scanner.startIndex)
        }
        catch FenceParsingError.notAFence {
            // scanner could point anywhere but not past end of line
            scanner.popUntil(Codec.linefeed)
            return Line(.text, indent, indexBeforeFence ..< scanner.startIndex)
        }
        catch FenceParsingError.emptyFence(let kind, let level) {
            // scanner could point anywhere but not past end of line
            scanner.popUntil(Codec.linefeed)
            let linekind = LineKind.fence(kind, scanner.startIndex ..< scanner.startIndex, level)
            return Line(linekind, indent, indexBeforeFence ..< scanner.startIndex)
        }
        catch {
            fatalError()
        }
    }
}

/// Error type used for parsing a ThematicBreak line
fileprivate struct NotAThematicBreakError: Error {}

extension MarkdownParser {

    /// Tries to read a ThematicBreak line.
    /// 
    /// Advances the scanner to the end of the line if it succeeded, throws an error otherwise.
    /// 
    /// - precondition: `firstToken == scanner.pop()`
    ///
    /// (not checked at runtime)
    ///
    /// - parameter scanner: a scanner pointing to the start of what might be a ThematicBreak line
    /// - parameter firstToken: the first token of the potential ThematicBreak line
    /// - throws: `NotAThematicBreakError()` if the line is not a ThematicBreak line
    fileprivate static func readThematicBreak(_ scanner: inout Scanner<View>, firstToken: Codec.CodeUnit) throws {

        //  * * *
        // |_<--- (start of line)

        var level = 0
        try scanner.popWhile { token in

            guard case let token? = token, token != Codec.linefeed else {
                guard level >= 3 else {
                    throw NotAThematicBreakError() // e.g. * * -> not enough stars -> not a thematic break
                }
                return .stop // e.g. *  *  * * -> hurray! confirm and stop now
            }

            switch token {

            case firstToken: // e.g. * * |*| -> ok, keep reading
                level += 1
                return .pop

            case Codec.space, Codec.tab: // e.g. * * | | -> ok, keep reading
                return .pop

            default:
                throw NotAThematicBreakError() // e.g. * * |g| -> not a thematic break!
            }
        }
    }
}

/// Error type used when parsing a ReferenceDefinition line
fileprivate struct NotAReferenceDefinitionError: Error {}

extension MarkdownParser {

    /// Tries to parse a ReferenceDefinition line.
    ///
    /// Advances the scanner to the end of line if it succeeded, throws an error otherwise.
    ///
    /// - parameter scanner: a scanner pointing to the first token of what might be a ReferenceDefinition line
    /// - parameter indent: the indent of the line being parsed
    /// - throws: `NotAReferenceDefinitionError()` if the line is not a ReferenceDefinition line
    /// - returns: the parsed line
    fileprivate static func parseReferenceDefinition(_ scanner: inout Scanner<View>, indent: Indent) throws -> Line {

        //  [hello]:  world
        // |_<---
        let indexBeforeRefDef = scanner.startIndex
        _ = scanner.pop()

        //  [hello]:  world
        //  |_<---
        let idxBeforeTitle = scanner.startIndex

        var escapeNext = false
        try scanner.popWhile { (token: Codec.CodeUnit?) throws -> PopOrStop in

            guard case let token? = token, token != Codec.linefeed else {
                throw NotAReferenceDefinitionError()
            }

            guard !escapeNext else {
                escapeNext = false
                return .pop
            }

            guard token != Codec.leftsqbck else {
                throw NotAReferenceDefinitionError()
            }

            guard token != Codec.rightsqbck else {
                return .stop
            }

            escapeNext = (token == Codec.backslash)
            return .pop
        }

        let idxAfterTitle = scanner.startIndex
        guard idxAfterTitle > scanner.data.index(after: idxBeforeTitle) else {
            throw NotAReferenceDefinitionError()
        }

        _ = scanner.pop(Codec.rightsqbck)
        // [hello]:  world
        //       |_<---

        guard scanner.pop(Codec.colon) else { throw NotAReferenceDefinitionError() }

        scanner.popWhile(Codec.space)

        let idxBeforeDefinition = scanner.startIndex
        // [hello]:  world
        //          |_<---
        scanner.popUntil(Codec.linefeed)

        let idxAfterDefinition = scanner.startIndex
        guard idxBeforeDefinition < idxAfterDefinition else {
            throw NotAReferenceDefinitionError()
        }

        let definition = idxBeforeDefinition ..< idxAfterDefinition
        let title = idxBeforeTitle ..< idxAfterTitle
        
        return Line(.reference(title, definition), indent, indexBeforeRefDef ..< scanner.startIndex)
    }
}


struct LineLexerContext <C: MarkdownParserCodec> {
    var listKindBeingRead: C.CodeUnit?

    static var `default`: LineLexerContext {
        return .init(listKindBeingRead: nil)
    }
}

extension MarkdownParser {
    static func parseLine(_ scanner: inout Scanner<View>, context: LineLexerContext<Codec>) -> Line {
        //      xxxxx
        // |_<--- (start of line)

        var indent = Indent()
        scanner.popWhile { (token: Codec.CodeUnit?) -> PopOrStop in

            guard case let token? = token else {
                return .stop
            }

            guard case let indentKind? = IndentKind(token, codec: Codec.self) else {
                return .stop
            }

            indent.add(indentKind)
            return .pop
        }
        let indexAfterIndent = scanner.startIndex
        //       xxxx
        //      |_<--- (after indent)

        guard case let firstToken? = scanner.peek() else {
            return Line(.empty, Indent(), scanner.indices)
        }

        switch firstToken {

        case Codec.quote:
            _ = scanner.pop()!
            let rest = parseLine(&scanner, context: .default)
            return Line(.quote(rest), indent, indexAfterIndent ..< scanner.startIndex)


        case Codec.underscore:
            guard case .some = try? readThematicBreak(&scanner, firstToken: firstToken) else {
                scanner.popUntil(Codec.linefeed)
                return Line(.text, indent, indexAfterIndent ..< scanner.startIndex)
            }
            return Line(.thematicBreak, indent, indexAfterIndent ..< scanner.startIndex)


        case Codec.hyphen, Codec.asterisk:
            if firstToken != context.listKindBeingRead, case .some = try? readThematicBreak(&scanner, firstToken: firstToken) {
                return Line(.thematicBreak, indent, indexAfterIndent ..< scanner.startIndex)
            } else {
                var context = context
                context.listKindBeingRead = firstToken
                return parseList(&scanner, indent: indent, context: context)
            }


        case Codec.plus, Codec.zero...Codec.nine:
            return parseList(&scanner, indent: indent, context: context)


        case Codec.hash:
            return parseHeader(&scanner, indent: indent)


        case Codec.linefeed:
            return Line(.empty, indent, indexAfterIndent ..< scanner.startIndex)


        case Codec.backtick:
            return parseFence(&scanner, indent: indent)


        case Codec.leftsqbck:
            guard case let line? = try? parseReferenceDefinition(&scanner, indent: indent) else {
                scanner.popUntil(Codec.linefeed)
                return Line(.text, indent, indexAfterIndent ..< scanner.startIndex)
            }
            return line


        case _:
            scanner.popUntil(Codec.linefeed)
            return Line(.text, indent, indexAfterIndent ..< scanner.startIndex)
        }
    }
}
