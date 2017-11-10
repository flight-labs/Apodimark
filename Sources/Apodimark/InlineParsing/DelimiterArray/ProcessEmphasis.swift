//
//  ProcessEmphasis.swift
//  Apodimark
//

extension MarkdownParser {
    
    /// Parse the emphases contained in `delimiters` and append them to `nodes`
    func processAllEmphases(_ delimiters: inout [Delimiter?], indices: CountableRange<Int>, appendingTo nodes: inout [NonTextInline]) {
        var start = indices.lowerBound
        while case let newStart? = processEmphasis(&delimiters, indices: start ..< indices.upperBound, appendingTo: &nodes) {
            start = newStart
        }
    }

    /// Parse the first emphasis contained in `delimiters[indices]` and append it to `nodes`
    /// - returns: the index of the first opening emphasis delimiter in the `delimiters[indices]`, or `nil` if no emphasis was found
    fileprivate func processEmphasis(_ delimiters: inout [Delimiter?], indices: CountableRange<Int>, appendingTo nodes: inout [NonTextInline]) -> Int? {
        
        guard let (newStart, openingDelIdx, closingDelIdx, emphasisKind) = {
            () -> (Int, Int, Int, EmphasisKind)? in
            
            var openingEmph: (underscore: Int?, asterisk: Int?, tilde: Int?) = (nil, nil, nil)
            
            var firstOpeningEmph: Int? = nil
            
            for i in indices {
                guard case let .emph(kind, state, level)? = delimiters[i]?.kind else {
                    continue
                }
                if state.contains(.closing) {
                    let fstDelIdx: Int? = (kind == .underscore ? openingEmph.underscore :
                            kind == .asterisk ? openingEmph.asterisk : openingEmph.tilde)

                    if fstDelIdx != nil { return (firstOpeningEmph!, fstDelIdx!, i, kind) }
                }
                if state.contains(.opening) {
                    if firstOpeningEmph == nil { firstOpeningEmph = i }
                    if kind == .underscore { openingEmph.underscore = i }
                    else if kind == .tilde { openingEmph.tilde = i }
                    else { openingEmph.asterisk = i }
                }
            }
            return nil
        }() else {
            return nil
        }
        
        guard
            let openingDel = delimiters[openingDelIdx],
            let closingDel = delimiters[closingDelIdx],
            case .emph(let kind, let state1, let l1) = openingDel.kind,
            case .emph(kind, let state2, let l2) = closingDel.kind
        else {
            fatalError()
        }
        
        defer {
            for idx in openingDelIdx+1 ..< closingDelIdx {
                if case .emph? = delimiters[idx]?.kind {
                    delimiters[idx] = nil
                }
            }
        }

        let emphType: EmphasisType = {
            switch emphasisKind {
            case .asterisk: return EmphasisType.bold
            case .underscore: return EmphasisType.italic
            case .tilde: return EmphasisType.strikethrough
            }
        }()
        
        switch Int32.compare(l1, l2) {
            
        case .equal:
            delimiters[openingDelIdx] = nil
            delimiters[closingDelIdx] = nil
            nodes.append(.init(
                kind: .emphasis(l1, emphType),
                start: view.index(openingDel.idx, offsetBy: numericCast(-l1)),
                end: closingDel.idx
            ))
            return newStart
            
        case .lessThan:
            delimiters[openingDelIdx] = nil
            delimiters[closingDelIdx]!.kind = .emph(kind, state2, l2 - l1)
            let startOffset = -l1
            let endOffset = -(l2 - l1)
            
            nodes.append(.init(
                kind: .emphasis(l1, emphType),
                start: view.index(openingDel.idx, offsetBy: numericCast(startOffset)),
                end: view.index(closingDel.idx, offsetBy: numericCast(endOffset))
            ))
            return newStart
            
            
        case .greaterThan:
            delimiters[closingDelIdx] = nil
            view.formIndex(&delimiters[openingDelIdx]!.idx, offsetBy: numericCast(-l2))
            delimiters[openingDelIdx]!.kind = .emph(kind, state1, l1 - l2)
            
            nodes.append(.init(
                kind: .emphasis(l2, emphType),
                start: view.index(openingDel.idx, offsetBy: numericCast(-l2)),
                end: closingDel.idx
            ))
            return newStart
        }
    }
}
