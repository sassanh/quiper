import Foundation
import Testing
@testable import Quiper

@MainActor
struct EditorDocumentSessionTests {
    @Test func appliesExternalChangesImmediatelyWhenClean() throws {
        let fixture = try Fixture(initialText: "const original = true;")
        defer { fixture.remove() }
        var acceptedValues: [String] = []
        let session = EditorDocumentSession(
            initialText: fixture.initialText,
            fileURL: fixture.fileURL,
            isReadOnly: false,
            onAcceptedChange: { acceptedValues.append($0) }
        )

        try fixture.write("const external = true;")
        session.checkForExternalChanges()

        #expect(session.text == "const external = true;")
        #expect(session.status == .updatedExternally)
        #expect(acceptedValues == ["const external = true;"])
        session.stop()
    }

    @Test func reportsConflictWhenExternalFileChangesDuringInternalEdit() throws {
        let fixture = try Fixture(initialText: "body { color: black; }")
        defer { fixture.remove() }
        let session = EditorDocumentSession(
            initialText: fixture.initialText,
            fileURL: fixture.fileURL,
            isReadOnly: false,
            saveDelay: .seconds(60),
            onAcceptedChange: { _ in }
        )

        session.userDidEdit("body { color: blue; }")
        try fixture.write("body { color: red; }")
        session.checkForExternalChanges()

        #expect(session.status == .conflict)
        #expect(session.conflict?.externalText == "body { color: red; }")
        session.stop()
    }

    @Test func loadExternalResolvesConflictWithoutOverwritingDisk() throws {
        let fixture = try Fixture(initialText: "textarea")
        defer { fixture.remove() }
        var acceptedValue = ""
        let session = EditorDocumentSession(
            initialText: fixture.initialText,
            fileURL: fixture.fileURL,
            isReadOnly: false,
            saveDelay: .seconds(60),
            onAcceptedChange: { acceptedValue = $0 }
        )

        session.userDidEdit("input")
        try fixture.write("[contenteditable=\"true\"]")
        session.checkForExternalChanges()
        session.loadExternalVersion()

        #expect(session.conflict == nil)
        #expect(session.text == "[contenteditable=\"true\"]")
        #expect(acceptedValue == "[contenteditable=\"true\"]")
        #expect(try fixture.read() == "[contenteditable=\"true\"]")
        session.stop()
    }

    @Test func keepMineResolvesConflictByReplacingDiskVersion() throws {
        let fixture = try Fixture(initialText: "const value = 1;")
        defer { fixture.remove() }
        let session = EditorDocumentSession(
            initialText: fixture.initialText,
            fileURL: fixture.fileURL,
            isReadOnly: false,
            saveDelay: .seconds(60),
            onAcceptedChange: { TextFileStorage.save($0, to: fixture.fileURL) }
        )

        session.userDidEdit("const value = 2;")
        try fixture.write("const value = 3;")
        session.checkForExternalChanges()
        session.keepInternalVersion()

        #expect(session.conflict == nil)
        #expect(session.status == .saved)
        #expect(try fixture.read() == "const value = 2;")
        session.stop()
    }

    @Test func externalDeletionClearsTheDocument() throws {
        let fixture = try Fixture(initialText: ".composer")
        defer { fixture.remove() }
        var acceptedValue: String?
        let session = EditorDocumentSession(
            initialText: fixture.initialText,
            fileURL: fixture.fileURL,
            isReadOnly: false,
            onAcceptedChange: { acceptedValue = $0 }
        )

        try FileManager.default.removeItem(at: fixture.fileURL)
        session.checkForExternalChanges()

        #expect(session.text.isEmpty)
        #expect(acceptedValue == "")
        session.stop()
    }

    @Test func readOnlySessionRejectsInternalEdits() throws {
        let fixture = try Fixture(initialText: "textarea")
        defer { fixture.remove() }
        var acceptedValue: String?
        let session = EditorDocumentSession(
            initialText: fixture.initialText,
            fileURL: fixture.fileURL,
            isReadOnly: true,
            onAcceptedChange: { acceptedValue = $0 }
        )

        session.userDidEdit("input")

        #expect(session.text == "textarea")
        #expect(acceptedValue == nil)
        session.stop()
    }
}

private struct Fixture {
    let directoryURL: URL
    let fileURL: URL
    let initialText: String

    init(initialText: String) throws {
        self.initialText = initialText
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuiperEditorSessionTests-\(UUID().uuidString)", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("document.txt")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data(initialText.utf8).write(to: fileURL, options: .atomic)
    }

    func write(_ text: String) throws {
        try Data(text.utf8).write(to: fileURL, options: .atomic)
    }

    func read() throws -> String {
        let data = try Data(contentsOf: fileURL)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
