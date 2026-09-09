import AppKit
import CoreGraphics
import ImageIO

/// Local PDF interchange export. Artwork is converted using the system Generic
/// CMYK profile; the factory may assign its own print profile in Illustrator.
/// Millimetre vectors are preserved. This is not a CNC toolpath file.
enum CMYKPDF {
    private static let pointsPerMm: CGFloat = 72 / 25.4
    private static let cmykSpace = CGColorSpaceCreateDeviceCMYK()

    static func export(art: LoadedArtwork, result: GeometryResult, settings: StandeeSettings, white:WhiteInk, to url: URL) throws {
        guard url.isFileURL, url.pathExtension.lowercased() == "pdf" else { throw AppFailure("请选择 .pdf 格式的本地输出文件。") }
        guard !FileManager.default.fileExists(atPath: url.path) else { throw AppFailure("同名文件已经存在，请另存为新名称。") }
        let g = result.model
        let layout = try ExportLayout.make(result: result, settings: settings)
        let body = try SVGPath.parse(g.bodyPath)
        let whitePath = try white.vectorPath.map {try SVGPath.parse($0)}
        let basePath = layout.baseGeometry
        let slots = layout.slots.map { $0.geometry }
        let tabReferences = g.tabs.map { CGPath(rect:$0.cgRect,transform:nil) }
        let image = try makeCMYKImage(art.image)
        var mediaBox = CGRect(x: 0, y: 0, width: layout.pageWidth * Double(pointsPerMm), height: layout.pageHeight * Double(pointsPerMm))
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, [
                kCGPDFContextTitle: "亚克力立牌 · CMYK 制版文件",
                kCGPDFContextCreator: "亚克力立牌助手 · 本地应用",
                kCGPDFContextSubject: "1 彩图与刀线及插脚参考；2 K100 白墨；3 主体刀线；4 底座与插槽；5 插脚位置参考（不作刀线）；6 制版说明。单位毫米。",
                kCGPDFContextKeywords: ["CMYK", "acrylic standee", "vector dieline", "white ink"]
              ] as CFDictionary) else { throw AppFailure("无法建立 CMYK PDF 文件。") }
        for page in 1...6 {
            if page==6 {var infoRect=CGRect(x:0,y:0,width:FactorySheet.width*72/25.4,height:FactorySheet.height*72/25.4);let boxData=NSData(bytes:&infoRect,length:MemoryLayout<CGRect>.size);context.beginPDFPage([kCGPDFContextMediaBox:boxData] as CFDictionary);FactorySheet.draw(context,art:art,result:result,settings:settings,white:white,color:image);context.endPDFPage();continue}
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: mediaBox.height)
            context.scaleBy(x: pointsPerMm, y: -pointsPerMm)
            context.setFillColorSpace(cmykSpace)
            context.setStrokeColorSpace(cmykSpace)
            context.setLineWidth(0.1)
            context.setLineJoin(.round)
            context.setLineCap(.round)
            if page == 1 {
                context.saveGState()
                context.translateBy(x: layout.bodyX, y: layout.bodyY)
                context.addPath(body); context.clip(using: .evenOdd)
                let box = g.imageBox.cgRect
                context.translateBy(x: box.minX, y: box.maxY)
                context.scaleBy(x: 1, y: -1)
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: 0, y: 0, width: box.width, height: box.height))
                context.restoreGState()
            }
            if page == 2 {
                context.saveGState()
                context.translateBy(x: layout.bodyX, y: layout.bodyY)
                context.setFillColor([0, 0, 0, 1, 1])
                if let path=whitePath {context.addPath(path);context.drawPath(using:.eoFill)}else{try white.draw(in:context,rect:g.imageBox.cgRect)}
                context.restoreGState()
            }
            if page == 1 || page == 3 {
                context.saveGState()
                context.translateBy(x: layout.bodyX, y: layout.bodyY)
                context.setStrokeColor([0, 1, 0, 0, 1])
                context.addPath(body); context.strokePath()
                context.restoreGState()
            }
            if page == 1 || page == 5 {
                context.saveGState()
                context.translateBy(x: layout.bodyX, y: layout.bodyY)
                context.setStrokeColor([1, 0, 0, 0, 1])
                context.setLineJoin(.miter)
                for reference in tabReferences { context.addPath(reference) }
                context.strokePath()
                context.restoreGState()
            }
            if page == 1 || page == 4 {
                context.saveGState()
                context.translateBy(x: layout.baseX, y: layout.baseY)
                context.setStrokeColor([0, 1, 0, 0, 1])
                context.addPath(basePath)
                for slot in slots { context.addPath(slot) }
                context.strokePath()
                context.restoreGState()
            }
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        let data = pdfData as Data
        try validate(data, expectedMediaBox: mediaBox)
        do { try data.write(to: url, options: .withoutOverwriting) }
        catch { throw AppFailure("无法保存 PDF，或同名文件已经存在：\(error.localizedDescription)") }
        let saved = try Data(contentsOf: url)
        guard saved == data else { throw AppFailure("PDF 保存后内容校验失败。") }
        try validate(saved, expectedMediaBox: mediaBox)
    }

    /// Build a four-channel CMYK image with a separate grayscale transparency
    /// mask. RGB is unpremultiplied before conversion, so partially transparent
    /// pixels do not acquire a second dark alpha edge.
    static func makeCMYKImage(_ original: CGImage) throws -> CGImage {
        let width = original.width, height = original.height
        guard width > 0, height > 0, width*height <= 60000000 else {
            throw AppFailure("图片超过 6000 万像素，无法在本机内存预算内转换。")
        }
        let pixels = width * height
        let rgbSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        var rgba = [UInt8](repeating: 0, count: pixels * 4)
        let extracted = rgba.withUnsafeMutableBytes { memory -> Bool in
            guard let context = CGContext(data: memory.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: rgbSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.setBlendMode(.copy)
            context.draw(original, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard extracted else { throw AppFailure("无法读取图像透明度。") }
        var rgb = [UInt8](repeating: 255, count: pixels * 3)
        var alpha = [UInt8](repeating: 0, count: pixels)
        for i in 0..<pixels {
            let a = Int(rgba[i * 4 + 3]); alpha[i] = UInt8(a)
            if a > 0 {
                for component in 0..<3 {
                    rgb[i * 3 + component] = UInt8(min(255, (Int(rgba[i * 4 + component]) * 255 + a / 2) / a))
                }
            }
        }
        guard let rgbProvider = CGDataProvider(data: Data(rgb) as CFData),
              let unassociatedRGB = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 24,
                bytesPerRow: width * 3, space: rgbSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: rgbProvider, decode: nil, shouldInterpolate: true, intent: .relativeColorimetric) else {
            throw AppFailure("无法建立图像色彩转换数据。")
        }
        let conversionSpace = CGColorSpace(name: CGColorSpace.genericCMYK) ?? cmykSpace
        var converted = [UInt8](repeating: 0, count: pixels * 4)
        let convertedOK = converted.withUnsafeMutableBytes { memory -> Bool in
            guard let context = CGContext(data: memory.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: conversionSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.setRenderingIntent(.relativeColorimetric)
            context.setBlendMode(.copy)
            context.draw(unassociatedRGB, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard convertedOK,
              let imageProvider = CGDataProvider(data: Data(converted) as CFData),
              let cmyk = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: cmykSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: imageProvider, decode: nil, shouldInterpolate: true, intent: .relativeColorimetric),
              let maskProvider = CGDataProvider(data: Data(alpha) as CFData),
              let mask = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: maskProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent),
              let masked = cmyk.masking(mask) else { throw AppFailure("无法建立带透明度的 CMYK 图像。") }
        guard masked.colorSpace?.model == .cmyk else { throw AppFailure("图像转换未返回 CMYK 数据。") }
        return masked
    }

    static func imagePage(_ image:CGImage,widthMm:Double,heightMm:Double)throws->Data{
        let d=NSMutableData();var box=CGRect(x:0,y:0,width:widthMm*72/25.4,height:heightMm*72/25.4)
        guard let consumer=CGDataConsumer(data:d as CFMutableData),let c=CGContext(consumer:consumer,mediaBox:&box,nil)else{throw AppFailure("彩稿 PDF 创建失败。")}
        c.beginPDFPage(nil);c.draw(image,in:box);c.endPDFPage();c.closePDF();return d as Data
    }
    private static func validate(_ data: Data, expectedMediaBox: CGRect) throws {
        guard data.count > 1000, let provider = CGDataProvider(data: data as CFData),
              let pdf = CGPDFDocument(provider), pdf.numberOfPages == 6 else {
            throw AppFailure("生成的 PDF 页数或内容无效。")
        }
        for page in 1...5 {
            guard let box = pdf.page(at: page)?.getBoxRect(.mediaBox),
                  abs(box.width - expectedMediaBox.width) < 0.01,
                  abs(box.height - expectedMediaBox.height) < 0.01 else {
                throw AppFailure("PDF 第 \(page) 页的毫米尺寸校验失败。")
            }
        }
    }
}
