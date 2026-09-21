import Foundation

/// A JSON file under ~/Library/Application Support/kBox/, written atomically.
public struct JSONFileStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func appSupport(_ filename: String) -> JSONFileStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return JSONFileStore(url: base.appending(path: "kBox", directoryHint: .isDirectory).appending(path: filename))
    }

    public func load<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    public func save<T: Encodable>(_ value: T) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
