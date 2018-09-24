
extension MarkdownParser {
 
    func makeAST(text: TextInlineNodeIterator<View, Codec>, nonText: [NonTextInline]) -> Tree<Inline> {
        let tree = Tree<Inline>()
       
        var builder = InlineTreeBuilder(text, nonText, view, tree)
        while case let (n, level)? = builder.next() {
            tree.append(n, depthLevel: level)
        }
        
        return tree
    }
}

extension Range {
    fileprivate func split(up: Bound, nextLow: Bound) -> (Range, Range?) {
        return (lowerBound ..< Swift.min(up, upperBound), (nextLow < upperBound ? (nextLow ..< upperBound) : nil))
    }
}

extension TextInlineNode {
    fileprivate func withBounds(_ bounds: Range<View.Index>) -> TextInlineNode {
        var new = self
        new.start = bounds.lowerBound
        new.end = bounds.upperBound
        return new
    }
}

fileprivate func map <T, U> (_ x: (T, T?), _ f: (T) -> U) -> (U, U?) {
    return (f(x.0), x.1.map(f))
}

fileprivate struct InlineTreeBuilder <View: BidirectionalCollection, I1: IteratorProtocol, RefDef: ReferenceDefinitionProtocol> where
    I1.Element == TextInlineNode<View>
{
    typealias Node = InlineNode<View, RefDef>
    typealias Text = TextInlineNode<View>
    typealias NonText = NonTextInlineNode<View, RefDef>

    var (e1, e2): (Text?, NonText?) = (nil, nil)
    var (texts, nonTexts): (I1, Array<NonText>.Iterator)
    
    let tree: Tree<Node>
    var tryLevel = DepthLevel.root
    let view: View
    
    init(_ i1: I1, _ s2: [NonText], _ view: View, _ tree: Tree<Node>) {
        (self.texts, self.nonTexts) = (i1, s2.makeIterator())
        self.view = view
        self.tree = tree
    }

    mutating func next() -> (Node, DepthLevel)? {

        (e1, e2) = (e1 ?? texts.next(), e2 ?? nonTexts.next())
        
        guard case let (node?, newE1, newE2, insertLevel) = { () -> (Node?, Text?, NonText?, DepthLevel) in
            
            guard var t = e1 else {
                return (e2.map(Node.nonText), e1, nil, tryLevel)
            }

            var insertionLevel = tryLevel
            let parents = sequence(state: tryLevel) { [tree] (lvl: inout DepthLevel) -> (NonText, DepthLevel)? in
                guard case let .nonText(parent)? = tree.last(depthLevel: lvl.decremented()) else {
                    return nil
                }
                defer { lvl = lvl.decremented() }
                return (parent, lvl)
            }
            for (parent, level) in parents {
                let parentContent = parent.contentRange(inView: view)
                
                guard t.start < parentContent.upperBound else {
                    t.start = max(t.start, parent.end)
                    insertionLevel = level.decremented()
                    continue
                }

                if let n = e2, n.start <= t.start {
                    return (.nonText(n), e1, nil, level)
                }
                
                let up = e2.map { min($0.start, parentContent.upperBound) } ?? parentContent.upperBound
                let nextLow = e2.map { min($0.start, parent.end) } ?? parent.end
                
                let (insert, next) = map((max(t.start, parentContent.lowerBound) ..< t.end).split(up: up, nextLow: nextLow), t.withBounds)
                return (.text(insert), next, e2, level)
            }
            
            guard let n = e2 else {
                return (.text(t), nil, e2, insertionLevel)
            }
            
            guard t.start < n.start else {
                return (.nonText(n), e1, nil, insertionLevel)
            }
            
            if t.end < n.start {
                return (.text(t), nil, e2, insertionLevel)
            } else {
                let (insert, next) = map((t.start ..< t.end).split(up: n.start, nextLow: n.start), t.withBounds)
                return (.text(insert), next, e2, insertionLevel)
            }
        }() else {
            return nil
        }
        
        switch node {
        case .text   : tryLevel = insertLevel
        case .nonText: tryLevel = insertLevel.incremented()
        }
        
        (e1, e2) = (newE1, newE2)
        
        return (node, insertLevel)
    }
}
