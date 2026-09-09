import AppKit
import CoreGraphics

/// Geometry coordinates are millimetres, with positive y pointing downwards.
struct StandeeGeometry: Decodable {
    struct Rect: Decodable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    }
    struct Tab: Decodable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        let radius: Double?
        let centerX: Double?
        let depth: Double?
        let bridgeHeight: Double?
        var effectiveCenterX: Double { centerX ?? x + width / 2 }
        var cgRect: CGRect { CGRect(x:x,y:y,width:width,height:height) }
        var referencePath: String { "M \(x) \(y) H \(x+width) V \(y+height) H \(x) Z" }
    }
    struct BridgeRegion: Decodable {
        let bounds: Rect
        let enabled: Bool?
        let index: Int?
        let mouthWidthMm: Double?
        let previousDepthMm: Double?
        let retainedDepthMm: Double?
        let minimumBridgeRadiusMm: Double?
        let tangentContinuous: Bool?
        let noBacktracking: Bool?
        let curveSamples: [[Double]]?
    }
    struct BridgeDiagnostics: Decodable {
        struct Unhandled: Decodable {
            let reason: String?
            let mouthWidthMm: Double?
            let depthMm: Double?
            let bounds: Rect
        }
        let detected: Int?
        let bridged: Int?
        let unhandled: [Unhandled]?
    }
    let bodyPath: String
    let bodyOnlyPath: String
    let baselinePath: String
    let bridgePath: String
    let whitePath: String
    let silhouettePath: String
    let imageBox: Rect
    let bounds: Rect
    let tabs: [Tab]
    let widthMm: Double
    let heightMm: Double
    let totalHeightMm: Double
    let totalWidthMm: Double?
    let bridgeRegions: [BridgeRegion]?
    let bridgeDiagnostics: BridgeDiagnostics?
    let warnings: [String]
    let geometryResolutionMm: Double
    let cutComponents: Int?
    let whiteContours: Int?
    var sortedBridgeRegions: [BridgeRegion] {
        (bridgeRegions ?? []).sorted {
            if $0.bounds.y == $1.bounds.y { return $0.bounds.x < $1.bounds.x }
            return $0.bounds.y < $1.bounds.y
        }
    }
}

struct BasePreview {
    var widthMm: Double = 65
    var heightMm: Double = 65
    /// "circle", "rectangle" (or "rect"), or "square".
    var shape: String = "circle"
    var slotWidthMm: Double = 18.2
    var slotHeightMm: Double = 3.2
    var slotRadiusMm: Double = 0.5
    var thicknessMm: Double = 3
}

/// Small strict SVG path reader. Only the commands produced by our geometry
/// engine are accepted. Unsupported syntax fails instead of silently losing cuts.
enum SVGPath {
    enum ParseError: Error, LocalizedError {
        case invalidCharacter(String, Int)
        case missingCommand(Int)
        case unsupportedCommand(String)
        case missingParameters(String, Int)
        case invalidNumber(Int)
        case pathMustStartWithMove
        var errorDescription: String? {
            switch self {
            case .invalidCharacter(let c, let i): return "刀线路径第 \(i + 1) 字符无效：\(c)"
            case .missingCommand(let i): return "刀线路径第 \(i + 1) 项缺少命令。"
            case .unsupportedCommand(let c): return "刀线路径暂不支持命令 \(c)。"
            case .missingParameters(let c, let i): return "刀线路径命令 \(c) 在第 \(i + 1) 项缺少坐标。"
            case .invalidNumber(let i): return "刀线路径第 \(i + 1) 字符不是有效坐标。"
            case .pathMustStartWithMove: return "刀线路径必须从 M 命令开始。"
            }
        }
    }
    private enum Token { case command(Character), number(Double) }

