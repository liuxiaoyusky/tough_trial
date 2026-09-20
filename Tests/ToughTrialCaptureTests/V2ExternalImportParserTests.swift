import Foundation
import XCTest
import zlib
@testable import ToughTrialV2Core

final class V2ExternalImportParserTests: XCTestCase {
    func testICSKeepsFoldedFieldsTimezoneRecurrenceAndCancellation() throws {
        let source = """
        BEGIN:VCALENDAR\r
        VERSION:2.0\r
        BEGIN:VEVENT\r
        UID:calendar-event-1@example.com\r
        DTSTART;TZID=Asia/Hong_Kong:20260910T093000\r
        DTEND;TZID=Asia/Hong_Kong:20260910T103000\r
        SUMMARY:项目同步\\,第一次\r
        DESCRIPTION:第一行说明\r
         第二行说明\r
        RRULE:FREQ=WEEKLY;BYDAY=MO\r
        EXDATE;TZID=Asia/Hong_Kong:20260917T093000\r
        STATUS:CANCELLED\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        UID:all-day-event@example.com\r
        DTSTART;VALUE=DATE:20260911\r
        SUMMARY:全天安排\r
        END:VEVENT\r
        END:VCALENDAR\r
        """

        let first = try V2ExternalImportParser.recognize(
            data: Data(source.utf8),
            fileName: "apple-calendar.ics"
        )
        let second = try V2ExternalImportParser.recognize(
            data: Data(source.utf8),
            fileName: "apple-calendar.ics"
        )

        XCTAssertEqual(first.format, "ics")
        XCTAssertEqual(first.fingerprint, second.fingerprint)
        XCTAssertEqual(first.records.map(\.id), second.records.map(\.id))
        XCTAssertEqual(first.records.count, 2)
        XCTAssertEqual(first.records[0].kind, .calendar)
        XCTAssertEqual(first.records[0].title, "项目同步,第一次")
        XCTAssertTrue(first.records[0].text.contains("UID:calendar-event-1@example.com"))
        XCTAssertTrue(first.records[0].text.contains("DTSTART;TZID=Asia/Hong_Kong:20260910T093000"))
        XCTAssertTrue(first.records[0].text.contains("RRULE:FREQ=WEEKLY;BYDAY=MO"))
        XCTAssertTrue(first.records[0].text.contains("EXDATE;TZID=Asia/Hong_Kong:20260917T093000"))
        XCTAssertTrue(first.records[0].text.contains("DESCRIPTION:第一行说明第二行说明"))
        XCTAssertTrue(first.records[0].warnings.contains(where: { $0.contains("重复") }))
        XCTAssertTrue(first.records[0].warnings.contains(where: { $0.contains("CANCELLED") }))
        XCTAssertTrue(first.warnings.contains(where: { $0.contains("未自动展开") }))
        XCTAssertTrue(first.records[1].text.contains("VALUE=DATE:20260911"))
    }

    func testCSVPreservesQuotedNewlinesNegativeAmountsAndCurrencies() throws {
        let source = """
        Date,Description,Amount,Currency,Direction\r
        2026-09-10,"Lunch,\r
        with friend",-38,CNY,expense\r
        2026-09-11,"Refund",12.5,USD,income\r
        """

        let preview = try V2ExternalImportParser.recognize(
            data: Data(source.utf8),
            fileName: "MoneyThings-export.csv"
        )

        XCTAssertEqual(preview.format, "csv")
        XCTAssertEqual(preview.records.count, 2)
        XCTAssertEqual(preview.records[0].kind, .ledger)
        XCTAssertTrue(preview.records[0].text.contains("Lunch,\r\nwith friend"))
        XCTAssertTrue(preview.records[0].text.contains("列 3 Amount: -38"))
        XCTAssertTrue(preview.records[0].text.contains("列 4 Currency: CNY"))
        XCTAssertTrue(preview.records[1].text.contains("USD"))
        XCTAssertTrue(preview.warnings.joined().contains("原始值"))
    }

