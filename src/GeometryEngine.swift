import AppKit
import ImageIO
import JavaScriptCore

struct StandeeSettings:Equatable {
    var height=150.0,thickness=3.0,offset=3.0,smooth=1.0
    var curveSmooth=60.0,cornerRadius=1.0,toolDiameter=3.0,bridgeWidth=16.0,notchDepth=1.0
    var tabWidth=18.0,tabDepth=3.0,tabPosition=0.0,tabOverlap=3.0,tabCount=1
    var whiteBrushSize=2.0,whiteStrokes:[WhiteBrushStroke]=[]
    var whiteInset=0.0,whiteFill=false,cncBridge=true,threshold=10.0,whiteFollowsAlpha=false,whiteVector=false
    var baseShape="circle",baseWidth=65.0,baseLength=45.0,fit=0.0
    var disabledBridges:[Int]=[]
    var jobName="亚克力立牌",printFace="正面单面",notes="",factoryDPI=350.0
    var options:[String:Any] {["height":height,"offset":offset,"curveSmooth":curveSmooth,"cornerRadius":cornerRadius,"toolDiameter":toolDiameter,"bridgeWidth":bridgeWidth,"maxNotchDepth":notchDepth,"tabWidth":tabWidth,"tabDepth":tabDepth,"tabPosition":tabPosition,"tabOverlap":tabOverlap,"tabCount":tabCount,"cncBridge":cncBridge,"disabledBridges":disabledBridges,"threshold":Int((threshold*2.55).rounded())]}
    var geometryKey:String {String(data:try! JSONSerialization.data(withJSONObject:options,options:.sortedKeys),encoding:.utf8)!}
    var baseHeight:Double {baseShape=="rectangle" ? baseLength:baseWidth}
    var basePreview:BasePreview {BasePreview(widthMm:baseWidth,heightMm:baseHeight,shape:baseShape,slotWidthMm:tabWidth+fit,slotHeightMm:thickness+fit,slotRadiusMm:min(0.4,(thickness+fit)/4),thicknessMm:tabDepth)}
    func restoringDefaults()->StandeeSettings {
        var result=StandeeSettings();result.jobName=jobName;result.notes=notes;result.whiteStrokes=whiteStrokes
        return result
    }
}
struct LoadedArtwork {
    let id=UUID()
    let url:URL,image:CGImage,preview:CGImage,width:Int,height:Int,alpha:[UInt8],sourceData:Data
    static func load(_ url:URL)throws->LoadedArtwork{
        let data=try Data(contentsOf:url)
        guard let source=CGImageSourceCreateWithData(data as CFData,nil),CGImageSourceGetType(source) as String? == "public.png",let props=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],let w=props[kCGImagePropertyPixelWidth] as? Int,let h=props[kCGImagePropertyPixelHeight] as? Int,w*h<=60000000 else{throw AppFailure("请选择有效 PNG（支持原始分辨率，当前上限 6000 万像素）。")}
        func thumb(_ side:Int)->CGImage?{CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:side,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary)}
        guard let image=CGImageSourceCreateImageAtIndex(source,0,[kCGImageSourceShouldCacheImmediately:false] as CFDictionary),let small=thumb(960),let preview=thumb(2000) else{throw AppFailure("PNG 解码失败。")}
        let alpha=try extractAlpha(small)
        guard alpha.contains(where:{$0>0}) else{throw AppFailure("图片完全透明。")}
        return LoadedArtwork(url:url,image:image,preview:preview,width:small.width,height:small.height,alpha:alpha,sourceData:data)
    }
    static func extractAlpha(_ image:CGImage)throws->[UInt8]{
        let w=image.width,h=image.height;var rgba=[UInt8](repeating:0,count:w*h*4)
        let ok=rgba.withUnsafeMutableBytes{buf->Bool in guard let c=CGContext(data:buf.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue) else{return false};c.setBlendMode(.copy);c.draw(image,in:CGRect(x:0,y:0,width:w,height:h));return true}
        guard ok else{throw AppFailure("无法读取原图透明度。")};return stride(from:3,to:rgba.count,by:4).map{rgba[$0]}
    }
}
struct GeometryResult {let model:StandeeGeometry,json:[String:Any],data:Data}
struct AppFailure:LocalizedError {let message:String;init(_ s:String){message=s};var errorDescription:String?{message}}
final class Cancellation {private let lock=NSLock();private var value=false;func cancel(){lock.lock();value=true;lock.unlock()};var cancelled:Bool{lock.lock();defer{lock.unlock()};return value}}
final class GeometryEngine {
    let engineURL:URL
    private var context:JSContext?,artID:UUID?,cache:[String:GeometryResult]=[:]
    init(engineURL:URL){self.engineURL=engineURL}
    func build(_ art:LoadedArtwork,settings:StandeeSettings,cancellation:Cancellation?=nil)throws->GeometryResult{
        if cancellation?.cancelled==true{throw AppFailure("CANCELLED")}
        let key=art.id.uuidString+settings.geometryKey
        if let hit=cache[key]{return hit}
        if artID != art.id {
            guard let c=JSContext() else{throw AppFailure("无法启动轮廓计算。")};context=c;artID=art.id;cache.removeAll()
            let polygon:@convention(block)(String,Int,Double)->String={str,op,delta in
                guard let d=str.data(using:.utf8),let loops=try? JSONSerialization.jsonObject(with:d) as? [[[Double]]] else{return "[]"}
                let counts=loops.map{Int32($0.count)},xy=loops.flatMap{$0.flatMap{$0}}
                return counts.withUnsafeBufferPointer{cs in xy.withUnsafeBufferPointer{vs in guard let ptr=acrylic_polygon(vs.baseAddress,cs.baseAddress,Int32(counts.count),Int32(op),delta)else{return "[]"};defer{acrylic_free(ptr)};return String(cString:ptr)}}
            };c.setObject(polygon,forKeyedSubscript:"NativePolygon" as NSString)
            c.evaluateScript(try String(contentsOf:engineURL.deletingLastPathComponent().appendingPathComponent("curve-fit.js"),encoding:.utf8));c.evaluateScript(try String(contentsOf:engineURL,encoding:.utf8))
            let input:[String:Any]=["width":art.width,"height":art.height,"alpha":art.alpha,"originalWidth":art.image.width,"originalHeight":art.image.height]
            let data=try JSONSerialization.data(withJSONObject:input);c.evaluateScript("var source="+String(data:data,encoding:.utf8)!+";source.alpha=new Uint8Array(source.alpha);")
        }
        let c=context!,stop:@convention(block)()->Bool={cancellation?.cancelled ?? false};c.setObject(stop,forKeyedSubscript:"NativeCancelled" as NSString)
        var failure:String?;c.exceptionHandler={_,e in failure=e?.toString()}
        let value=c.evaluateScript("JSON.stringify(AcrylicGeometry.build(source,"+settings.geometryKey+"))")
        if let failure=failure{throw AppFailure(failure)};if cancellation?.cancelled==true{throw AppFailure("CANCELLED")}
        guard let text=value?.toString(),let data=text.data(using:.utf8),let json=try JSONSerialization.jsonObject(with:data) as? [String:Any]else{throw AppFailure("轮廓结果无效。")}
        let r=GeometryResult(model:try JSONDecoder().decode(StandeeGeometry.self,from:data),json:json,data:data)
        if cache.count>10{cache.removeAll()};cache[key]=r;return r
    }
    func vectorWhite(_ ink:WhiteInk,box:StandeeGeometry.Rect)throws->String {
        guard let c=context else{throw AppFailure("请先生成刀线。")}
        let raw=ink.alpha.withUnsafeBufferPointer{buf->String in guard let p=acrylic_trace(buf.baseAddress,Int32(ink.width),Int32(ink.height),128)else{return "[]"};defer{acrylic_free(p)};return String(cString:p)}
        let script="var wp="+raw+"; CurveFit.path(wp.map(p=>p.map(q=>[q[0]*\(box.width/Double(ink.width))+\(box.x),q[1]*\(box.height/Double(ink.height))+\(box.y)])),0.012).path"
        guard let text=c.evaluateScript(script)?.toString(),!text.isEmpty else{throw AppFailure("白墨矢量过于复杂或为空，请使用原图蒙版输出。")};return text
    }
}
