import SwiftUI
import UniformTypeIdentifiers

nonisolated struct MarkdownDocument: FileDocument {
    var text: String

    init(text: String = "") {
        self.text = text
    }

    static let markdownType = UTType(importedAs: "net.daringfireball.markdown",
                                     conformingTo: .plainText)

    static let readableContentTypes: [UTType] = [markdownType, .plainText]
    static let writableContentTypes: [UTType] = [markdownType]

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
