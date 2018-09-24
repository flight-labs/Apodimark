//
//  Apodimark.swift
//  Apodimark
//

/** A ReferenceDefinitionStore manages the references found in a markdown text.
 
 It stores *reference definitions*, which can be of any type, but will typically
 be strings.
 
 A *reference definition* can be added or retrieved from the store by specifying
 its *key*. The *key* is the string used between brackets to identify a reference.
 ```
 This is a [reference][key] whose definition is "hello"
 
 [key]: hello
 ```
 */
public protocol ReferenceDefinitionStore {
    associatedtype Definition: ReferenceDefinitionProtocol
    
    /// Add a reference definition to the store
    mutating func add(key: String, value: String)
    
    /// Retrieve the reference definition for the given key
    func definition(for key: String) -> Definition?
}

/**
 A ReferenceDefinitionStore that acts as a simple dictionary.
 
 Once a definition is added for a certain key, it cannot be overwritten.
 */
public struct DefaultReferenceDefinitionStore: ReferenceDefinitionStore {
    public typealias Definition = String
    
    var _dic: [String: String] = [:]
    
    /// Creates an empty store
    public init() {}

    public mutating func add(key: String, value: String) {
        let lowercasedKey = key.lowercased()
        if _dic[lowercasedKey] == nil {
            _dic[lowercasedKey] = value
        }
    }
    public func definition(for key: String) -> String? {
        return _dic[key.lowercased()]
    }
}

/// A protocol for types that can be used as a reference definition.
public protocol ReferenceDefinitionProtocol {
    init(string: String)
}
extension String: ReferenceDefinitionProtocol {
    public init(string: String) { self = string }
}

public enum EmphasisType {
    case bold
    case italic
    case underline
    case strikethrough
}

public struct ParagraphBlock <View: BidirectionalCollection, RefDef> {
    public let text: [MarkdownInline<View, RefDef>]
    public let indent: Int
}

public struct HeaderBlock <View: BidirectionalCollection, RefDef> {
    public let level: Int
    public let text: [MarkdownInline<View, RefDef>]
    public let markers: (Range<View.Index>, Range<View.Index>?)
}

public struct QuoteBlock <View: BidirectionalCollection, RefDef> {
    public let content: [MarkdownBlock<View, RefDef>]
    public let markers: [View.Index]
}

public struct ListItemBlock <View: BidirectionalCollection, RefDef> {
    public let marker: Range<View.Index>
    public let content: [MarkdownBlock<View, RefDef>]
}

public struct ListBlock <View: BidirectionalCollection, RefDef> {
    public let kind: ListBlockKind
    public let items: [ListItemBlock<View, RefDef>]
}

public struct FenceBlock <View: BidirectionalCollection> {
    public let name: Range<View.Index>
    public let text: [Range<View.Index>]
    public let markers: (Range<View.Index>, Range<View.Index>?)
}

public struct CodeBlock <View: BidirectionalCollection> {
    public let text: [Range<View.Index>]
}

public struct ReferenceDefinitionBlock <View: BidirectionalCollection, RefDef> {
    public let key: Range<View.Index>
    public let definition: Range<View.Index>
}

public struct ThematicBreakBlock <View: BidirectionalCollection> {
    public let marker: Range<View.Index>
}

public struct TextInline <View: BidirectionalCollection> {
    public let span: Range<View.Index>
}

public struct BreakInline <View: BidirectionalCollection> {
    public let span: Range<View.Index>
}

public struct ReferenceInline <View: BidirectionalCollection, RefDef> {
    public let kind: ReferenceKind
    public let title: [MarkdownInline<View, RefDef>]
    public let definition: RefDef
    public let markers: [Range<View.Index>]
}

public struct EmphasisInline <View: BidirectionalCollection, RefDef> {
    public let level: Int
    public let type: EmphasisType
    public let content: [MarkdownInline<View, RefDef>]
    public let markers: (Range<View.Index>, Range<View.Index>)
}

public struct MonospacedTextInline <View: BidirectionalCollection, RefDef> {
    public let content: [MarkdownInline<View, RefDef>]
    public let markers: (Range<View.Index>, Range<View.Index>)
}

public struct EscapingBackslashInline <View: BidirectionalCollection> {
    public let index: View.Index
}

public indirect enum MarkdownInline <View: BidirectionalCollection, RefDef> {
    case text(TextInline<View>)
    case reference(ReferenceInline<View, RefDef>)
    case emphasis(EmphasisInline<View, RefDef>)
    case monospacedText(MonospacedTextInline<View, RefDef>)
    case escapingBackslash(EscapingBackslashInline<View>)
    case softbreak(BreakInline<View>)
    case hardbreak(BreakInline<View>)
}

public indirect enum MarkdownBlock <View: BidirectionalCollection, RefDef> {
    case paragraph(ParagraphBlock<View, RefDef>)
    case header(HeaderBlock<View, RefDef>)
    case quote(QuoteBlock<View, RefDef>)
    case list(ListBlock<View, RefDef>)
    case fence(FenceBlock<View>)
    case code(CodeBlock<View>)
    case referenceDefinition(ReferenceDefinitionBlock<View, RefDef>)
    case thematicBreak(ThematicBreakBlock<View>)
}

public enum ListBlockKind {

    case unordered
    case ordered(startingAt: Int)

    init(kind: ListKind) {
        switch kind {
        case .bullet(_): self = .unordered
        case .number(_, let n): self = .ordered(startingAt: n)
        }
    }
}

