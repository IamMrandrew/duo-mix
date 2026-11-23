import CoreGraphics

/// Calculate each side independently so a vertical hinge never cuts through a channel.
struct FaderBankLayout {
    let firstWidth: CGFloat?
    let gap: CGFloat?
    let firstCount: Int
    let secondCount: Int
    var count: Int { firstCount + secondCount }

    init(width: CGFloat, margin: CGFloat, hinge: CGRect?, accessible: Bool) {
        let stripWidth: CGFloat = accessible ? 72 * 1.6 : 72
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

/// On Duo the clock and camera can reserve just one end of the top safe area.
struct TabletopToolbarLayout {
    let leadingInset: CGFloat
    let trailingInset: CGFloat
    let rowTop: CGFloat
    let height: CGFloat

    init(width: CGFloat, margin: CGFloat, safeTop: CGFloat, occlusions: [CGRect], accessible: Bool) {
        let rowHeight: CGFloat = 48
        let topBand = CGRect(x: 0, y: 0, width: width, height: max(rowHeight + 8, safeTop))
        let obstruction = occlusions.filter { $0.intersects(topBand) }.reduce(CGRect.null) { $0.union($1) }
        let clearY = max(safeTop, obstruction.isNull ? 0 : obstruction.maxY)
        if !obstruction.isNull && !accessible {
            let left = obstruction.minX - margin - 4
            let right = width - margin - obstruction.maxX - 4
            // Room for connection status, bank range and both 46-point paging buttons.
            if max(left, right) >= 276 {
                leadingInset = left >= right ? 0 : max(0, obstruction.maxX + 4 - margin)
                trailingInset = left >= right ? max(0, width - margin - obstruction.minX + 4) : 0
                height = max(clearY, rowHeight + 8)
                rowTop = (height - rowHeight) / 2
                return
            }
        }
        leadingInset = 0
        trailingInset = 0
        rowTop = clearY + 4
        height = rowTop + rowHeight
    }
}
