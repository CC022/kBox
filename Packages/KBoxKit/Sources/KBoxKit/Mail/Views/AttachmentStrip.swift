import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// Attachments under the message header: tap for Quick Look, context menu to save.
struct AttachmentStrip: View {
    let attachments: [MailAttachment]
    let store: MailStore

    @State private var previewURL: URL?
    @State private var saving: MailAttachment?
    @State private var failure: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    Button {
                        preview(attachment)
                    } label: {
                        AttachmentChip(attachment: attachment)
                    }
                    .buttonStyle(.plain)
                    .help("\(attachment.filename) — 点按快速查看")
                    .contextMenu {
                        Button("快速查看", systemImage: "eye") { preview(attachment) }
                        Button("存储…", systemImage: "square.and.arrow.down") { saving = attachment }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .quickLookPreview($previewURL)
        .fileExporter(
            isPresented: Binding(get: { saving != nil }, set: { if !$0 { saving = nil } }),
            document: saving.map { AttachmentDocument(data: $0.data) },
            contentType: saving?.contentType ?? .data,
            defaultFilename: saving.map { MailStore.safeFilename($0.filename) }
        ) { result in
            if case .failure(let error) = result { failure = error.localizedDescription }
        }
        .alert("无法处理附件", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("好") {}
        } message: {
            Text(failure ?? "")
        }
    }

    private func preview(_ attachment: MailAttachment) {
        do {
            previewURL = try store.previewURL(for: attachment)
        } catch {
            failure = error.localizedDescription
        }
    }
}

private struct AttachmentChip: View {
    let attachment: MailAttachment

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.filename)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(attachment.size.formatted(.byteCount(style: .file)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 240, alignment: .leading)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.hairline))
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    private var symbol: String {
        let type = attachment.contentType
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return "film" }
        if type.conforms(to: .audio) { return "waveform" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .archive) { return "doc.zipper" }
        if type.conforms(to: .spreadsheet) { return "tablecells" }
        if type.conforms(to: .presentation) { return "play.rectangle" }
        if type.conforms(to: .calendarEvent) || attachment.mimeType == "text/calendar" { return "calendar" }
        if type.conforms(to: .emailMessage) || attachment.mimeType == "message/rfc822" { return "envelope" }
        if type.conforms(to: .text) { return "doc.text" }
        return "doc"
    }
}

struct AttachmentDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
