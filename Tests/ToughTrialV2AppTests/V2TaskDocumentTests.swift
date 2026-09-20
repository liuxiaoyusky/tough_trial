import XCTest
import SwiftUI
import UIKit
import ToughTrialV2Core
@testable import ToughTrial

final class V2TaskDocumentTests: XCTestCase {
    func testFirstParagraphBecomesTitleAndBodyRetainsBlankLinesAndEmoji() {
        let fields = V2TaskDocumentContent.split("  整理旅行照片  \n挑出十张🧳\n\n周末再看\n")
        XCTAssertEqual(fields.title, "整理旅行照片")
        XCTAssertEqual(fields.note, "挑出十张🧳\n\n周末再看\n")
    }

    func testTitleOnlyAndEmptyFirstParagraphDoNotInventContent() {
        let titleOnly = V2TaskDocumentContent.split("买牛奶")
        XCTAssertEqual(titleOnly.title, "买牛奶")
        XCTAssertEqual(titleOnly.note, "")
        let missingTitle = V2TaskDocumentContent.split("\n只有正文")
        XCTAssertEqual(missingTitle.title, "")
        XCTAssertEqual(missingTitle.note, "只有正文")
        XCTAssertEqual(V2TaskDocumentContent.split("").title, "")
    }

    func testPastedWindowsParagraphBreakDoesNotAddABlankBodyLine() {
        let fields = V2TaskDocumentContent.split("准备行李\r\n带好护照\r\n确认车票")
        XCTAssertEqual(fields.title, "准备行李")
        XCTAssertEqual(fields.note, "带好护照\r\n确认车票")
    }

    func testExistingBodyIsJoinedWithoutTrimmingItsContent() {
        XCTAssertEqual(V2TaskDocumentContent.join(title: "原任务", note: "\n原始段落\n"), "原任务\n\n原始段落\n")
        XCTAssertEqual(V2TaskDocumentContent.join(title: "原任务", note: ""), "原任务")
    }
    @MainActor
    func testSelectionCallbackPublishesTheNativeTextBeforeItsCaret() {
        var text = "原始内容"
        var selection = NSRange(location: 0, length: 0)
        var textWhenCaretChanged = ""
        let input = V2TaskDocumentInput(
            text: Binding(get: { text }, set: { text = $0 }),
            selection: Binding(get: { selection }, set: { selection = $0; textWhenCaretChanged = text }),
            isFocused: .constant(false), isEnabled: true, identifier: "test.document")
        let coordinator = input.makeCoordinator()
        let view = UITextView()
        view.text = "新的内容"
        view.selectedRange = NSRange(location: 4, length: 0)
        // UIKit can report selection before textViewDidChange during replacement.
        coordinator.textViewDidChangeSelection(view)
        XCTAssertEqual(textWhenCaretChanged, "新的内容")
        XCTAssertEqual(text, "新的内容")
        XCTAssertEqual(selection, NSRange(location: 4, length: 0))
    }

    @MainActor
    func testExternalDictationUpdatesTextAndCaretAfterNativeEditing() {
        var text = "整理🧳\n检查车票"
        var selection = NSRange(location: 5, length: 0)
        let input = V2TaskDocumentInput(
            text: Binding(get: { text }, set: { text = $0 }),
            selection: Binding(get: { selection }, set: { selection = $0 }),
            isFocused: .constant(false), isEnabled: true, identifier: "test.document")
        let coordinator = input.makeCoordinator()
        let view = UITextView()
        coordinator.applyBindings(to: view)
        view.text = "整理🧳\n检查护照"
        view.selectedRange = NSRange(location: 9, length: 0)
        coordinator.textViewDidChangeSelection(view)
        coordinator.applyBindings(to: view)
        XCTAssertEqual(view.text, "整理🧳\n检查护照")
        text = "整理🧳\n检查护照和车票"
        selection = NSRange(location: (text as NSString).length, length: 0)
        coordinator.applyBindings(to: view)
        XCTAssertEqual(view.text, text)
        XCTAssertEqual(view.selectedRange, selection)
    }
}
