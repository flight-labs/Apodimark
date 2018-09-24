//
//  MarkdownParser.swift
//  Apodimark
//

let TAB_INDENT = 3

/**
 A MarkdownParser holds the necessary data and type information to parse
 a collection representing some text.
*/
final class MarkdownParser <View: BidirectionalCollection, Codec: MarkdownParserCodec, DefinitionStore: ReferenceDefinitionStore> where
    View.Iterator.Element == Codec.CodeUnit
{
    let view: View
    var definitionStore: DefinitionStore
    let blockTree: Tree<Block>
        
    init(view: View, definitionStore: DefinitionStore) {
        self.definitionStore = definitionStore
        self.view = view
        self.blockTree = .init()
    }
}

// type aliases

extension MarkdownParser {
    typealias Delimiter = (idx: View.Index, kind: DelimiterKind)

    typealias RefDef = DefinitionStore.Definition
    
    typealias Inline = InlineNode<View, RefDef>
    typealias NonTextInline = NonTextInlineNode<View, RefDef>
    typealias TextInline = TextInlineNode<View>
    
    typealias Block = BlockNode<View, RefDef>
    
    typealias LineKind = Apodimark.LineKind<View, RefDef>
    typealias Line = Apodimark.Line<View, RefDef>
}
