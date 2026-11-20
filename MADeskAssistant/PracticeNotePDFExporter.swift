//
//  PracticeNotePDFExporter.swift
//  MADeskAssistant
//
//  Created by Sebastian Esquerra on 9/30/26.
//
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

struct PracticeNotePDFSnapshot {
    let title: String
    let identifier: String
    let savedAt: Date
    let reasonForVisit: String
    let hpi: String
    let ros: String
    let pe: String
    let assessment: String
    let plan: String
    let references: [(code: String, description: String, year: String)]
    let cptLines: [String]

    init(case item: PracticeCase) {
        title = item.title
        identifier = item.identifier
        savedAt = item.updatedAt
        reasonForVisit = item.reasonForVisit
        hpi = item.hpi
        ros = PracticeTemplateStore.exportText(from: item.ros)
        pe = PracticeTemplateStore.exportText(from: item.pe)
        assessment = item.assessment
        plan = item.plan
        references = item.codeReferences
            .sorted { $0.addedAt < $1.addedAt }
            .map { ($0.code, $0.descriptionText, $0.fiscalYear) }
        cptLines = PracticeCPTStore.load(item.cptDraftData).map(PracticeCPTStore.displayLine)
    }
}

struct PracticeNotePDFDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    static var writableContentTypes: [UTType] { [.pdf] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum PracticeNotePDFExporter {
    static func makeDocument(from note: PracticeNotePDFSnapshot) throws -> PracticeNotePDFDocument {
        let pdfData = NSMutableData()

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else {
            throw CocoaError(.fileWriteUnknown)
        }

        var pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)

        guard let context = CGContext(consumer: consumer, mediaBox: &pageRect, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let left: CGFloat = 54
        let right: CGFloat = 54
        let top: CGFloat = 54
        let bottom: CGFloat = 56
        let textWidth = pageRect.width - left - right
        let footerTop = pageRect.height - bottom - 22

        var y: CGFloat = top
        var pageNumber = 0

        func makeText(_ text: String, size: CGFloat, bold: Bool, color: NSColor = .black) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.lineSpacing = 3

            return NSAttributedString(
                string: text,
                attributes: [
                    .font: bold
                        ? NSFont.systemFont(ofSize: size, weight: .semibold)
                        : NSFont.systemFont(ofSize: size),
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]
            )
        }

        func measuredHeight(_ text: NSAttributedString) -> CGFloat {
            ceil(
                text.boundingRect(
                    with: CGSize(width: textWidth, height: 10_000),
                    options: [.usesLineFragmentOrigin, .usesFontLeading]
                ).height
            ) + 3
        }

        func draw(_ text: NSAttributedString, at position: CGFloat) {
            let height = measuredHeight(text)
            text.draw(
                with: CGRect(
                    x: left,
                    y: pageRect.height - position - height,
                    width: textWidth,
                    height: height
                ),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
        }

        func beginPage() {
            context.beginPDFPage(nil)
            pageNumber += 1
            y = top

            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext

            let footer = makeText(
                "Fictional practice case only — not a patient record, diagnosis, or billing document.    Page \(pageNumber)",
                size: 8,
                bold: false,
                color: .darkGray
            )
            draw(footer, at: footerTop)
        }

        func endPage() {
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }

        func ensureSpace(_ height: CGFloat) {
            if y + height > footerTop - 12 {
                endPage()
                beginPage()
            }
        }

        func addLine(
            _ text: String,
            size: CGFloat = 11,
            bold: Bool = false,
            color: NSColor = .black,
            spacingAfter: CGFloat = 8
        ) {
            let attributed = makeText(text, size: size, bold: bold, color: color)
            let height = measuredHeight(attributed)
            ensureSpace(height + spacingAfter)
            draw(attributed, at: y)
            y += height + spacingAfter
        }

        func addSection(_ heading: String, _ value: String) {
            let content = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayValue = content.isEmpty ? "Not entered" : content

            let headingText = makeText(heading, size: 12, bold: true)
            ensureSpace(measuredHeight(headingText) + 22)
            addLine(heading, size: 12, bold: true, spacingAfter: 4)

            // Split long text by paragraph, then by word-sized pieces so no
            // paragraph can run past a page boundary.
            let paragraphs = displayValue.components(separatedBy: .newlines)

            for paragraph in paragraphs {
                if paragraph.isEmpty {
                    addLine(" ", spacingAfter: 2)
                    continue
                }

                var current = ""
                for word in paragraph.split(separator: " ", omittingEmptySubsequences: false) {
                    let candidate = current.isEmpty ? String(word) : current + " " + word

                    if measuredHeight(makeText(candidate, size: 11, bold: false)) > 88,
                       !current.isEmpty {
                        addLine(current, spacingAfter: 2)
                        current = String(word)
                    } else {
                        current = candidate
                    }
                }

                if !current.isEmpty {
                    addLine(current, spacingAfter: 4)
                }
            }

            y += 8
        }

        beginPage()

        addLine(
            "Fictional Practice SOAP Note",
            size: 19,
            bold: true,
            spacingAfter: 6
        )
        addLine(
            "Practice draft only — not a patient record",
            size: 10,
            color: .darkGray,
            spacingAfter: 16
        )

        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = note.identifier.trimmingCharacters(in: .whitespacesAndNewlines)

        addLine("Case title: \(title.isEmpty ? "Not entered" : title)", bold: true)
        addLine("Fake case identifier: \(identifier.isEmpty ? "Not entered" : identifier)")
        addLine(
            "Last saved: \(note.savedAt.formatted(date: .abbreviated, time: .shortened))",
            size: 10,
            color: .darkGray,
            spacingAfter: 18
        )

        addSection("Reason for Visit", note.reasonForVisit)
        addSection("HPI — History of Present Illness", note.hpi)
        addSection("ROS — Review of Systems", note.ros)
        addSection("PE — Physical Examination", note.pe)
        addSection("Assessment", note.assessment)
        addSection("Plan", note.plan)

        addLine(
            "ICD-10-CM References for Review",
            size: 12,
            bold: true,
            spacingAfter: 8
        )

        if note.references.isEmpty {
            addLine("None selected")
        } else {
            for reference in note.references {
                addLine(
                    "\(reference.code) — \(reference.description) (\(reference.year))",
                    spacingAfter: 8
                )
            }
        }

        addLine(
            "References are for review. They are not assigned diagnoses or final billing codes.",
            size: 9,
            color: .darkGray,
            spacingAfter: 12
        )

        addLine(
            "CPT Practice Codes",
            size: 12,
            bold: true,
            spacingAfter: 8
        )
        if note.cptLines.isEmpty {
            addLine("None selected")
        } else {
            for line in note.cptLines {
                addLine(line, spacingAfter: 8)
            }
        }
        addLine(
            "CPT entries are a teaching subset, not the official CPT code set and not a final billing choice.",
            size: 9,
            color: .darkGray
        )

        endPage()
        context.closePDF()

        guard pdfData.length > 0 else {
            throw CocoaError(.fileWriteUnknown)
        }

        return PracticeNotePDFDocument(data: pdfData as Data)
    }
}
