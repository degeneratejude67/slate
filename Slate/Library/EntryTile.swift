import SwiftUI

struct EntryTile: View {
    let entry: LibraryEntry
    var coverHeight: CGFloat = 210

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if entry.isNotebook {
                    CoverView(entry: entry)
                } else {
                    FolderIcon()
                }
            }
            .frame(height: coverHeight, alignment: .bottom)

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
            NotebookCover(style: entry.cover ?? .slate, title: entry.name)
        }
    }
}

struct NotebookCover: View {
    let style: CoverStyle
    var title: String? = nil

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3,
                                           bottomTrailingRadius: 10, topTrailingRadius: 10)
        shape
            .fill(style.color.gradient)
            .overlay { CoverPatternView(style: style).clipShape(shape) }
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.black.opacity(0.16)).frame(width: 11)
            }
            .overlay(alignment: .top) {
                if let title {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.92))
                        .frame(height: 40)
                        .overlay {
                            Text(title)
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
            }
            .aspectRatio(0.76, contentMode: .fit)
            .shadow(color: .black.opacity(0.22), radius: 5, y: 2)
    }
}

struct CoverPatternView: View {
    let style: CoverStyle

    var body: some View {
        Canvas { ctx, size in
            let ink = style.isLight ? Color.black : Color.white
            switch style.pattern {
            case .none:
                break
            case .linen:
                var y: CGFloat = 0
                while y < size.height {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.6)), with: .color(ink.opacity(0.06)))
                    y += 2.4
                }
                var x: CGFloat = 0
                while x < size.width {
                    ctx.fill(Path(CGRect(x: x, y: 0, width: 0.6, height: size.height)), with: .color(ink.opacity(0.05)))
                    x += 2.4
                }
            case .kraft:
                var seed: UInt64 = 7
                for _ in 0..<260 {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let x = CGFloat(seed % 1000) / 1000 * size.width
                    let y = CGFloat((seed >> 20) % 1000) / 1000 * size.height
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)), with: .color(.black.opacity(0.12)))
                }
            case .grid:
                var x: CGFloat = 0
                while x < size.width {
                    ctx.stroke(Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) },
                               with: .color(.white.opacity(0.16)), lineWidth: 0.6)
                    x += 12
                }
                var y: CGFloat = 0
                while y < size.height {
                    ctx.stroke(Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) },
                               with: .color(.white.opacity(0.16)), lineWidth: 0.6)
                    y += 12
                }
            case .dots:
                var row = 0
                var y: CGFloat = 8
                while y < size.height {
                    var x: CGFloat = row % 2 == 0 ? 8 : 18
                    while x < size.width {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)),
                                 with: .color(.white.opacity(0.7)))
                        x += 20
                    }
                    y += 14; row += 1
                }
            case .stripes:
                var x: CGFloat = -size.height
                while x < size.width {
                    ctx.stroke(Path { p in
                        p.move(to: CGPoint(x: x, y: size.height))
                        p.addLine(to: CGPoint(x: x + size.height, y: 0))
                    }, with: .color(.white.opacity(0.13)), lineWidth: 6)
                    x += 18
                }
            case .terrazzo:
                let colors: [Color] = [.orange, .teal, .pink, .gray, .yellow]
                var seed: UInt64 = 11
                for i in 0..<70 {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let x = CGFloat(seed % 1000) / 1000 * size.width
                    let y = CGFloat((seed >> 21) % 1000) / 1000 * size.height
                    let r = CGFloat(2 + (seed >> 40) % 5)
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 1.4, height: r)),
                             with: .color(colors[i % colors.count].opacity(0.55)))
                }
            }
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
