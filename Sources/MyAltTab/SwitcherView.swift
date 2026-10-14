import SwiftUI

/// Grid geometry for the switcher. Tiles are scaled down so the whole grid fits on screen.
struct SwitcherLayout {
    static let padding: CGFloat = 16
    static let rowSpacing: CGFloat = 4
    static let footerHeight: CGFloat = 30 // selected-window caption + spacing
    private static let minScale: CGFloat = 0.35

    let showPreviews: Bool
    var columns = 1
    var rows = 1
    var scale: CGFloat = 1

    // Unscaled tile metrics for each mode.
    var baseTileSize: CGSize { showPreviews ? CGSize(width: 240, height: 176) : CGSize(width: 128, height: 114) }

    var tileSize: CGSize { CGSize(width: baseTileSize.width * scale, height: baseTileSize.height * scale) }
    var previewSize: CGSize { CGSize(width: 212 * scale, height: 132 * scale) }
    var iconSize: CGFloat { (showPreviews ? 80 : 64) * scale }
    var badgeSize: CGFloat { 36 * scale }
    var fontSize: CGFloat { max(9, (showPreviews ? 12 : 11) * scale) }

    var gridWidth: CGFloat { CGFloat(columns) * tileSize.width }
    var panelSize: CGSize {
        CGSize(width: gridWidth + 2 * Self.padding,
               height: CGFloat(rows) * tileSize.height + CGFloat(rows - 1) * Self.rowSpacing
                   + Self.footerHeight + 2 * Self.padding)
    }

    /// Picks the column count that allows the largest tiles within ~90% of the screen.
    static func fitting(count: Int, in screen: CGSize, showPreviews: Bool) -> SwitcherLayout {
        let count = max(1, count)
        let availableWidth = screen.width * 0.92 - 2 * padding
        let availableHeight = screen.height * 0.88 - 2 * padding - footerHeight
        var best = SwitcherLayout(showPreviews: showPreviews, columns: count, rows: 1, scale: 0)

        for columns in 1...count {
            let rows = (count + columns - 1) / columns
            var candidate = SwitcherLayout(showPreviews: showPreviews, columns: columns, rows: rows)
            let base = candidate.baseTileSize
            let tilesHeight = availableHeight - CGFloat(rows - 1) * rowSpacing
            candidate.scale = min(1, availableWidth / (CGFloat(columns) * base.width), tilesHeight / (CGFloat(rows) * base.height))
            // On ties prefer more columns (fewer rows), like Windows' single-row switcher.
            if candidate.scale >= best.scale { best = candidate }
        }
        best.scale = max(minScale, best.scale)
        return best
    }
}

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel
    let onClick: (Int) -> Void

    private var layout: SwitcherLayout { model.layout }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: SwitcherLayout.rowSpacing) {
                ForEach(rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(row, id: \.self) { index in
                            tile(index)
                        }
                    }
                    .frame(width: layout.gridWidth, alignment: .leading)
                }
            }
            if model.windows.indices.contains(model.selected) {
                let window = model.windows[model.selected]
                Text(window.title == window.appName ? window.appName : "\(window.appName) — \(window.title)")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: layout.gridWidth, height: SwitcherLayout.footerHeight, alignment: .bottom)
            }
        }
        .padding(SwitcherLayout.padding)
        .frame(width: layout.panelSize.width, height: layout.panelSize.height, alignment: .top)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.15)))
    }

    private var rows: [[Int]] {
        let columns = max(1, layout.columns)
        return stride(from: 0, to: model.windows.count, by: columns).map {
            Array($0..<min($0 + columns, model.windows.count))
        }
    }

    private func tile(_ index: Int) -> some View {
        let window = model.windows[index]
        let isSelected = index == model.selected
        let scale = layout.scale
        return Group {
            if layout.showPreviews {
                VStack(spacing: 8 * scale) {
                    preview(for: window)
                        .frame(width: layout.previewSize.width, height: layout.previewSize.height)
                        .opacity(window.isMinimized ? 0.6 : 1)
                    title(for: window, lines: 1)
                        .frame(width: layout.previewSize.width, height: 16 * scale)
                }
            } else {
                VStack(spacing: 6 * scale) {
                    Image(nsImage: window.icon)
                        .resizable()
                        .frame(width: layout.iconSize, height: layout.iconSize)
                        .opacity(window.isMinimized ? 0.6 : 1)
                    title(for: window, lines: 2)
                        .frame(width: layout.tileSize.width - 24 * scale, height: 28 * scale, alignment: .top)
                }
            }
        }
        .frame(width: layout.tileSize.width - 8 * scale, height: layout.tileSize.height)
        .background(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.4) : .clear))
        .frame(width: layout.tileSize.width)
        .contentShape(Rectangle())
        .onTapGesture { onClick(index) }
    }

    private func title(for window: WindowInfo, lines: Int) -> some View {
        HStack(spacing: 4) {
            if window.isMinimized {
                Image(systemName: "minus.circle").foregroundStyle(.secondary)
            }
            Text(window.title)
                .lineLimit(lines)
                .multilineTextAlignment(.center)
                .truncationMode(.tail)
        }
        .font(.system(size: layout.fontSize))
    }

    @ViewBuilder
    private func preview(for window: WindowInfo) -> some View {
        if let image = model.previews[window.windowID] {
            // Thumbnail with the app icon pinned to its top-right corner.
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6 * layout.scale, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                .overlay(alignment: .topTrailing) {
                    Image(nsImage: window.icon)
                        .resizable()
                        .frame(width: layout.badgeSize, height: layout.badgeSize)
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .offset(x: layout.badgeSize * 0.28, y: -layout.badgeSize * 0.28)
                }
        } else {
            Image(nsImage: window.icon)
                .resizable()
                .frame(width: layout.iconSize, height: layout.iconSize)
        }
    }
}