    static func parse(_ source: String) throws -> CGPath {
        let bytes = Array(source.utf8)
        var index = 0
        var tokens: [Token] = []
        func isDigit(_ b: UInt8) -> Bool { b >= 48 && b <= 57 }
        while index < bytes.count {
            let b = bytes[index]
            if b == 32 || b == 9 || b == 10 || b == 13 || b == 44 { index += 1; continue }
            if (b >= 65 && b <= 90) || (b >= 97 && b <= 122) {
                tokens.append(.command(Character(UnicodeScalar(Int(b))!)))
                index += 1
                continue
            }
            let start = index
            if b == 43 || b == 45 { index += 1 }
            var digits = 0
            while index < bytes.count && isDigit(bytes[index]) { index += 1; digits += 1 }
            if index < bytes.count && bytes[index] == 46 {
                index += 1
                while index < bytes.count && isDigit(bytes[index]) { index += 1; digits += 1 }
            }
            guard digits > 0 else {
                throw ParseError.invalidCharacter(String(decoding: bytes[start...start], as: UTF8.self), start)
            }
            if index < bytes.count && (bytes[index] == 69 || bytes[index] == 101) {
                index += 1
                if index < bytes.count && (bytes[index] == 43 || bytes[index] == 45) { index += 1 }
                let exponentStart = index
                while index < bytes.count && isDigit(bytes[index]) { index += 1 }
                guard index > exponentStart else { throw ParseError.invalidNumber(start) }
            }
            guard let number = Double(String(decoding: bytes[start..<index], as: UTF8.self)), number.isFinite else {
                throw ParseError.invalidNumber(start)
            }
            tokens.append(.number(number))
        }
        let path = CGMutablePath()
        var cursor = 0
        var command: Character?
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var began = false
        while cursor < tokens.count {
            if case .command(let c) = tokens[cursor] { command = c; cursor += 1 }
            guard let c = command else { throw ParseError.missingCommand(cursor) }
            guard "MLHVQCZ".contains(c) else { throw ParseError.unsupportedCommand(String(c)) }
            if !began && c != "M" { throw ParseError.pathMustStartWithMove }
            if c == "Z" {
                path.closeSubpath()
                current = subpathStart
                command = nil
                continue
            }
            let count: Int
            switch c { case "M", "L": count = 2; case "H", "V": count = 1; case "Q": count = 4; default: count = 6 }
            guard cursor + count <= tokens.count else { throw ParseError.missingParameters(String(c), cursor) }
            var values: [CGFloat] = []
            for offset in 0..<count {
                guard case .number(let n) = tokens[cursor + offset] else { throw ParseError.missingParameters(String(c), cursor + offset) }
                values.append(CGFloat(n))
            }
            cursor += count
            switch c {
            case "M":
                current = CGPoint(x: values[0], y: values[1]); subpathStart = current
                path.move(to: current); began = true; command = "L"
            case "L":
                current = CGPoint(x: values[0], y: values[1]); path.addLine(to: current)
            case "H": current.x = values[0]; path.addLine(to: current)
            case "V": current.y = values[0]; path.addLine(to: current)
            case "Q":
                current = CGPoint(x: values[2], y: values[3])
                path.addQuadCurve(to: current, control: CGPoint(x: values[0], y: values[1]))
            case "C":
                current = CGPoint(x: values[4], y: values[5])
                path.addCurve(to: current, control1: CGPoint(x: values[0], y: values[1]), control2: CGPoint(x: values[2], y: values[3]))
            default: break
            }
        }
        return path.copy()!
    }
}

