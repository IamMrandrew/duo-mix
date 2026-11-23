import CoreGraphics

/// Calculate each side independently so a vertical hinge never cuts through a channel.
struct FaderBankLayout {
    static let stripWidths: [CGFloat] = [48, 60, 72, 92]
    static let defaultZoom = 2
    let firstWidth: CGFloat?
    let gap: CGFloat?
    let firstCount: Int
    let secondCount: Int
    var count: Int { firstCount + secondCount }

    init(width: CGFloat, margin: CGFloat, hinge: CGRect?, zoom: Int, accessible: Bool) {
        let index = min(max(0, zoom), Self.stripWidths.count - 1)
        let stripWidth = Self.stripWidths[index] * (accessible ? 1.6 : 1)
        let available = max(0, width - 2 * margin)
        func slots(_ span: CGFloat) -> Int { max(0, min(32, Int((span + 1) / (stripWidth + 1)))) }

        if let hinge {
            let leading = max(0, min(available, hinge.minX - margin - 2))
            let trailing = max(0, min(available - leading, width - margin - hinge.maxX - 2))
            firstWidth = leading
            gap = available - leading - trailing
            let left = slots(leading), right = slots(trailing)
            firstCount = left + (left + right == 0 && leading >= trailing ? 1 : 0)
            secondCount = min(32 - firstCount, right + (left + right == 0 && trailing > leading ? 1 : 0))
        } else {
            firstWidth = nil
            gap = nil
            firstCount = max(1, slots(available))
            secondCount = 0
        }
    }
}
