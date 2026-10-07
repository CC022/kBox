import Foundation

/// One message inside an mbox file: the byte range of its headers and body (without the
/// `From ` envelope line), and the envelope line, whose date is the fallback for a missing Date header.
public struct MessageSlice: Sendable, Equatable {
    public var range: Range<Int>
    public var envelope: String
}

public enum MboxError: LocalizedError, Equatable {
    case notMailbox

    public var errorDescription: String? {
        switch self {
        case .notMailbox: "这不是 mbox 邮箱文件"
        }
    }
}

/// Reading and splitting mbox files (mboxo / mboxrd as written by Gmail, Thunderbird and Apple Mail).
enum Mbox {
    /// Reads an mbox file, or the `mbox` file inside an Apple Mail export (a folder named `xxx.mbox`).
    /// The read is coordinated, so a file in iCloud Drive that is not downloaded yet is fetched first,
    /// and it is copied into memory rather than mapped: a mapped file that is overwritten or truncated
    /// while open would crash the app.
    static func load(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, any Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
            result = Result {
                var isDirectory: ObjCBool = false
                let file = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
                    ? url.appending(path: "mbox")
                    : url
                return try Data(contentsOf: file)
            }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    /// Splits at `From ` lines that start a message. A file that is a single message with no
    /// envelope (an .eml) comes back as one slice.
    static func split(_ data: Data) throws -> [MessageSlice] {
        guard !data.isEmpty else { throw MboxError.notMailbox }
        let base = data.startIndex
        return try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) throws -> [MessageSlice] in
            let count = buffer.count
            var start = 0
            while start < count, [0x0A, 0x0D, 0x20, 0x09].contains(buffer[start]) { start += 1 }
            if count - start >= 3, buffer[start] == 0xEF, buffer[start + 1] == 0xBB, buffer[start + 2] == 0xBF { start += 3 }
            guard start < count else { throw MboxError.notMailbox }

            guard hasFromPrefix(buffer, at: start) else {
                guard looksLikeHeader(buffer, at: start) else { throw MboxError.notMailbox }
                return [MessageSlice(range: (base + start)..<(base + count), envelope: "")]
            }

            var envelopes = [start]
            var offset = start
            while offset < count, let found = memchr(buffer.baseAddress! + offset, 0x0A, count - offset) {
                let lineStart = UnsafeRawPointer(found) - buffer.baseAddress! + 1
                if hasFromPrefix(buffer, at: lineStart), isEnvelope(buffer, at: lineStart) {
                    envelopes.append(lineStart)
                }
                offset = lineStart
            }

            return envelopes.indices.map { index in
                let envelopeStart = envelopes[index]
                let envelopeEnd = lineEnd(buffer, from: envelopeStart)
                let messageStart = min(envelopeEnd + 1, count)
                let messageEnd = max(messageStart, index + 1 < envelopes.count ? envelopes[index + 1] : count)
                var contentEnd = envelopeEnd
                if contentEnd > envelopeStart, buffer[contentEnd - 1] == 0x0D { contentEnd -= 1 }
                let envelope = String(decoding: buffer[envelopeStart..<contentEnd], as: UTF8.self)
                return MessageSlice(range: (base + messageStart)..<(base + messageEnd), envelope: envelope)
            }
        }
    }

    /// The message bytes, with mboxrd quoting (`>From `, `>>From ` …) undone by one level.
    static func message(_ range: Range<Int>, in data: Data) -> Data {
        let raw = data[range]
        guard raw.range(of: Data(">From ".utf8)) != nil else { return raw }
        var output = Data(capacity: raw.count)
        var lineStart = raw.startIndex
        while lineStart < raw.endIndex {
            let end = raw[lineStart...].firstIndex(of: 0x0A).map { $0 + 1 } ?? raw.endIndex
            var quotes = lineStart
            while quotes < end, raw[quotes] == 0x3E { quotes += 1 }
            let isQuotedFrom = quotes > lineStart && raw[quotes..<end].starts(with: Data("From ".utf8))
            output.append(raw[(isQuotedFrom ? lineStart + 1 : lineStart)..<end])
            lineStart = end
        }
        return output
    }

    // MARK: - Byte helpers

    private static func hasFromPrefix(_ buffer: UnsafeRawBufferPointer, at offset: Int) -> Bool {
        offset + 5 <= buffer.count
            && buffer[offset] == 0x46 && buffer[offset + 1] == 0x72 && buffer[offset + 2] == 0x6F
            && buffer[offset + 3] == 0x6D && buffer[offset + 4] == 0x20
    }

    private static func lineEnd(_ buffer: UnsafeRawBufferPointer, from offset: Int) -> Int {
        var index = offset
        while index < buffer.count, buffer[index] != 0x0A { index += 1 }
        return index
    }

    /// A `From ` line inside the file only starts a message when it carries a time (`21:21:13`)
    /// and the next line is a header field — so a body line like "From the team…" does not split.
    private static func isEnvelope(_ buffer: UnsafeRawBufferPointer, at offset: Int) -> Bool {
        let end = lineEnd(buffer, from: offset)
        var hasTime = false
        var index = offset + 5
        while index + 3 <= end {
            if isDigit(buffer[index]), buffer[index + 1] == 0x3A, isDigit(buffer[index + 2]), index + 3 < end, isDigit(buffer[index + 3]) {
                hasTime = true
                break
            }
            index += 1
        }
        return hasTime && end + 1 < buffer.count && looksLikeHeader(buffer, at: end + 1)
    }

    /// `Name:` — printable ASCII other than space and colon, then a colon.
    private static func looksLikeHeader(_ buffer: UnsafeRawBufferPointer, at offset: Int) -> Bool {
        var index = offset
        while index < buffer.count {
            let byte = buffer[index]
            if byte == 0x3A { return index > offset }
            guard byte > 0x20, byte < 0x7F else { return false }
            index += 1
        }
        return false
    }

    private static func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }
}
