import SwiftUI

struct MarkdownBodyView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                lineView(line)
            }
        }
    }

    private var lines: [String] {
        text.split(whereSeparator: \.isNewline).map(String.init)
    }

    @ViewBuilder
    private func lineView(_ raw: String) -> some View {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let rest = bulletContent(trimmed) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•").foregroundColor(.secondary)
                Text(attributed(rest))
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(attributed(trimmed))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bulletContent(_ s: String) -> String? {
        for prefix in ["- ", "* ", "+ "] where s.hasPrefix(prefix) {
            return String(s.dropFirst(prefix.count))
        }
        return nil
    }

    private func attributed(_ s: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
    }
}

struct PopoverView: View {
    let state: LoadState
    let onRefresh: () -> Void
    let onStopSpeaking: () -> Void
    let onOpenURL: (URL) -> Void
    let isSpeaking: Bool

    enum LoadState {
        case loading
        case entry(DigestEntry)
        case error(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Divider()

            Group {
                switch state {
                case .loading:
                    HStack { ProgressView(); Text("Fetching latest digest…") }
                case .entry(let entry):
                    entryView(entry)
                case .error(let msg):
                    Text(msg)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 400, height: 320)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Steady Digest")
                .font(.headline)
            Spacer()
            Button(action: onStopSpeaking) {
                Image(systemName: isSpeaking ? "stop.circle.fill" : "stop.circle")
            }
            .buttonStyle(.borderless)
            .disabled(!isSpeaking)
            .help(isSpeaking ? "Stop speaking" : "Not speaking")
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
    }

    @ViewBuilder
    private func entryView(_ entry: DigestEntry) -> some View {
        let resource = entry.resource
        VStack(alignment: .leading, spacing: 6) {
            if let title = resource?.title, !title.isEmpty {
                Text(title).font(.title3).bold()
            } else if let goal = resource?.goal?.title {
                Text(goal).font(.title3).bold()
            } else {
                Text("Digest entry").font(.title3).bold()
            }

            HStack(spacing: 8) {
                if let person = resource?.person?.name {
                    Label(person, systemImage: "person")
                }
                if let published = entry.publishedAt {
                    Label(published.formatted(date: .abbreviated, time: .shortened),
                          systemImage: "clock")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)

            if let progress = resource?.progress {
                HStack {
                    ProgressView(value: Double(progress), total: 100)
                    Text("\(progress)%").font(.caption).foregroundColor(.secondary)
                }
            }

            if let conf = resource?.confidenceDescription {
                Text("Confidence: \(conf)").font(.caption).foregroundColor(.secondary)
            }

            if let body = resource?.body, !body.isEmpty {
                ScrollView {
                    MarkdownBodyView(text: body)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let urlString = resource?.url, let url = URL(string: urlString) {
                Button("Open in Steady") { onOpenURL(url) }
                    .buttonStyle(.link)
            }
        }
    }
}