/// Native AppKit canvas; no browser or network surface is used.
final class StandeeCanvas: NSView {
    var geometry: StandeeGeometry? { didSet { refreshPaths(); needsDisplay = true } }
    var whiteImage:CGImage? { didSet { needsDisplay=true } }
    var brushEnabled=false {didSet{if !brushEnabled{draftPoints=[]};window?.invalidateCursorRects(for:self);needsDisplay=true}}
    var brushDiameter=2.0 {didSet{needsDisplay=true}}
    var pendingWhiteStrokes:[WhiteBrushStroke]=[] {didSet{needsDisplay=true}}
    var whiteStrokeCommitted:((WhiteBrushStroke)->Void)?
    private var draftPoints:[WhiteBrushPoint]=[],draftRadius=0.0,cursorPoint:CGPoint?
    private var brushTracking:NSTrackingArea?
    var bridgeSelected:((Int)->Void)?
    var zoom:CGFloat=1,pan=CGPoint.zero
    private var dragStart:CGPoint?,panStart=CGPoint.zero
    private var bodyOrigin=CGPoint.zero,bodyScale:CGFloat=1
    var artwork: CGImage? { didSet { needsDisplay = true } }
    var base = BasePreview() { didSet { needsDisplay = true } }
    var previewMode: String = "art" { didSet { needsDisplay = true } }
    var showComparison = true { didSet { needsDisplay = true } }
    var detailIndex: Int? { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    private var paths: [String: CGPath] = [:]
    private(set) var pathError: String?
    private let cutColor = NSColor(calibratedRed: 0.97, green: 0.14, blue: 0.48, alpha: 1)
    private let bridgeColor = NSColor(calibratedRed: 0.09, green: 0.70, blue: 0.72, alpha: 0.48)
    private var isDark:Bool { effectiveAppearance.bestMatch(from:[.darkAqua,.aqua]) == .darkAqua }
    private var ink:NSColor { isDark ? NSColor(calibratedWhite:0.90,alpha:1) : NSColor(calibratedRed:0.16,green:0.19,blue:0.28,alpha:1) }
    private var muted:NSColor { isDark ? NSColor(calibratedWhite:0.66,alpha:1) : NSColor(calibratedRed:0.43,green:0.47,blue:0.55,alpha:1) }
    override func viewDidChangeEffectiveAppearance(){super.viewDidChangeEffectiveAppearance();needsDisplay=true}

    func fitView(){zoom=1;pan = .zero;needsDisplay=true}
    func actualSize(){zoom=(72/25.4)/max(0.01,bodyScale);pan = .zero;needsDisplay=true}
    func pixelDetail(){guard let g=geometry,let white=whiteImage else{return};zoom=min(30,CGFloat(white.height)/(CGFloat(g.imageBox.height)*bodyScale));pan = .zero;needsDisplay=true}
    override func resetCursorRects(){if brushEnabled{addCursorRect(bounds,cursor:.crosshair)}}
    override func updateTrackingAreas(){
        super.updateTrackingAreas();if let old=brushTracking{removeTrackingArea(old)}
        let area=NSTrackingArea(rect:bounds,options:[.mouseMoved,.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self,userInfo:nil)
        addTrackingArea(area);brushTracking=area
    }
    override func mouseMoved(with event:NSEvent){cursorPoint=convert(event.locationInWindow,from:nil);if brushEnabled{needsDisplay=true}}
    override func mouseExited(with event:NSEvent){cursorPoint=nil;needsDisplay=true}
    func modelPoint(at q:CGPoint)->CGPoint {
        let screen=CGPoint(x:(q.x-bounds.midX-pan.x)/zoom+bounds.midX,y:(q.y-bounds.midY-pan.y)/zoom+bounds.midY)
        return CGPoint(x:(screen.x-bodyOrigin.x)/bodyScale,y:(screen.y-bodyOrigin.y)/bodyScale)
    }
    func sourcePoint(at q:CGPoint)->WhiteBrushPoint? {
        guard let g=geometry else{return nil};let p=modelPoint(at:q)
        return WhiteBrushPoint(x:(p.x-g.imageBox.x)/g.imageBox.width,y:(p.y-g.imageBox.y)/g.imageBox.height)
    }
    private func appendBrushPoint(_ q:CGPoint,force:Bool=false){
        guard let p=sourcePoint(at:q),let g=geometry else{return}
        if let last=draftPoints.last,!force,hypot((p.x-last.x)*g.imageBox.width,(p.y-last.y)*g.imageBox.height)<brushDiameter/12{return}
        draftPoints.append(p);cursorPoint=q;needsDisplay=true
    }
    override func scrollWheel(with event:NSEvent){
        let p=convert(event.locationInWindow,from:nil),old=zoom;zoom=max(0.35,min(30,zoom*exp(-event.scrollingDeltaY*0.012)));let ratio=zoom/old
        pan.x=p.x-bounds.midX-(p.x-bounds.midX-pan.x)*ratio;pan.y=p.y-bounds.midY-(p.y-bounds.midY-pan.y)*ratio;needsDisplay=true
    }
    override func mouseDown(with event:NSEvent){
        let q=convert(event.locationInWindow,from:nil);dragStart=nil
        if brushEnabled && !event.modifierFlags.contains(.option) {
            guard let g=geometry,g.imageBox.cgRect.contains(modelPoint(at:q)),paths["body"]?.contains(modelPoint(at:q),using:.evenOdd,transform:.identity)==true else{return}
            draftPoints=[];draftRadius=brushDiameter/(2*g.imageBox.height);appendBrushPoint(q,force:true);return
        }
        dragStart=q;panStart=pan
    }
    override func mouseDragged(with event:NSEvent){
        let q=convert(event.locationInWindow,from:nil)
        if !draftPoints.isEmpty{appendBrushPoint(q);return}
        guard let p=dragStart else{return};pan=CGPoint(x:panStart.x+q.x-p.x,y:panStart.y+q.y-p.y);needsDisplay=true
    }
    override func mouseUp(with event:NSEvent){
        let q=convert(event.locationInWindow,from:nil)
        if !draftPoints.isEmpty {
            appendBrushPoint(q);let stroke=WhiteBrushStroke(points:draftPoints,radius:draftRadius);draftPoints=[]
            whiteStrokeCommitted?(stroke);needsDisplay=true;return
        }
        guard let p=dragStart else{return};defer{dragStart=nil};if brushEnabled || hypot(q.x-p.x,q.y-p.y)>4{return};guard detailIndex==nil,let g=geometry else{return}
        let point=modelPoint(at:q)
        if let i=g.sortedBridgeRegions.firstIndex(where:{$0.bounds.cgRect.insetBy(dx:-1,dy:-1).contains(point)}){bridgeSelected?(i)}
    }
    private func refreshPaths() {
        paths.removeAll(); pathError = nil
        guard let g = geometry else { return }
        let inputs = ["body": g.bodyPath, "bodyOnly": g.bodyOnlyPath, "baseline": g.baselinePath,
                      "bridge": g.bridgePath, "white": g.whitePath, "silhouette": g.silhouettePath]
        do { for (name, source) in inputs { paths[name] = try SVGPath.parse(source) } }
        catch { pathError = error.localizedDescription }
    }

    override func draw(_ dirtyRect: NSRect) {
        (isDark ? NSColor(calibratedRed:0.105,green:0.115,blue:0.135,alpha:1) : NSColor(calibratedRed:0.965,green:0.974,blue:0.988,alpha:1)).setFill()
        bounds.fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        guard let geometry = geometry else {
            text("导入透明底图片，开始制作立牌", in: CGRect(x: 20, y: bounds.midY - 35, width: bounds.width - 40, height: 32), size: 19, color: ink)
            text("轮廓、白墨、插脚和底座会在这里实时预览", in: CGRect(x: 20, y: bounds.midY + 2, width: bounds.width - 40, height: 28), size: 13, color: muted)
            return
        }
        if let error = pathError {
            text(error, in: bounds.insetBy(dx: 30, dy: 35), size: 14, color: .systemRed)
            return
        }
        let regions = geometry.sortedBridgeRegions
        context.saveGState();context.translateBy(x:bounds.midX+pan.x,y:bounds.midY+pan.y);context.scaleBy(x:zoom,y:zoom);context.translateBy(x:-bounds.midX,y:-bounds.midY)
        if let detail = detailIndex, regions.indices.contains(detail) {
            drawDetail(geometry, region: regions[detail], index: detail, count: regions.count, in: context)
        } else {
            drawFull(geometry, in: context)
        }
        context.restoreGState()
        if brushEnabled,let p=cursorPoint,bounds.contains(p) {
            let r=brushDiameter*bodyScale*zoom/2,rect=CGRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2)
            context.saveGState();context.setLineWidth(3);context.setStrokeColor(NSColor.white.cgColor);context.strokeEllipse(in:rect)
            context.setLineWidth(1);context.setStrokeColor(NSColor.black.cgColor);context.strokeEllipse(in:rect);context.restoreGState()
        }
        drawLegend()
    }

    private func drawFull(_ g: StandeeGeometry, in context: CGContext) {
        let cutBounds = paths["body"]?.boundingBoxOfPath ?? g.bounds.cgRect
        let bodyBounds = g.tabs.reduce(cutBounds) { $0.union($1.cgRect) }
        guard bodyBounds.width > 0 && bodyBounds.height > 0 else { return }
        let baseWidth = max(1, CGFloat(base.widthMm)), baseHeight = max(1, CGFloat(base.heightMm))
        let baseRect = CGRect(x: bodyBounds.maxX + 24, y: bodyBounds.midY - baseHeight / 2, width: baseWidth, height: baseHeight)
        let scene = bodyBounds.union(baseRect)
        let viewport = CGRect(x: 32, y: 79, width: max(1, bounds.width - 64), height: max(1, bounds.height - 157))
        let placement = fitted(scene, to: viewport)
        let scale = placement.scale
        bodyOrigin=placement.origin;bodyScale=scale
        context.saveGState()
        context.translateBy(x: placement.origin.x, y: placement.origin.y)
        context.scaleBy(x: scale, y: scale)
        drawBody(g, in: context, scale: scale, forceComparison: false)
        drawBase(g, rect: baseRect, in: context, scale: scale)
        context.restoreGState()

        let bodyScreen = screenRect(bodyBounds, placement: placement)
        let baseScreen = screenRect(baseRect, placement: placement)
        text("主体 · 正面", in: CGRect(x: bodyScreen.minX - 20, y: bodyScreen.minY - 56, width: bodyScreen.width + 40, height: 23), size: 15, color: ink)
        text("主体高 \(mm(g.heightMm)) mm · 插脚为参考框", in: CGRect(x: bodyScreen.minX - 50, y: bodyScreen.minY - 33, width: bodyScreen.width + 100, height: 22), size: 11, color: muted)
        let shapeName = base.shape == "circle" ? "圆形" : base.shape == "square" ? "正方形" : "长方形"
        text("\(shapeName)底座 · 俯视", in: CGRect(x: baseScreen.minX - 25, y: baseScreen.minY - 36, width: baseScreen.width + 50, height: 25), size: 14, color: ink)
        dimension(from: CGPoint(x: bodyScreen.minX, y: bodyScreen.maxY + 18), to: CGPoint(x: bodyScreen.maxX, y: bodyScreen.maxY + 18), label: "\(mm(Double(bodyBounds.width))) mm", in: context)
        let baseLabel = base.shape == "circle" ? "Ø \(mm(base.widthMm)) mm" : "\(mm(base.widthMm)) × \(mm(base.heightMm)) mm"
        dimension(from: CGPoint(x: baseScreen.minX, y: baseScreen.maxY + 18), to: CGPoint(x: baseScreen.maxX, y: baseScreen.maxY + 18), label: baseLabel, in: context)
        text("透明 · 厚 \(mm(base.thicknessMm)) mm", in: CGRect(x: baseScreen.minX - 25, y: baseScreen.maxY + 46, width: baseScreen.width + 50, height: 22), size: 11, color: muted)
    }

    private func drawDetail(_ g: StandeeGeometry, region: StandeeGeometry.BridgeRegion, index: Int, count: Int, in context: CGContext) {
        let box = region.bounds.cgRect
        let padding = max(5, max(box.width, box.height) * 0.60)
        let area = box.insetBy(dx: -padding, dy: -padding)
        let viewport = CGRect(x: 28, y: 68, width: max(1, bounds.width - 56), height: max(1, bounds.height - 135))
        let placement = fitted(area, to: viewport)
        text("跨接细节 \(index + 1) / \(count)", in: CGRect(x: 24, y: 18, width: bounds.width - 48, height: 30), size: 17, color: ink)
        context.saveGState()
        context.clip(to: viewport)
        context.translateBy(x: placement.origin.x, y: placement.origin.y)
        context.scaleBy(x: placement.scale, y: placement.scale)
        drawBody(g, in: context, scale: placement.scale, forceComparison: true)
        context.restoreGState()
        if let mouth = region.mouthWidthMm, let depth = region.previousDepthMm {
            text("原凹口宽 \(mm(mouth)) mm · 深 \(mm(depth)) mm", in: CGRect(x: 24, y: bounds.height - 64, width: bounds.width - 48, height: 23), size: 12, color: muted)
        }
    }

    private func drawBody(_ g: StandeeGeometry, in context: CGContext, scale: CGFloat, forceComparison: Bool) {
        guard let body = paths["body"] else { return }
        context.saveGState()
        context.addPath(body); context.clip(using: .evenOdd)
        checker(in: body.boundingBoxOfPath.insetBy(dx: -1, dy: -1), context: context, square: max(1, 13 / scale))
        if previewMode == "white", let white = whiteImage {
            if brushEnabled,let image=artwork {
                let rect=g.imageBox.cgRect;context.saveGState();context.setAlpha(0.22);context.translateBy(x:rect.minX,y:rect.maxY);context.scaleBy(x:1,y:-1);context.draw(image,in:CGRect(origin:.zero,size:rect.size));context.restoreGState()
            }
            let rect=g.imageBox.cgRect;context.saveGState();context.translateBy(x:rect.minX,y:rect.maxY);context.scaleBy(x:1,y:-1);context.draw(white,in:CGRect(origin:.zero,size:rect.size));context.restoreGState()
            context.saveGState();context.clip(to:rect);context.setFillColor(NSColor.black.cgColor);context.setStrokeColor(NSColor.black.cgColor)
            for stroke in pendingWhiteStrokes{stroke.draw(in:context,rect:rect)}
            if !draftPoints.isEmpty{WhiteBrushStroke(points:draftPoints,radius:draftRadius).draw(in:context,rect:rect)}
            context.restoreGState()
        } else if previewMode == "silhouette", let silhouette = paths["silhouette"] {
            context.addPath(silhouette); context.setFillColor(NSColor.black.cgColor); context.drawPath(using: .eoFill)
        } else if previewMode != "cut" && previewMode != "dieline", let image = artwork {
            // imageBox maps the original image canvas, including transparent margins.
            let rect = g.imageBox.cgRect
            context.saveGState()
            context.translateBy(x: rect.minX, y: rect.maxY)
            context.scaleBy(x: 1, y: -1)
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
            context.restoreGState()
        }
        context.restoreGState()
        if (showComparison || forceComparison) && previewMode != "white" && previewMode != "silhouette" {
            if let bridge = paths["bridge"] {
                context.addPath(bridge); context.setFillColor(bridgeColor.cgColor); context.drawPath(using: .eoFill)
            }
            if let baseline = paths["baseline"], !(g.bridgeRegions ?? []).isEmpty {
                context.saveGState()
                for region in g.bridgeRegions ?? [] { context.addRect(region.bounds.cgRect.insetBy(dx: -0.75, dy: -0.75)) }
                context.clip()
                context.addPath(baseline)
                context.setStrokeColor(NSColor(calibratedRed: 0.42, green: 0.46, blue: 0.51, alpha: 0.95).cgColor)
                context.setLineWidth(1.6 / scale); context.setLineDash(phase: 0, lengths: [4 / scale, 3 / scale]); context.strokePath()
                context.restoreGState()
            }
        }
        context.addPath(body)
        context.setStrokeColor(cutColor.cgColor)
        context.setLineWidth(1.7 / scale); context.setLineJoin(.round); context.setLineCap(.round)
        context.strokePath()
        if previewMode != "white" && previewMode != "silhouette" {
            context.saveGState()
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1.5 / scale); context.setLineJoin(.miter)
            for tab in g.tabs { context.stroke(tab.cgRect) }
            context.restoreGState()
        }
    }

