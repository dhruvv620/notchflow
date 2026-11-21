// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 dhruvv620

import SwiftUI

/// Arranging a board: drag a panel anywhere (it snaps to the grid, swaps
/// with a panel it's dropped on, or slides to the nearest clear spot), drag
/// an edge or corner to resize, × to take it off. Used on the board itself
/// (Edit) and in Settings.
struct GlanceArranger<Tile: View>: View {
    let board: GlanceBoard
    var gap: CGFloat = 12
    var cornerRadius: CGFloat = 16
    @Binding var selected: UUID?
    /// Applies a change to the board being arranged.
    let change: ((GlanceBoard) -> GlanceBoard) -> Void
    let tile: (GlancePanel) -> Tile

    private enum Handle { case move, right, bottom, corner, left, top }

    @State private var active: UUID?
    @State private var handle: Handle = .move
    @State private var delta: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let area = CGRect(origin: .zero, size: geometry.size)
            let cell = CGSize(width: area.width / CGFloat(GlancePolicy.columns), height: area.height / CGFloat(GlancePolicy.rows))
            ZStack(alignment: .topLeading) {
                grid(area: area, cell: cell)
                if let active, let panel = board.panels.first(where: { $0.id == active }) {
                    // Where it will land.
                    let target = GlanceLayout.rect(for: snapped(panel.frame, cell: cell), in: area, gap: gap)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .frame(width: target.width, height: target.height)
                        .offset(x: target.minX, y: target.minY)
                }
                ForEach(board.panels.filter(\.isShown)) { panel in
                    let base = GlanceLayout.rect(for: panel.frame, in: area, gap: gap)
                    let rect = live(base, for: panel.id, cell: cell)
                    tile(panel)
                        .frame(width: rect.width, height: rect.height)
                        .overlay { chrome(panel, cell: cell) }
                        .offset(x: rect.minX, y: rect.minY)
                        .zIndex(active == panel.id ? 2 : (selected == panel.id ? 1 : 0))
                        .onTapGesture { selected = panel.id }
                        .gesture(drag(panel, handle: .move, cell: cell))
                }
            }
        }
    }

    // MARK: Pieces

    private func grid(area: CGRect, cell: CGSize) -> some View {
        Canvas { context, size in
            for column in 0...GlancePolicy.columns where column % GlancePolicy.unit == 0 {
                for row in 0...GlancePolicy.rows where row % GlancePolicy.unit == 0 {
                    let point = CGPoint(x: CGFloat(column) * cell.width, y: CGFloat(row) * cell.height)
                    context.fill(Path(ellipseIn: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)),
                                 with: .color(.white.opacity(0.35)))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func chrome(_ panel: GlancePanel, cell: CGSize) -> some View {
        let isSelected = selected == panel.id || active == panel.id
        return ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : Color.white.opacity(0.35), lineWidth: isSelected ? 2.5 : 1.5)
                .allowsHitTesting(false)
            // Edges and corner for resizing.
            VStack { Spacer(); edge(panel, .bottom, width: nil, height: 10, cell: cell) }
            HStack { Spacer(); edge(panel, .right, width: 10, height: nil, cell: cell) }
            VStack { edge(panel, .top, width: nil, height: 10, cell: cell); Spacer() }
            HStack { edge(panel, .left, width: 10, height: nil, cell: cell); Spacer() }
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.accentColor, in: Circle())
                        .padding(4)
                        .contentShape(Rectangle())
                        .highPriorityGesture(drag(panel, handle: .corner, cell: cell))
                        .help("Drag to resize")
                }
            }
            VStack {
                HStack {
                    Button {
                        if selected == panel.id { selected = nil }
                        change { board in
                            panel.kind.isBuiltIn ? GlancePolicy.setting(panel.id, shown: false, on: board)
                                : GlancePolicy.removing(panel.id, from: board)
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Color.black.opacity(0.7), in: Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .help("Take off the board")
                    Spacer()
                }
                Spacer()
            }
        }
    }

    private func edge(_ panel: GlancePanel, _ which: Handle, width: CGFloat?, height: CGFloat?, cell: CGSize) -> some View {
        Color.clear
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, maxHeight: height == nil ? .infinity : nil)
            .contentShape(Rectangle())
            .highPriorityGesture(drag(panel, handle: which, cell: cell))
            .onHover { inside in
                guard inside else { NSCursor.pop(); return }
                (which == .left || which == .right ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
            }
    }

    // MARK: Dragging

    private func drag(_ panel: GlancePanel, handle grabbed: Handle, cell: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                active = panel.id
                handle = grabbed
                delta = value.translation
                selected = panel.id
            }
            .onEnded { _ in
                commit(panel, cell: cell)
                active = nil
                delta = .zero
                handle = .move
            }
    }

    /// The panel's frame as it would be with the current drag, in cells.
    private func snapped(_ frame: GlanceRect, cell: CGSize) -> GlanceRect {
        guard cell.width > 0, cell.height > 0 else { return frame }
        let dx = Int((delta.width / cell.width).rounded())
        let dy = Int((delta.height / cell.height).rounded())
        var rect = frame
        switch handle {
        case .move: rect.x += dx; rect.y += dy
        case .right: rect.width += dx
        case .bottom: rect.height += dy
        case .corner: rect.width += dx; rect.height += dy
        case .left: rect.x += dx; rect.width -= dx
        case .top: rect.y += dy; rect.height -= dy
        }
        rect.width = max(1, rect.width)
        rect.height = max(1, rect.height)
        return GlancePolicy.clamped(rect)
    }

    private func commit(_ panel: GlancePanel, cell: CGSize) {
        let target = snapped(panel.frame, cell: cell)
        guard target != panel.frame else { return }
        change { board in
            switch handle {
            case .move: return GlancePolicy.moving(panel.id, toX: target.x, y: target.y, on: board)
            case .right, .bottom, .corner: return GlancePolicy.resizing(panel.id, width: target.width, height: target.height, on: board)
            case .left, .top: return GlancePolicy.reframing(panel.id, to: target, on: board)
            }
        }
    }

    /// The panel's rect while it's being dragged or resized (follows the pointer).
    private func live(_ base: CGRect, for id: UUID, cell: CGSize) -> CGRect {
        guard active == id else { return base }
        var rect = base
        switch handle {
        case .move: rect = rect.offsetBy(dx: delta.width, dy: delta.height)
        case .right: rect.size.width = max(cell.width, rect.width + delta.width)
        case .bottom: rect.size.height = max(cell.height, rect.height + delta.height)
        case .corner:
            rect.size.width = max(cell.width, rect.width + delta.width)
            rect.size.height = max(cell.height, rect.height + delta.height)
        case .left:
            let dx = min(delta.width, rect.width - cell.width)
            rect.origin.x += dx
            rect.size.width -= dx
        case .top:
            let dy = min(delta.height, rect.height - cell.height)
            rect.origin.y += dy
            rect.size.height -= dy
        }
        return rect
    }
}
