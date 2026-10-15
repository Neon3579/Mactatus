import AppKit
import SwiftUI

/// 팝오버 카드 공통 모양(제어 센터 모듈처럼 살짝 밝은 둥근 사각형).
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

/// 상태 색: 정상 초록 / 70% 이상 노랑 / 90% 이상 빨강(0~1 비율 기준).
func statusColor(_ fraction: Double) -> Color {
    switch fraction {
    case 0.9...: .red
    case 0.7...: .yellow
    default: .green
    }
}

/// 작은 선 그래프. values는 0~1(maxValue를 주면 그 값 기준으로 나눈다).
struct Sparkline: View {
    let values: [Double]
    var maxValue: Double? = nil
    var color: Color = .accentColor

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)
            ZStack {
                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: proxy.size.height))
                        points.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: points.last!.x, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(color.opacity(0.18).gradient)
                    Path { path in
                        path.move(to: points[0])
                        points.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }
            }
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let top = max(maxValue ?? 1, values.max() ?? 0, 0.000_1)
        let step = size.width / CGFloat(MetricsHistoryCapacity - 1)
        let offset = CGFloat(MetricsHistoryCapacity - values.count) * step
        return values.enumerated().map { i, value in
            CGPoint(x: offset + CGFloat(i) * step, y: size.height * (1 - CGFloat(min(value / top, 1))))
        }
    }
}

let MetricsHistoryCapacity = 60

/// 가로 막대(0~1).
struct FractionBar: View {
    let fraction: Double
    var color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(proxy.size.width * min(max(fraction, 0), 1), fraction > 0 ? 6 : 0))
            }
        }
        .frame(height: 6)
    }
}

/// 앱 아이콘 캐시(프로세스 목록용).
@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for path: String?) -> NSImage? {
        guard let path else { return nil }
        if let cached = cache[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[path] = image
        return image
    }
}

/// 메뉴바용 템플릿 그래프 이미지.
enum MenuBarSparkline {
    static func image(values: [Double], size: CGSize = CGSize(width: 34, height: 16)) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            let inset = rect.insetBy(dx: 0.5, dy: 1.5)
            NSColor.black.withAlphaComponent(0.25).setStroke()
            let frame = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            frame.lineWidth = 1
            frame.stroke()
            guard values.count > 1 else { return true }
            let recent = Array(values.suffix(30))
            let step = inset.width / CGFloat(max(recent.count - 1, 1))
            let path = NSBezierPath()
            for (i, value) in recent.enumerated() {
                let point = NSPoint(x: inset.minX + CGFloat(i) * step, y: inset.minY + inset.height * CGFloat(min(max(value, 0), 1)))
                i == 0 ? path.move(to: point) : path.line(to: point)
            }
            let fill = path.copy() as! NSBezierPath
            fill.line(to: NSPoint(x: inset.maxX, y: inset.minY))
            fill.line(to: NSPoint(x: inset.minX, y: inset.minY))
            fill.close()
            NSColor.black.withAlphaComponent(0.35).setFill()
            fill.fill()
            NSColor.black.setStroke()
            path.lineWidth = 1.2
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
