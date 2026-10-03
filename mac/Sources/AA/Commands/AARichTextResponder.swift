// Spec: 03 SHELL-503 (rich-text scope and subsets), §6.5.1.13 (rich-text views validate every Format item, find bar,
//       pasteAsPlainText, cancelOperation), SHELL-514; ARCHITECTURE.md §7.6.
import AppKit
import AACore

enum RichKind { case container, sireBody, viewer }

/// Every Format-menu / find command routed to an AA rich-text view.
enum FormatCommand: Hashable {
    case showFonts, bold, italic, underline, strikethrough, bigger, smaller, baselineDefault, superscript, `subscript`,
         showColors, highlight(ARGB?), highlightOther, alignLeft, center, justify, alignRight, bulletedList,
         numberedList, indent, outdent, insertLink, insertTable, insertSavedList, clearFormatting, lockSelection,
         unlockSelection, moveItemUp, moveItemDown, pasteAndMatchStyle, showFind, findNext, findPrevious,
         useSelectionForFind, jumpToSelection
}

/// Adopted by W-CONT's `AARichTextView`, W-SIRE's body view and W-FILES' viewer text view.
@MainActor protocol AARichTextResponder: NSTextView {
    var aaRichKind: RichKind { get }
    func aaValidate(_ c: FormatCommand) -> Bool
    func aaPerform(_ c: FormatCommand)
}

extension RichKind {
    var shellKind: ShellRichKind {
        switch self {
        case .container: return .container
        case .sireBody: return .sireBody
        case .viewer: return .viewer
        }
    }
}

extension FormatCommand {
    /// The Format / Find command a registry command maps to (nil for non-rich commands).
    static func forCommand(_ c: CommandID) -> FormatCommand? {
        switch c {
        case .showFonts: return .showFonts
        case .bold: return .bold
        case .italic: return .italic
        case .underline: return .underline
        case .strikethrough: return .strikethrough
        case .bigger: return .bigger
        case .smaller: return .smaller
        case .baselineDefault: return .baselineDefault
        case .superscript: return .superscript
        case .subscript: return .subscript
        case .showColors: return .showColors
        case .alignLeft: return .alignLeft
        case .center: return .center
        case .justify: return .justify
        case .alignRight: return .alignRight
        case .bulletedList: return .bulletedList
        case .numberedList: return .numberedList
        case .indent: return .indent
        case .outdent: return .outdent
        case .insertLink: return .insertLink
        case .insertTable: return .insertTable
        case .insertSavedList: return .insertSavedList
        case .clearFormatting: return .clearFormatting
        case .lockSelection: return .lockSelection
        case .unlockSelection: return .unlockSelection
        case .moveUp: return .moveItemUp
        case .moveDown: return .moveItemDown
        case .pasteAndMatchStyle: return .pasteAndMatchStyle
        case .find: return .showFind
        case .findNext: return .findNext
        case .findPrevious: return .findPrevious
        case .useSelectionForFind: return .useSelectionForFind
        case .jumpToSelection: return .jumpToSelection
        default: return nil
        }
    }
}

extension ShellFindAction {
    var formatCommand: FormatCommand {
        switch self {
        case .showFind: return .showFind
        case .findNext: return .findNext
        case .findPrevious: return .findPrevious
        case .useSelectionForFind: return .useSelectionForFind
        case .jumpToSelection: return .jumpToSelection
        }
    }
}
