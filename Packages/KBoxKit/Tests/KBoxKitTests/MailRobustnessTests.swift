import Foundation
import Testing
@testable import KBoxKit

/// Malformed input must never crash the byte-level parsers: every truncation of the fixtures and
/// thousands of seeded random mutations go through splitting, summaries, full parsing and rendering.
struct MailRobustnessTests {
    @Test func survivesEveryTruncation() {
        let data = Data(MailFixtures.invoice.utf8)
        for length in 0...data.count {
            exercise(data.prefix(length))
        }
    }

    @Test func survivesRandomMutations() {
        var generator = SplitMix64(seed: 0x6B426F78)
        let base = Array(MailFixtures.mailbox.utf8)
        for _ in 0..<1500 {
            var bytes = base
            for _ in 0..<Int.random(in: 1...6, using: &generator) {
                mutate(&bytes, using: &generator)
            }
            exercise(Data(bytes))
        }
    }

    @Test func survivesSlicesThatDoNotStartAtZero() {
        let data = Data(("junk\n" + MailFixtures.mailbox).utf8)
        for offset in [1, 5, 17] {
            exercise(data.dropFirst(offset))
        }
    }

    @Test func survivesHostileHeaders() {
        let values = [
            "=?", "=?UTF-8?", "=?UTF-8?B?", "=?UTF-8?Q?=?=", "=?UTF-8?X?abc?=", "=??B?YQ==?=", "=?UTF-8?B?????=",
            "\"unterminated <a@b", "<<<>>>", ",,,;;;:::", "a@b (unclosed", "\\\\\\", String(repeating: "=?a?b?", count: 50),
            "Mon, 32 Foo 99999 99:99:99 +9999", "+", "GMT+", "-:", "1 Jan 1 1:1:1", ";;;",
        ]
        for value in values {
            _ = MIME.decodeWords(value)
            _ = MailAddress.parseList(value)
            _ = MailDate.parse(value)
            _ = MailDate.parseReceived(value)
            _ = MIME.parameterized("text/plain; " + value)
            _ = MailHTML.text(fromHTML: value)
            _ = MailHTML.plainTextBody(value)
            _ = MailHTML.hasRemoteReferences(value)
            _ = MailParser.unflow(value, deleteSpace: true)
        }
    }

    private func exercise(_ data: Data) {
        let slices = (try? Mbox.split(data)) ?? [MessageSlice(range: data.startIndex..<data.endIndex, envelope: "")]
        for (index, slice) in slices.enumerated() {
            let (summary, _) = MailParser.summary(id: index, slice: slice, in: data)
            let content = MailParser.content(summary, in: data)
            _ = MailHTML.document(for: content, allowRemote: false)
        }
        let text = String(decoding: data, as: UTF8.self)
        _ = MailHTML.text(fromHTML: text)
        _ = MIME.decodeWords(String(text.prefix(400)))
        _ = MIME.decodeQuotedPrintable(data)
        _ = MIME.decodeBase64(data)
        _ = MIME.splitMultipart(data, boundary: "outer")
    }

    /// Edits biased towards the bytes the parsers care about.
    private func mutate(_ bytes: inout [UInt8], using generator: inout SplitMix64) {
        let tokens = ["\n", "\r\n", "\n\n", "--", "--outer", "--alt--", "=", "=?", "?=", "?", "<", ">", "&", "&#", ";",
                      ":", "\"", "'", "%", "*", "\\", "From ", ">From ", "\u{0}", "\u{FF}", "Content-Type: multipart/mixed; boundary=x\n"]
        guard !bytes.isEmpty else {
            bytes = Array(tokens.randomElement(using: &generator)!.utf8)
            return
        }
        let position = Int.random(in: 0..<bytes.count, using: &generator)
        switch Int.random(in: 0..<5, using: &generator) {
        case 0:
            bytes.insert(contentsOf: Array(tokens.randomElement(using: &generator)!.utf8), at: position)
        case 1:
            bytes.removeSubrange(position..<min(bytes.count, position + Int.random(in: 1...40, using: &generator)))
        case 2:
            bytes[position] = UInt8.random(in: 0...255, using: &generator)
        case 3:
            let end = min(bytes.count, position + Int.random(in: 1...80, using: &generator))
            bytes.insert(contentsOf: bytes[position..<end], at: Int.random(in: 0...bytes.count, using: &generator))
        default:
            bytes.insert(contentsOf: [0xC4, 0xE3, 0xE5, 0x8F], at: position)
        }
    }
}

/// Small seeded generator so failures reproduce.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