/**
 Parses a markdown document.
 
 - parameter source:          a BidirectionalCollection holding the text to parse
 - parameter definitionStore: an initial ReferenceDefinitionStore to use for handling references
 - parameter codec:           a MarkdownParserCodec capable of reading the `source`

 - returns: an array of MarkdownBlock defining the markdown document
 */
@_specialize(where View == String.UTF16View, DefinitionStore == DefaultReferenceDefinitionStore, Codec == UTF16MarkdownCodec)
public func parsedMarkdown <View, DefinitionStore, Codec> (source: View, definitionStore: DefinitionStore, codec: Codec.Type) -> [MarkdownBlock<View, DefinitionStore.Definition>] where
    View: BidirectionalCollection,
    DefinitionStore: ReferenceDefinitionStore,
    Codec: MarkdownParserCodec,
    View.Iterator.Element == Codec.CodeUnit
{
    return MarkdownParser<View, Codec, DefinitionStore>(view: source, definitionStore: definitionStore).finalAST()
}

extension MarkdownParser {

    /// Parse the collection and return the Abstract Syntax Tree
    /// describing the original Markdown document
    fileprivate func finalAST() -> [MarkdownBlock<View, RefDef>] {
        parseBlocks()
        updateDefinitionStore()
        return blockTree.makeBreadthFirstIterator().compactMap(makeFinalBlock)
    }
    
    /// Return a MarkdownBlock from an instance of the internal BlockNode type and its children
    fileprivate func makeFinalBlock(from node: Block, children: TreeBreadthFirstIterator<Block>?) -> MarkdownBlock<View, RefDef>? {
        switch node {
            
        case let .paragraph(p):
            let inlines = makeFinalInlineNodeTree(from: parseInlines(p.text).makeBreadthFirstIterator())
            let block = ParagraphBlock(text: inlines, indent: p.indent)
            return .paragraph(block)
            
            
        case let .header(h):
            let block = HeaderBlock(
                level: numericCast(h.level),
                text: makeFinalInlineNodeTree(from: parseInlines([h.text]).makeBreadthFirstIterator()),
                markers: h.markers
            )
            return .header(block)
            
            
        case let .quote(q):
            
            let block = QuoteBlock(
                content: children?.compactMap(makeFinalBlock) ?? [],
                markers: q.markers
            )
            
            return .quote(block)
        
        case .listItem:
            fatalError()
        
        case let .list(l):
            let items = children?.map { (n, c) -> ListItemBlock<View, RefDef> in
                guard case .listItem(let i) = n else { return .init(marker: view.startIndex ..< view.startIndex, content: []) }
                return ListItemBlock<View, RefDef>(
                    marker: i.markerSpan,
                    content: c?.compactMap(makeFinalBlock) ?? []
                )
            } ?? []
            
            let block = ListBlock(kind: ListBlockKind(kind: l.kind), items: items)
            
            return .list(block)
            
            
        case let .code(c):
            return .code(CodeBlock(text: c.text))
            
            
        case let .fence(f):
            let block = FenceBlock<View>(
                name: f.name,
                text: f.text,
                markers: f.markers
            )
            return .fence(block)
            
            
        case let .thematicBreak(t):
            return .thematicBreak(ThematicBreakBlock(marker: t.span))
            
            
        case let .referenceDefinition(r):
            return .referenceDefinition(.init(key: r.title, definition: r.definition))
        }
    }

}

extension MarkdownParser {
    /// Returns an array of MarkdownInline from a tree of InlineNode
    fileprivate func makeFinalInlineNodeTree(from tree: TreeBreadthFirstIterator<Inline>) -> [MarkdownInline<View, RefDef>] {
        
        var nodes: [MarkdownInline<View, RefDef>] = []
        
        for (node, children) in tree {
            switch node {
            case .text(let t):
                switch t.kind {
                    
                case .hardbreak:
                    nodes.append(.hardbreak(BreakInline(span: t.start ..< t.end)))
                    
                case .softbreak:
                    nodes.append(.softbreak(BreakInline(span: t.start ..< t.end)))
                    
                case .text:
                    nodes.append(.text(Apodimark.TextInline(span: t.start ..< t.end)))
                }
    
            case .nonText(let n):
                switch n.kind {
                case .code(let level):
                    let startMarkers = n.start ..< view.index(n.start, offsetBy: numericCast(level))
                    let endMarkers = view.index(n.end, offsetBy: numericCast(-level)) ..< n.end
                    
                    let inline = MonospacedTextInline(
                        content: children.map(makeFinalInlineNodeTree) ?? [],
                        markers: (startMarkers, endMarkers)
                    )
                    nodes.append(.monospacedText(inline))
                    
                case let .emphasis(level, type):
                    let startMarkers = n.start ..< view.index(n.start, offsetBy: numericCast(level))
                    let endMarkers = view.index(n.end, offsetBy: numericCast(-level)) ..< n.end
                    
                    let inline = EmphasisInline(
                        level: numericCast(level),
                        type: type,
                        content: children.map(makeFinalInlineNodeTree) ?? [],
                        markers: (startMarkers, endMarkers)
                    )
                    
                    nodes.append(.emphasis(inline))
                    
                case .reference(let kind, title: let title, definition: let definition):
                    let markers = [n.start ..< title.lowerBound, title.upperBound ..< n.end]
                    
                    let inline = ReferenceInline(
                        kind: kind,
                        title: children.map(makeFinalInlineNodeTree) ?? [],
                        definition: definition,
                        markers: markers
                    )
                    
                    nodes.append(.reference(inline))
                
                case .escapingBackslash:
                    nodes.append(.escapingBackslash(.init(index: n.start)))
                }
            }
        }
        return nodes
    }
}