    func testTSVWithUTF16BOMIsDecodedAndKeepsEmptyColumns() throws {
        let source = "日期\t描述\t金额\t币种\n2026-09-10\t咖啡\t-18\t\n"
        var data = Data([0xFF, 0xFE])
        data.append(String(source).data(using: .utf16LittleEndian)!)

        let preview = try V2ExternalImportParser.recognize(data: data, fileName: "money.tsv")

        XCTAssertEqual(preview.format, "tsv")
        XCTAssertEqual(preview.records.count, 1)
        XCTAssertTrue(preview.records[0].text.contains("列 2 描述: 咖啡"))
        XCTAssertTrue(preview.records[0].text.contains("列 4 币种: "))
        XCTAssertTrue(preview.records[0].warnings.isEmpty)
    }

    func testJSONDayOneEntriesKeepFullFieldsAndDoNotInventCurrency() throws {
        let source = """
        {
          "entries": [
            {
              "uuid": "day-one-1",
              "creationDate": "2026-09-10T09:30:00Z",
              "text": "今天完成了第一次复盘",
              "tags": ["工作", "回想"],
              "photos": [{"identifier": "asset-1"}]
            },
            {
              "date": "2026-09-10",
              "merchant": "Coffee",
              "amount": 18
            }
          ]
        }
        """

        let preview = try V2ExternalImportParser.recognize(data: Data(source.utf8), fileName: "dayone.json")

        XCTAssertEqual(preview.format, "json")
        XCTAssertEqual(preview.records.count, 2)
        XCTAssertEqual(preview.records[0].kind, .journal)
        XCTAssertTrue(preview.records[0].text.contains("\"photos\""))
        XCTAssertTrue(preview.records[0].text.contains("第一次复盘"))
        XCTAssertEqual(preview.records[1].kind, .ledger)
        XCTAssertTrue(preview.records[1].warnings.contains(where: { $0.contains("币种") }))
        XCTAssertFalse(preview.records[1].text.contains("CNY"))
    }

    func testMarkdownIsOneLosslessJournalRecord() throws {
        let source = "# 今天\n\n这是一段日志，保留 **Markdown** 原文。\n"
        let preview = try V2ExternalImportParser.recognize(data: Data(source.utf8), fileName: "journal.md")
        XCTAssertEqual(preview.records.count, 1)
        XCTAssertEqual(preview.records[0].kind, .journal)
        XCTAssertEqual(preview.records[0].title, "今天")
        XCTAssertEqual(preview.records[0].text, source)
    }

    func testUnsupportedFormatsMalformedFilesAndLimitsAreExplicit() throws {
        for name in ["export.xls", "export.pdf", "export.zip"] {
            XCTAssertThrowsError(try V2ExternalImportParser.recognize(data: Data([1, 2, 3]), fileName: name)) { error in
                guard case .unsupportedFormat = error as? V2ExternalImportError else {
                    return XCTFail("expected unsupported format for \(name), got \(error)")
                }
            }
        }

        XCTAssertThrowsError(
            try V2ExternalImportParser.recognize(data: Data("Date,Description\\n2026,\"unfinished".utf8), fileName: "bad.csv")
        ) { error in
            XCTAssertEqual(error as? V2ExternalImportError, .malformed("CSV/TSV 引号没有闭合"))
        }

        let oversized = Data(repeating: 0x20, count: V2ExternalImportParser.maxInputBytes + 1)
        XCTAssertThrowsError(try V2ExternalImportParser.recognize(data: oversized, fileName: "large.txt")) { error in
            XCTAssertEqual(error as? V2ExternalImportError, .inputTooLarge(maxBytes: V2ExternalImportParser.maxInputBytes))
        }

        var rows = ["Date,Amount"]
        rows.append(contentsOf: (0...V2ExternalImportParser.maxRecords).map { "2026-09-10,\($0)" })
        XCTAssertThrowsError(
            try V2ExternalImportParser.recognize(data: Data(rows.joined(separator: "\n").utf8), fileName: "too-many.csv")
        ) { error in
            XCTAssertEqual(error as? V2ExternalImportError, .tooManyRecords(maxRecords: V2ExternalImportParser.maxRecords))
        }
    }

