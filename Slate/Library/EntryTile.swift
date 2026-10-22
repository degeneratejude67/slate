import SwiftUI

struct EntryTile: View {
    let entry: LibraryEntry

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if entry.isNotebook {
                    CoverView(entry: entry)
                } else {
                    FolderIcon()
                }
            }
            .frame(height: 210, alignment: .bottom)

            Text(entry.name)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var subtitle: String {
        if entry.isNotebook {
            let pages = entry.itemCount == 1 ? "1 page" : "\(entry.itemCount) pages"
            return entry.modified.formatted(date: .abbreviated, time: .omitted) + " · " + pages
        }
        return entry.itemCount == 1 ? "1 item" : "\(entry.itemCount) items"
    }
}

/// First page for imported PDFs; a cloth-style cover for notebooks made from paper templates.
struct CoverView: View {
    let entry: LibraryEntry

    var body: some View {
        if let image = ThumbCache.shared.image(at: entry.url.appendingPathComponent("thumb.png")) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.black.opacity(0.08)))
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
        } else {
            let color = (entry.cover ?? .slate).color
            UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3,
                                   bottomTrailingRadius: 10, topTrailingRadius: 10)
                .fill(color.gradient)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.black.opacity(0.18)).frame(width: 11)
                }
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.92))
                        .frame(height: 40)
                        .overlay {
                            Text(entry.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.black.opacity(0.75))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 6)
                        }
                        .padding(.leading, 26)
                        .padding(.trailing, 16)
                        .padding(.top, 34)
                }
                .aspectRatio(0.76, contentMode: .fit)
                .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
        }
    }
}

struct FolderIcon: View {
    var body: some View {
        Image(systemName: "folder.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(Theme.accent.opacity(0.85).gradient)
            .frame(width: 150, height: 120)
            .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
    }
}
