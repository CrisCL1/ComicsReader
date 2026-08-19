import SwiftUI

/// Fila de la biblioteca: portada, título, progreso, etiquetas y estrella.
struct DocumentCard: View {

    let item: LibraryItem
    var onOpen: () -> Void
    var onToggleFavorite: () -> Void

    @EnvironmentObject private var drive: DriveSync
    @State private var thumbnail: UIImage?

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 14) {
                cover

                VStack(alignment: .leading, spacing: 7) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(Theme.textFaint)

                    if !item.tags.isEmpty {
                        TagStrip(tags: item.tags)
                    }

                    Spacer(minLength: 2)

                    HStack(spacing: 8) {
                        ProgressBar(value: item.progress, tint: item.isFinished ? Theme.accentAlt : Theme.accent)
                        Text("\(item.progressPercent)%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.textMuted)
                            .frame(width: 34, alignment: .trailing)
                    }
                }

                VStack(spacing: 10) {
                    Button(action: onToggleFavorite) {
                        Image(systemName: item.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 15))
                            .foregroundStyle(item.isFavorite ? Theme.star : Theme.textFaint)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)

                    if drive.isBusy(item) {
                        ProgressView().controlSize(.mini).tint(Theme.textMuted)
                    } else if !item.isLocalAvailable {
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.accentAlt)
                    } else if item.driveFileID != nil {
                        Image(systemName: "checkmark.icloud")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textFaint)
                    }
                }
            }
            .padding(12)
            .frame(height: 132)
            .card()
        }
        .buttonStyle(.plain)
        .task(id: item.id) { thumbnail = FileStore.loadThumbnail(for: item) }
    }

    private var cover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.surfaceHigh)

            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .frame(width: 76, height: 108)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
        .opacity(item.isLocalAvailable ? 1 : 0.5)
    }

    private var subtitle: String {
        var parts: [String] = []
        if item.pageCount > 0 {
            parts.append("p. \(item.lastPage + 1) de \(item.pageCount)")
        }
        parts.append(item.isLocalAvailable ? item.readableSize : "En Drive")
        return parts.joined(separator: "  ·  ")
    }
}

/// Chips de etiquetas en una línea.
struct TagStrip: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(tags.prefix(3), id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.surfaceHigh)
                    .clipShape(Capsule())
            }
            if tags.count > 3 {
                Text("+\(tags.count - 3)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textFaint)
            }
        }
    }
}
