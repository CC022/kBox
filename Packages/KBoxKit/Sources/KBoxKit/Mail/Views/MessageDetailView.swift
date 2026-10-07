import SwiftUI

/// The reader: header, attachments, a notice when remote content is blocked, then the body.
struct MessageDetailView: View {
    @Bindable var store: MailStore

    var body: some View {
        if let summary = store.selectedSummary {
            let content = store.selected?.summary.id == summary.id ? store.selected : nil
            VStack(spacing: 0) {
                MessageHeaderView(summary: summary)
                if let content {
                    if !content.attachments.isEmpty {
                        AttachmentStrip(attachments: content.attachments, store: store)
                    }
                    if content.hasRemoteContent && !store.allowsRemoteContent {
                        RemoteContentBanner { store.allowsRemoteContent = true }
                    }
                }
                Divider()
                if content != nil {
                    MailWebView(html: store.document, version: store.documentVersion, highlight: store.searchWords)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color.canvasBackground)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        } else {
            ContentUnavailableView("未选择邮件", systemImage: "envelope")
        }
    }
}

private struct MessageHeaderView: View {
    let summary: MailSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(address: summary.from)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    // The address gives way first, then the date; the name stays whole.
                    Text(summary.from?.displayName ?? "（无发件人）")
                        .font(.headline)
                        .lineLimit(1)
                        .layoutPriority(2)
                    if let from = summary.from, !from.name.isEmpty, !from.email.isEmpty {
                        Text(from.email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    if let date = summary.date {
                        Text(Fmt.mailFullDate(date))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }
                Text(summary.subject.isEmpty ? "（无主题）" : summary.subject)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                AddressLine(label: "收件人", addresses: summary.to)
                AddressLine(label: "抄送", addresses: summary.cc)
            }
        }
        .textSelection(.enabled)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AddressLine: View {
    let label: String
    let addresses: [MailAddress]

    var body: some View {
        if !addresses.isEmpty {
            (Text("\(label)：").foregroundStyle(.secondary) + Text(addresses.map(\.displayName).joined(separator: "、")))
                .font(.subheadline)
                .lineLimit(2)
                .help(addresses.map { $0.name.isEmpty ? $0.email : "\($0.name) <\($0.email)>" }.joined(separator: "\n"))
        }
    }
}

/// Initials on a colour picked from the address, the same colour every launch.
struct AvatarView: View {
    let address: MailAddress?
    var size: CGFloat = 40

    private static let palette: [Color] = [.blue, .indigo, .purple, .pink, .red, .orange, .teal, .green]

    var body: some View {
        Circle()
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(address?.initials ?? "?")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            }
            .accessibilityHidden(true)
    }

    private var color: Color {
        let key = (address?.email.isEmpty == false ? address?.email : address?.name) ?? ""
        let hash = key.lowercased().unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        return Self.palette[Int(hash % UInt32(Self.palette.count))]
    }
}

private struct RemoteContentBanner: View {
    let load: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.slash")
                .foregroundStyle(.secondary)
            Text("此邮件包含远程内容，已阻止载入以保护隐私。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("载入远程内容", action: load)
                .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.12))
    }
}
