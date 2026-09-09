import AppKit

/// One checked layout for both Illustrator and PDF exports. Geometry is in mm.
struct ExportLayout {
    struct Slot {
        let path: String
        let geometry: CGPath
        let bounds: CGRect
    }
    let bodyX: Double, bodyY: Double
    let baseX: Double, baseY: Double
    let pageWidth: Double, pageHeight: Double
    let bodyBounds: CGRect
    let basePath: String
    let baseGeometry: CGPath
    let slots: [Slot]

    static func make(result: GeometryResult, settings: StandeeSettings) throws -> ExportLayout {
        let g = result.model
        let baseWidth = settings.baseWidth, baseHeight = settings.baseHeight
        let slotWidth = settings.tabWidth + settings.fit, slotHeight = settings.thickness + settings.fit
        let dimensions = [baseWidth, baseHeight, slotWidth, slotHeight]
        guard dimensions.allSatisfy({ $0.isFinite && $0 > 0 }),
              ["circle", "rectangle", "square"].contains(settings.baseShape) else {
            throw AppFailure("底座或插槽尺寸无效，请检查参数。")
        }
        let cutBounds = try SVGPath.parse(g.bodyPath).boundingBoxOfPath
        guard g.tabs.allSatisfy({ [$0.x,$0.y,$0.width,$0.height].allSatisfy { $0.isFinite } && $0.width > 0 && $0.height > 0 }) else {
            throw AppFailure("插脚参考框尺寸无效。")
        }
        let bounds = g.tabs.reduce(cutBounds) { $0.union($1.cgRect) }
        guard !bounds.isNull, !bounds.isEmpty,
              [bounds.minX, bounds.minY, bounds.maxX, bounds.maxY].allSatisfy({ $0.isFinite }) else {
            throw AppFailure("最终刀线边界无效，无法排版。")
        }
        let basePath = settings.baseShape == "circle" ? ellipse(baseWidth, baseHeight) : roundedRect(0, 0, baseWidth, baseHeight, 3)
        let baseGeometry = try SVGPath.parse(basePath)
        let centers = g.tabs.map { $0.effectiveCenterX }
        guard centers.allSatisfy({ $0.isFinite }) else { throw AppFailure("插脚中心坐标无效。") }
        let mean = centers.reduce(0, +) / Double(max(1, centers.count))
        let slots: [Slot] = try centers.enumerated().map { index, center in
            let x = baseWidth / 2 + center - mean - slotWidth / 2
            let y = (baseHeight - slotHeight) / 2
            let path = roundedRect(x, y, slotWidth, slotHeight, min(0.4, slotHeight / 4))
            let geometry = try SVGPath.parse(path)
            // The current bases are convex. If this whole bounding rectangle is
            // inside the actual base path, the rounded slot is also inside it.
            // A 0.001 mm numerical margin rejects touching/open boundary cuts;
            // this is not a factory-specific structural wall-thickness rule.
            let envelope = geometry.boundingBoxOfPath.insetBy(dx: -0.001, dy: -0.001)
            let corners = [CGPoint(x: envelope.minX, y: envelope.minY), CGPoint(x: envelope.maxX, y: envelope.minY),
                           CGPoint(x: envelope.maxX, y: envelope.maxY), CGPoint(x: envelope.minX, y: envelope.maxY)]
            guard corners.allSatisfy({ baseGeometry.contains($0, using: .evenOdd, transform: .identity) }) else {
                throw AppFailure("第 \(index + 1) 个插槽超出或接触底座边缘。请加大底座、缩小插脚宽度，或改用单插脚；当前尺寸不会导出。")
            }
            return Slot(path: path, geometry: geometry, bounds: geometry.boundingBoxOfPath)
        }
        for i in slots.indices {
            for j in slots.indices where j < i {
                let a = slots[i].bounds, b = slots[j].bounds
                if a.maxX >= b.minX && b.maxX >= a.minX && a.maxY >= b.minY && b.maxY >= a.minY {
                    throw AppFailure("两个插槽相交或接触，无法作为独立插槽加工。请缩小插脚宽度或改用单插脚；当前尺寸不会导出。")
                }
            }
        }
        let margin = 10.0, gap = 20.0
        let bodyX = margin - Double(bounds.minX), bodyY = margin - Double(bounds.minY)
        let baseX = margin + Double(bounds.width) + gap
        let baseY = margin + max(0, (Double(bounds.height) - baseHeight) / 2)
        return ExportLayout(bodyX: bodyX, bodyY: bodyY, baseX: baseX, baseY: baseY,
            pageWidth: baseX + baseWidth + margin, pageHeight: max(Double(bounds.height), baseHeight) + margin * 2,
            bodyBounds: bounds, basePath: basePath, baseGeometry: baseGeometry, slots: slots)
    }

    static func roundedRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ radius: Double) -> String {
        let r = max(0, min(radius, min(w, h) / 2))
        return "M \(x+r) \(y) H \(x+w-r) Q \(x+w) \(y) \(x+w) \(y+r) V \(y+h-r) Q \(x+w) \(y+h) \(x+w-r) \(y+h) H \(x+r) Q \(x) \(y+h) \(x) \(y+h-r) V \(y+r) Q \(x) \(y) \(x+r) \(y) Z"
    }
    static func ellipse(_ w: Double, _ h: Double) -> String {
        let x = w / 2, y = h / 2, k = 0.5522847498307936
        return "M \(w) \(y) C \(w) \(y+y*k) \(x+x*k) \(h) \(x) \(h) C \(x-x*k) \(h) 0 \(y+y*k) 0 \(y) C 0 \(y-y*k) \(x-x*k) 0 \(x) 0 C \(x+x*k) 0 \(w) \(y-y*k) \(w) \(y) Z"
    }
}
