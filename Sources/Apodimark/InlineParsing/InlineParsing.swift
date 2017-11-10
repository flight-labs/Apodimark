//
//  InlineParsing.swift
//  Apodimark
//

extension NonTextInlineNode {
    /// Returns true iff lhs.start < rhs.start
    static func < (lhs: NonTextInlineNode, rhs: NonTextInlineNode) -> Bool { return lhs.start <  rhs.start }
}

extension MarkdownParser {
    
    
    /// Parse the text defined by the given indices as inline Markdown.
    ///
    /// - parameter text: an array of indices to the markdown text.
    ///
    ///   Each range in the array must define a single line.
    ///
    /// - returns: a tree of InlineNode describing the parsed text
    func parseInlines(_ text: [Range<View.Index>]) -> Tree<Inline> {
        
        var nonTextDels = delimiters(in: text)

        var nodes: [NonTextInline] = []
        
        processAllMonospacedText(&nonTextDels, appendingTo: &nodes)
        processAllReferences(&nonTextDels, appendingTo: &nodes)
        processAllEmphases(&nonTextDels, indices: nonTextDels.indices, appendingTo: &nodes)
        processAllEscapingBackslashes(nonTextDels, appendingTo: &nodes)
        
        nodes.sort(by: <)
        
        let textNodes = TextInlineNodeIterator<View, Codec>(view: view, text: text)
        
        return makeAST(text: textNodes, nonText: nodes)
    }

    
    /// Scans the text and finds the special delimiters inside it.
    ///
    /// - parameter text: an array of indices to the markdown text.
    ///
    ///   Each range in the array must define a single line.
    ///
    /// - returns: the delimiters included in the text
    private func delimiters(in text: [Range<View.Index>]) -> [Delimiter?] {
        
        var delimiters: [Delimiter?] = []
    
        var scanner = Scanner(data: view)
        
        for line in text {
            
            (scanner.startIndex, scanner.endIndex) = (line.lowerBound, line.upperBound)
            
            var prevTokenKind = TokenKind.whitespace
            
            while case let token? = scanner.pop() {
                let curTokenKind = MarkdownParser.tokenKind(token)
                defer { prevTokenKind = curTokenKind }

                // avoid going into the switch if token is not punctuation (optimization, maybe unnecessary)
                guard case .punctuation = curTokenKind else {
                    continue
                }
                
                switch token {
                    
                case Codec.underscore, Codec.asterisk, Codec.tilde:
                    let idxBeforeRun = view.index(before: scanner.startIndex)
                    scanner.popWhile(token)
                    let nextTokenKind = scanner.peek().flatMap(MarkdownParser.tokenKind) ?? .whitespace
                    
                    let delimiterState = DelimiterState(token: token, prev: prevTokenKind, next: nextTokenKind, codec: Codec.self)
                    let lvl = view.distance(from: idxBeforeRun, to: scanner.startIndex)
                    let kind: EmphasisKind = token == Codec.underscore ?
                            .underscore : (token == Codec.asterisk ? .asterisk : .tilde)
                    delimiters.append((scanner.startIndex, .emph(kind, delimiterState, numericCast(lvl))))
                    
                case Codec.backtick:
                    let idxBeforeRun = view.index(before: scanner.startIndex)
                    scanner.popWhile(Codec.backtick)
                    let lvl = view.distance(from: idxBeforeRun, to: scanner.startIndex)
                    delimiters.append((scanner.startIndex, .code(numericCast(lvl))))
                    
                case Codec.exclammark:
                    if scanner.pop(Codec.leftsqbck) {
                        delimiters.append((scanner.startIndex, .unwrappedRefOpener))
                    }
                    
                case Codec.leftsqbck:
                    delimiters.append((scanner.startIndex, .refOpener))
                    
                case Codec.rightsqbck:
                    delimiters.append((scanner.startIndex, .refCloser))
                    if scanner.pop(Codec.leftparen) {
                        delimiters.append((scanner.startIndex, .refValueOpener))
                    }
                    
                case Codec.leftparen:
                    delimiters.append((scanner.startIndex, .leftParen))
                    
                case Codec.rightparen:
                    delimiters.append((scanner.startIndex, .rightParen))
                    
                case Codec.backslash:
                    guard case let el? = scanner.peek() else {
                        break
                    }
                    if Codec.isPunctuation(el) {
                        delimiters.append((scanner.startIndex, .escapingBackslash))
                        if el != Codec.backtick { _ = scanner.pop() }
                    }
                    
                default:
                    break
                }
            }
        }
        
        return delimiters
    }
}


