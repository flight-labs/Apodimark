//
//  InlineNode.swift
//  Apodimark
//

public enum ReferenceKind {
    case normal, unwrapped

    var textWidth: Int {
        switch self {
        case .normal   : return 1
        case .unwrapped: return 2
        }
    }
}

enum InlineNode <View: BidirectionalCollection, RefDef: ReferenceDefinitionProtocol> {
    case text(TextInlineNode<View>)
    case nonText(NonTextInlineNode<View, RefDef>)
}

enum NonTextInlineNodeKind <View: BidirectionalCollection, RefDef: ReferenceDefinitionProtocol> {
    indirect case reference(ReferenceKind, title: Range<View.Index>, definition: RefDef)
    case code(Int32)
    case emphasis(Int32, EmphasisType)
    case escapingBackslash
}


enum TextInlineNodeKind {
    case text
    case softbreak
    case hardbreak
}

struct TextInlineNode <View: BidirectionalCollection> {
    let kind: TextInlineNodeKind
    var start: View.Index
    var end: View.Index
}

struct NonTextInlineNode <View: BidirectionalCollection, RefDef: ReferenceDefinitionProtocol> {

    let kind: NonTextInlineNodeKind<View, RefDef>
    var start: View.Index
    var end: View.Index

    func contentRange(inView view: View) -> Range<View.Index> {
        switch kind {
        case .reference(_, let title, _):
            return title
        case .code(let l):
            return view.index(start, offsetBy: numericCast(l)) ..< view.index(end, offsetBy: numericCast(-l))
        case let .emphasis(l, _):
            return view.index(start, offsetBy: numericCast(l)) ..< view.index(end, offsetBy: numericCast(-l))
        case .escapingBackslash:
            return start ..< start
        }
    }
}
