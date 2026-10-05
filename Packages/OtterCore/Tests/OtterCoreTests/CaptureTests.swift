import Foundation
import Testing
@testable import OtterCore

/// The outbox's coding: ISO 8601 dates.
private func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

private func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}

@Test func captureWrittenBeforeTitlesExistedDecodesAsUnnamed() throws {
    let json = """
        {
          "id": "6A1F2C3D-0000-4000-8000-000000000001",
          "createdAt": "2026-09-21T14:13:20Z",
          "timeZoneIdentifier": "Europe/Paris",
          "text": "Buy oat milk",
          "attachments": [],
          "destinationID": "6A1F2C3D-0000-4000-8000-000000000002",
          "source": "panel"
        }
        """
    let capture = try decoder().decode(Capture.self, from: Data(json.utf8))
    #expect(capture.title == nil)
    #expect(capture.text == "Buy oat milk")
    #expect(capture.createdAt == referenceDate)
}

@Test func titleAndFileSurviveTheOutboxCoding() throws {
    let file = URL(fileURLWithPath: "/Users/me/Notes/Groceries list.md")
    let capture = makeCapture(title: "Groceries list", fileURL: file, destination: DestinationID())
    let decoded = try decoder().decode(Capture.self, from: encoder().encode(capture))
    #expect(decoded == capture)
    #expect(decoded.title == "Groceries list")
    #expect(decoded.fileURL == file)
}

@Test func unnamedCaptureWritesNoTitleKey() throws {
    let json = try encoder().encode(makeCapture(destination: DestinationID()))
    let object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
    #expect(object["title"] == nil)
    #expect(object["fileURL"] == nil)
}