    func testXLSXReadsAllWorksheetCellsAndMarksExcelDateSerial() throws {
        let files: [(String, Data)] = [
            ("[Content_Types].xml", Data(#"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"></Types>"#.utf8)),
            ("xl/workbook.xml", Data(#"<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><workbookPr date1904="0"/><sheets><sheet name="MoneyThings" sheetId="1" r:id="rId1"/></sheets></workbook>"#.utf8)),
            ("xl/_rels/workbook.xml.rels", Data(#"<Relationships><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>"#.utf8)),
            ("xl/sharedStrings.xml", Data(#"<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><si><t>Shared note</t></si></sst>"#.utf8)),
            ("xl/styles.xml", Data(#"<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><cellXfs count="2"><xf numFmtId="0"/><xf numFmtId="14"/></cellXfs></styleSheet>"#.utf8)),
            ("xl/worksheets/sheet1.xml", Data("""
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
            <row r="1"><c r="A1" t="inlineStr"><is><t>Date</t></is></c><c r="B1" t="inlineStr"><is><t>Amount</t></is></c><c r="C1" t="inlineStr"><is><t>Currency</t></is></c><c r="D1" t="inlineStr"><is><t>Description</t></is></c></row>
            <row r="2"><c r="A2" s="1"><v>45658</v></c><c r="B2"><v>-38</v></c><c r="C2" t="inlineStr"><is><t>CNY</t></is></c><c r="D2" t="s"><v>0</v></c></row>
            </sheetData></worksheet>
            """.utf8))
        ]

        let preview = try V2ExternalImportParser.recognize(
            data: makeStoredZip(files),
            fileName: "MoneyThings.xlsx"
        )

        XCTAssertEqual(preview.format, "xlsx")
        XCTAssertEqual(preview.records.count, 1)
        XCTAssertTrue(preview.records[0].text.contains("工作表: MoneyThings"))
        XCTAssertTrue(preview.records[0].text.contains("列 1 A:"))
        XCTAssertTrue(preview.records[0].text.contains("Excel serial: 45658"))
        XCTAssertTrue(preview.records[0].text.contains("列 2 B: -38"))
        XCTAssertTrue(preview.records[0].text.contains("列 3 C: CNY"))
        XCTAssertTrue(preview.records[0].text.contains("Shared note"))
    }

    func testXLSXWorksheetNamesFollowRelationshipsAndIgnoreExternalTargets() throws {
        let sheet = Data(#"<worksheet><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Note</t></is></c></row><row r="2"><c r="A2" t="inlineStr"><is><t>Record</t></is></c></row></sheetData></worksheet>"#.utf8)
        let files: [(String, Data)] = [
            ("[Content_Types].xml", Data("<Types/>".utf8)),
            ("xl/workbook.xml", Data(#"<workbook><sheets><sheet name="Second" r:id="b"/><sheet name="First" r:id="a"/><sheet name="External" r:id="c"/></sheets></workbook>"#.utf8)),
            ("xl/_rels/workbook.xml.rels", Data(#"<Relationships><Relationship Id="b" Type="urn:test/worksheet" Target="/xl/worksheets/sheet2.xml"/><Relationship Id="a" Type="urn:test/worksheet" Target="./worksheets/sheet1.xml"/><Relationship Id="c" Type="urn:test/worksheet" Target="worksheets/sheet3.xml" TargetMode="External"/></Relationships>"#.utf8)),
            ("xl/worksheets/sheet1.xml", sheet), ("xl/worksheets/sheet2.xml", sheet), ("xl/worksheets/sheet3.xml", sheet)
        ]
        let preview = try V2ExternalImportParser.recognize(data: makeStoredZip(files), fileName: "sheets.xlsx")
        XCTAssertEqual(preview.records.count, 3)
        XCTAssertTrue(preview.records[0].text.contains("工作表: First"))
        XCTAssertTrue(preview.records[1].text.contains("工作表: Second"))
        XCTAssertTrue(preview.records[2].text.contains("工作表: xl/worksheets/sheet3.xml"))
        XCTAssertFalse(preview.records[2].text.contains("External"))
        XCTAssertTrue(preview.warnings.contains { $0.contains("关系缺失") })
    }

    func testDeflatedXLSXAndCorruptedChecksum() throws {
        let bytes = Data(base64Encoded: "UEsDBBQAAAAIAHsNKl3HHBc8CgAAAAgAAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbLMJqSxILda3AwBQSwMEFAAAAAgAew0qXe6ytkxyAAAAwQAAABgAAAB4bC93b3Jrc2hlZXRzL3NoZWV0MS54bWyzKc8vyi7OSE0tsbMBUy6JJYl2NkX55QpFtkqGSnY2ySCGo6GSQomtUmZeTmZeanBJEVA8s9jOpsTOL78k1UYfqFkfxNdPBmKgXrgBRnADjHAY4JKalpNYkpqikFOal5yh4OwXqWBkgc1EfSTn6SNcDQBQSwECFAMUAAAACAB7DSpdxxwXPAoAAAAIAAAAEwAAAAAAAAAAAAAAgAEAAAAAW0NvbnRlbnRfVHlwZXNdLnhtbFBLAQIUAxQAAAAIAHsNKl3usrZMcgAAAMEAAAAYAAAAAAAAAAAAAACAATsAAAB4bC93b3Jrc2hlZXRzL3NoZWV0MS54bWxQSwUGAAAAAAIAAgCHAAAA4wAAAAAA")!
        let preview = try V2ExternalImportParser.recognize(data: bytes, fileName: "compressed.xlsx")
        XCTAssertTrue(preview.records[0].text.contains("Deflated lunch CNY 28"))
        var corrupt = bytes
        let signature = Data([0x50, 0x4b, 0x01, 0x02])
        let first = try XCTUnwrap(corrupt.range(of: signature))
        let second = try XCTUnwrap(corrupt.range(of: signature, in: first.upperBound..<corrupt.count))
        corrupt[second.lowerBound + 16] ^= 1
        XCTAssertThrowsError(try V2ExternalImportParser.recognize(data: corrupt, fileName: "corrupt.xlsx"))
    }

    private func checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { UInt32(zlib.crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count))) }
    }

    private func makeStoredZip(_ files: [(String, Data)]) -> Data {
        var output = Data()
        var offsets: [UInt32] = []

        for (name, data) in files {
            offsets.append(UInt32(output.count))
            appendUInt32(0x0403_4b50, to: &output)
            appendUInt16(20, to: &output) // version needed
            appendUInt16(0, to: &output) // flags
            appendUInt16(0, to: &output) // stored
            appendUInt16(0, to: &output) // time
            appendUInt16(0, to: &output) // date
            appendUInt32(checksum(data), to: &output)
            appendUInt32(UInt32(data.count), to: &output)
            appendUInt32(UInt32(data.count), to: &output)
            appendUInt16(UInt16(name.utf8.count), to: &output)
            appendUInt16(0, to: &output)
            output.append(contentsOf: name.utf8)
            output.append(data)
        }

        let centralDirectoryOffset = UInt32(output.count)
        for (index, file) in files.enumerated() {
            let name = file.0
            let data = file.1
            appendUInt32(0x0201_4b50, to: &output)
            appendUInt16(20, to: &output)
            appendUInt16(20, to: &output)
            appendUInt16(0, to: &output)
            appendUInt16(0, to: &output)
            appendUInt16(0, to: &output)
            appendUInt16(0, to: &output)
            appendUInt32(checksum(data), to: &output)
            appendUInt32(UInt32(data.count), to: &output)
            appendUInt32(UInt32(data.count), to: &output)
            appendUInt16(UInt16(name.utf8.count), to: &output)
            appendUInt16(0, to: &output)
            appendUInt16(0, to: &output)
            appendUInt16(0, to: &output)
            appendUInt16(0, to: &output)
            appendUInt32(0, to: &output)
            appendUInt32(offsets[index], to: &output)
            output.append(contentsOf: name.utf8)
        }
        let centralDirectorySize = UInt32(output.count) - centralDirectoryOffset
        appendUInt32(0x0605_4b50, to: &output)
        appendUInt16(0, to: &output)
        appendUInt16(0, to: &output)
        appendUInt16(UInt16(files.count), to: &output)
        appendUInt16(UInt16(files.count), to: &output)
        appendUInt32(centralDirectorySize, to: &output)
        appendUInt32(centralDirectoryOffset, to: &output)
        appendUInt16(0, to: &output)
        return output
    }

    private func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
    }

    private func appendUInt32(_ value: UInt32, to data: inout Data) {
        appendUInt16(UInt16(value & 0xffff), to: &data)
        appendUInt16(UInt16((value >> 16) & 0xffff), to: &data)
    }
}
