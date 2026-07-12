import SwiftUI

/// "Now & Next" scheduled-block bar, fed by Reclaim's moment endpoints.
struct NowNextBanner: View {
    let current: MomentEvent?
    let next: MomentEvent?

    var body: some View {
        if current == nil && next == nil {
            EmptyView()
        } else {
            HStack(spacing: 12) {
                if let c = current, c.isActive() {
                    chip(label: "NOW", event: c, accent: .green, showEnd: true)
                }
                if let n = next {
                    chip(label: "NEXT", event: n, accent: .blue, showEnd: false)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .padding(.vertical, 7)
        }
    }

    @ViewBuilder
    private func chip(label: String, event: MomentEvent, accent: Color, showEnd: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption2.bold()).foregroundStyle(accent)
            if let p = event.priorityEnum {
                Text(p.short).font(.caption2.bold()).foregroundStyle(p.color)
            }
            Text(event.displayTitle).font(.callout.weight(.medium)).lineLimit(1)
            Group {
                if showEnd, let end = event.eventEnd {
                    Text("ends ") + Text(end, style: .relative)
                } else if let start = event.eventStart {
                    Text(start, style: .time) + Text(" · in ") + Text(start, style: .relative)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            if let s = event.onlineMeetingUrl, let u = URL(string: s) {
                Link(destination: u) { Image(systemName: "video.fill").foregroundStyle(accent) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(accent.opacity(0.10), in: Capsule())
    }
}
