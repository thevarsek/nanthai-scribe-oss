import Foundation
import XCTest
@testable import ScribeCore

@MainActor
final class ChunkedRewriterTests: XCTestCase {
    func testChunksPreserveAllCharactersAndPreferParagraphs() {
        let paragraph = String(repeating: "A sentence. ", count: 150) + "\n\n"
        let text = paragraph + String(repeating: "Another sentence. ", count: 400)
        let chunks = RefineChunks.split(text)
        XCTAssertEqual(chunks.joined(), text)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 2_500 })
        XCTAssertEqual(chunks.first, paragraph)
    }

    func testUnbrokenUnicodeTextIsNeverTruncated() {
        let text = String(repeating: "👩🏽‍💻", count: 6_001)
        let chunks = RefineChunks.split(text)
        XCTAssertEqual(chunks.map(\.count), [2_500, 2_500, 1_001])
        XCTAssertEqual(chunks.joined(), text)
        XCTAssertEqual(RefineChunks.split(""), [])
    }

    func testLongRefineFallsBackOnlyForFailedChunkAndSplitsNoteOnce() async throws {
        let first = String(repeating: "First sentence. ", count: 130).trimmingCharacters(in: .whitespaces)
        let second = String(repeating: "Second sentence. ", count: 130)
        let text = first + "\n\n" + second
        let base = RecordingChunkRewriter()
        let output = try await ChunkedRewriter(base).rewrite(RewriteRequest(task: .polish, transcript: text))
        let requests = await base.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map(\.allowsSpokenNote), [true, false])
        XCTAssertTrue(output.hasPrefix("Refined first chunk.\n\n"))
        XCTAssertTrue(output.hasSuffix(TextCleanup.clean(second)))
    }

    func testShortRefineAndEditsArePassedThrough() async throws {
        let base = RecordingChunkRewriter()
        let rewriter = ChunkedRewriter(base)
        _ = try await rewriter.rewrite(RewriteRequest(task: .polish, transcript: "Short."))
        do {
            _ = try await rewriter.rewrite(RewriteRequest(task: .edit(instruction: "Shorter", selection: "Selection"),
                                                         transcript: String(repeating: "word ", count: 1_000)))
            XCTFail("The base's second-call error should propagate for edits")
        } catch { }
        let requests = await base.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.last?.transcript.count, 5_000)
    }
}

private actor RecordingChunkRewriter: TextRewriter {
    nonisolated let id = "chunk-test"
    private(set) var requests: [RewriteRequest] = []
    func isAvailable() async -> Bool { true }
    func rewrite(_ request: RewriteRequest) async throws -> String {
        requests.append(request)
        if requests.count == 2 { throw RewriteError.unavailable("Test failure") }
        return "Refined first chunk."
    }
}
