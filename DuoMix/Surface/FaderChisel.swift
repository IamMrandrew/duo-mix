import SwiftUI

/// A cut slate grip with a straight position mark. The whole lane accepts drags.
struct FaderChisel: View {
    let level: Double
    let selected: Bool
    let isDragging: Bool
    let inset: CGFloat

    private let slate = Color(red: 0.41, green: 0.44, blue: 0.46)
    private let lightSlate = Color(red: 0.49, green: 0.52, blue: 0.54)

    static func travelInset(forHeight height: CGFloat) -> CGFloat {
        min(height / 2, 30, max(12, height * 0.17))
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let travel = max(1, size.height - inset * 2)
            let y = inset + (1 - CGFloat(min(1, max(0, level)))) * travel
            let height = max(0, inset * 2 - 2)
            let width = min(height * 0.53, size.width * 0.66)

            ZStack(alignment: .topLeading) {
                Canvas { context, bounds in
                    let x = bounds.width / 2
                    let slot = CGRect(x: x - 2, y: inset - 1.5, width: 4, height: travel + 3)
                    context.fill(Path(roundedRect: slot.offsetBy(dx: 0.5, dy: 0.6), cornerRadius: 2),
                                 with: .color(.white.opacity(0.23)))
                    context.fill(Path(roundedRect: slot, cornerRadius: 2), with: .color(Color(white: 0.047)))

                    let markEnd = x - width / 2 - 2
                    for tick in 0...4 {
                        let tickY = inset + CGFloat(tick) * travel / 4
                        let length = min(tick.isMultiple(of: 2) ? 7 : 3, max(0, markEnd - 2))
                        let mark = CGRect(x: markEnd - length, y: tickY - 0.75,
                                          width: length, height: 1.5)
                        context.fill(Path(mark), with: .color(.white.opacity(0.46)))
                    }
                }

                Canvas { context, bounds in
                    let w = bounds.width, h = bounds.height
                    let cut = min(4.5, w * 0.21)
                    let outline = polygon([(cut, 0), (w - cut, 0), (w, cut),
                                           (w, h - cut), (w - cut, h), (cut, h),
                                           (0, h - cut), (0, cut)])
                    context.fill(outline, with: .color(isDragging ? lightSlate : slate))
                    let cutFace = polygon([(0, h * 0.42), (w, h * 0.28),
                                           (w, h - cut), (w - cut, h), (cut, h), (0, h - cut)])
                    context.fill(cutFace, with: .color(Color(white: isDragging ? 0.54 : 0.46)))
                    let leftEdge = polygon([(0, cut), (cut, 0), (w - cut, 0),
                                            (w - cut - 0.4, 1), (cut + 0.4, 1),
                                            (1, cut + 0.4), (1, h - cut), (0, h - cut)])
                    context.fill(leftEdge, with: .color(.white.opacity(0.38)))
                    context.fill(Path(CGRect(x: 2, y: h / 2 - 1, width: max(0, w - 4), height: 2)),
                                 with: .color(selected ? Desk.accent : Color(white: 0.90)))
                }
                .frame(width: width, height: height)
                .position(x: size.width / 2, y: y)
            }
        }
    }

    private func polygon(_ vertices: [(CGFloat, CGFloat)]) -> Path {
        Path { path in
            path.addLines(vertices.map { CGPoint(x: $0.0, y: $0.1) })
            path.closeSubpath()
        }
    }
}