    private func drawBase(_ g: StandeeGeometry, rect: CGRect, in context: CGContext, scale: CGFloat) {
        let outline = CGMutablePath()
        if base.shape == "circle" { outline.addEllipse(in: rect) }
        else { outline.addRoundedRect(in: rect, cornerWidth: min(3, rect.width / 2), cornerHeight: min(3, rect.height / 2)) }
        context.saveGState()
        context.addPath(outline); context.clip()
        checker(in: rect, context: context, square: max(1, 13 / scale))
        context.restoreGState()
        context.addPath(outline); context.setStrokeColor(cutColor.cgColor); context.setLineWidth(1.7 / scale); context.strokePath()
        let tabMean = g.tabs.map { $0.effectiveCenterX }.reduce(0, +) / Double(max(1, g.tabs.count))
        for tab in g.tabs {
            // The same relative centres are used on the standee and on the base.
            let center = rect.midX + CGFloat(tab.effectiveCenterX - tabMean)
            let slot = CGRect(x: center - base.slotWidthMm / 2, y: rect.midY - base.slotHeightMm / 2, width: base.slotWidthMm, height: base.slotHeightMm)
            let radius = max(0, min(CGFloat(base.slotRadiusMm), min(slot.width, slot.height) / 2))
            context.addPath(CGPath(roundedRect: slot, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.setFillColor(NSColor(calibratedRed: 0.23, green: 0.27, blue: 0.35, alpha: 1).cgColor)
            context.setStrokeColor(cutColor.cgColor); context.setLineWidth(1.4 / scale); context.drawPath(using: .fillStroke)
        }
    }

    private func checker(in rect: CGRect, context: CGContext, square: CGFloat) {
        // Keep sufficient contrast against the black white-ink mask in both appearances.
        context.setFillColor((isDark ? NSColor(calibratedWhite:0.53,alpha:1) : NSColor.white).cgColor); context.fill(rect)
        context.setFillColor((isDark ? NSColor(calibratedWhite:0.46,alpha:1) : NSColor(calibratedRed:0.88,green:0.90,blue:0.94,alpha:1)).cgColor)
        let minX = Int(floor(rect.minX / square)), maxX = Int(ceil(rect.maxX / square))
        let minY = Int(floor(rect.minY / square)), maxY = Int(ceil(rect.maxY / square))
        if maxX - minX > 2000 || maxY - minY > 2000 { return }
        for row in minY..<maxY { for column in minX..<maxX where (row + column) % 2 == 0 {
            context.fill(CGRect(x: CGFloat(column) * square, y: CGFloat(row) * square, width: square, height: square))
        } }
    }

    private typealias Placement = (origin: CGPoint, scale: CGFloat)
    private func fitted(_ rect: CGRect, to viewport: CGRect) -> Placement {
        let scale = max(0.001, min(viewport.width / max(0.001, rect.width), viewport.height / max(0.001, rect.height)))
        return (CGPoint(x: viewport.midX - rect.midX * scale, y: viewport.midY - rect.midY * scale), scale)
    }
    private func screenRect(_ rect: CGRect, placement: Placement) -> CGRect {
        CGRect(x: placement.origin.x + rect.minX * placement.scale, y: placement.origin.y + rect.minY * placement.scale,
               width: rect.width * placement.scale, height: rect.height * placement.scale)
    }
    private func mm(_ value: Double) -> String { String(format: "%0.1f", value) }
    private func text(_ string: String, in rect: CGRect, size: CGFloat, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
        (string as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color, .paragraphStyle: paragraph])
    }
    private func dimension(from start: CGPoint, to end: CGPoint, label: String, in context: CGContext) {
        context.saveGState()
        context.setLineWidth(0.8); context.setStrokeColor(muted.withAlphaComponent(0.72).cgColor)
        context.move(to: start); context.addLine(to: end)
        context.move(to: CGPoint(x: start.x, y: start.y - 4)); context.addLine(to: CGPoint(x: start.x, y: start.y + 4))
        context.move(to: CGPoint(x: end.x, y: end.y - 4)); context.addLine(to: CGPoint(x: end.x, y: end.y + 4)); context.strokePath()
        context.restoreGState()
        text(label, in: CGRect(x: start.x - 20, y: start.y + 5, width: end.x - start.x + 40, height: 22), size: 11, color: muted)
    }
    private func drawLegend() {
        let legend: String
        if previewMode == "white" { legend = brushEnabled ? "补白画笔：点击或拖涂 · 黑色为白墨 · Option 拖动画布 · 滚轮缩放" : "黑色：白墨覆盖区域 · 粉线：成品刀线" }
        else if previewMode == "silhouette" { legend = "黑色：填孔后的轮廓 · 粉线：成品刀线" }
        else if showComparison || detailIndex != nil { legend = "粉线：刀线 · 蓝框：插脚位置参考 · 灰虚线：原凹口 · 青色：新增透明材料" }
        else { legend = "粉线：成品刀线 · 蓝框：插脚位置参考（工厂调整）· 棋盘格：透明亚克力" }
        text(legend, in: CGRect(x: 16, y: bounds.height - 30, width: bounds.width - 32, height: 22), size: 11, color: muted)
    }
}
