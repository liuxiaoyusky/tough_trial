import Foundation

/// Shared by the native iPhone and Mac editors. Paragraph boundaries follow NSString,
/// including CRLF and Unicode separators, rather than only the ASCII newline.
public enum V2TaskDocumentContent {
    public static func join(title: String, note: String) -> String {
        note.isEmpty ? title : title + "\n" + note
    }

    public static func split(_ text: String) -> (title: String, note: String) {
        let string = text as NSString
        var end = 0, contentsEnd = 0
        string.getParagraphStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: 0, length: 0))
        return (string.substring(to: contentsEnd).trimmingCharacters(in: .whitespacesAndNewlines),
                string.substring(from: end))
    }
}
