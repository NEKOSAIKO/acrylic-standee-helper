import AppKit
import Accelerate

/// Brush coordinates are normalized to the original image, so edits stay on
/// the same pixels when the standee size, preview zoom or pan changes.
struct WhiteBrushPoint:Equatable { let x:Double,y:Double }
struct WhiteBrushStroke:Equatable {
    let id:UUID
    let points:[WhiteBrushPoint]
    let radius:Double // Fraction of the source image height.
    init(points:[WhiteBrushPoint],radius:Double){id=UUID();self.points=points;self.radius=radius}
    func draw(in c:CGContext,rect:CGRect) {
        guard let first=points.first,radius>0 else{return}
        let r=radius*rect.height
        func mapped(_ p:WhiteBrushPoint)->CGPoint{CGPoint(x:rect.minX+p.x*rect.width,y:rect.minY+p.y*rect.height)}
        c.setLineWidth(r*2);c.setLineCap(.round);c.setLineJoin(.round)
        let p=mapped(first);c.fillEllipse(in:CGRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2))
        if points.count>1 {c.move(to:p);for point in points.dropFirst(){c.addLine(to:mapped(point))};c.strokePath()}
    }
}
struct WhiteInk {
    let width:Int,height:Int,alpha:[UInt8],mask:CGImage,preview:CGImage,vectorPath:String?
    var nonzero:Int {alpha.reduce(0){$0+($1>0 ? 1:0)}}
    func withVector(_ p:String)->WhiteInk{WhiteInk(width:width,height:height,alpha:alpha,mask:mask,preview:preview,vectorPath:p)}
    func cmykImage()throws->CGImage{
        var pixels=[UInt8](repeating:0,count:width*height*4);for i in stride(from:3,to:pixels.count,by:4){pixels[i]=255}
        guard let provider=CGDataProvider(data:Data(pixels) as CFData),let image=CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceCMYK(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.none.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent),let result=image.masking(mask)else{throw AppFailure("白墨 CMYK 图像建立失败。")};return result
    }
    func draw(in c:CGContext,rect:CGRect)throws{
        let image=try cmykImage();c.saveGState();c.translateBy(x:rect.minX,y:rect.maxY);c.scaleBy(x:1,y:-1);c.draw(image,in:CGRect(origin:.zero,size:rect.size));c.restoreGState()
    }
    func pdfData(widthMm:Double,heightMm:Double)throws->Data{
        try CMYKPDF.imagePage(cmykImage(),widthMm:widthMm,heightMm:heightMm)
    }
    static func make(alpha a:[UInt8],width w:Int,height h:Int,cancellation:Cancellation?=nil)throws->WhiteInk {
        guard a.count==w*h,let provider=CGDataProvider(data:Data(a) as CFData),let mask=CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:w,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.none.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent)else{throw AppFailure("白墨蒙版失败。")}
        var rgba=[UInt8](repeating:0,count:w*h*4)
        for i in 0..<a.count {
            if i%1048576==0 && cancellation?.cancelled==true{throw AppFailure("CANCELLED")}
            rgba[i*4+3]=a[i]
        }
        guard let p=CGDataProvider(data:Data(rgba) as CFData),let image=CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue),provider:p,decode:nil,shouldInterpolate:true,intent:.defaultIntent)else{throw AppFailure("白墨预览失败。")}
        return WhiteInk(width:w,height:h,alpha:a,mask:mask,preview:image,vectorPath:nil)
    }
}
final class WhiteEngine {
    private var sourceID:UUID?,sourceAlpha:[UInt8]=[],cache:[String:WhiteInk]=[:]
    private var paintedCache:(key:String,ink:WhiteInk)?
    func build(_ art:LoadedArtwork,settings s:StandeeSettings,box:StandeeGeometry.Rect,clipPath:String?=nil,cancellation:Cancellation?=nil)throws->WhiteInk{
        if cancellation?.cancelled==true{throw AppFailure("CANCELLED")}
        let ink=try base(art,settings:s,box:box,cancellation:cancellation)
        guard !s.whiteStrokes.isEmpty else{paintedCache=nil;return ink}
        guard let path=clipPath else{throw AppFailure("手动补白缺少主体边界。")}
        let key="\(art.id)|\(s.whiteInset)|\(s.whiteFill)|\(s.whiteFollowsAlpha)|\(s.threshold)|\(box.x)|\(box.y)|\(box.width)|\(box.height)|\(path)|"+s.whiteStrokes.map{$0.id.uuidString}.joined(separator:",")
        if let hit=paintedCache,hit.key==key{return hit.ink}
        var alpha=ink.alpha
        let body=try SVGPath.parse(path)
        let sx=Double(ink.width)/box.width,sy=Double(ink.height)/box.height
        var t=CGAffineTransform(a:sx,b:0,c:0,d:sy,tx:-box.x*sx,ty:-box.y*sy)
        guard let clip=body.copy(using:&t)else{throw AppFailure("补白边界转换失败。")}
        let ok:Bool=try alpha.withUnsafeMutableBytes{memory in
            guard let c=CGContext(data:memory.baseAddress,width:ink.width,height:ink.height,bitsPerComponent:8,bytesPerRow:ink.width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue)else{return false}
            // Match the top-down source pixel rows and the flipped AppKit canvas.
            c.translateBy(x:0,y:CGFloat(ink.height));c.scaleBy(x:1,y:-1)
            c.addPath(clip);c.clip(using:.evenOdd)
            c.setFillColor(gray:1,alpha:1);c.setStrokeColor(gray:1,alpha:1)
            for stroke in s.whiteStrokes {
                if cancellation?.cancelled==true{throw AppFailure("CANCELLED")}
                stroke.draw(in:c,rect:CGRect(x:0,y:0,width:ink.width,height:ink.height))
            }
            return true
        }
        guard ok else{throw AppFailure("手动补白失败。")}
        let result=try WhiteInk.make(alpha:alpha,width:ink.width,height:ink.height,cancellation:cancellation)
        paintedCache=(key,result);return result
    }
    private func base(_ art:LoadedArtwork,settings s:StandeeSettings,box:StandeeGeometry.Rect,cancellation:Cancellation?=nil)throws->WhiteInk{
        let key="\(art.id)|\(s.whiteInset)|\(s.whiteFill)|\(s.whiteFollowsAlpha)|\(s.threshold)|\(box.height)"
        if let hit=cache[key]{return hit}
        func check()throws{if cancellation?.cancelled==true{throw AppFailure("CANCELLED")}}
        try check();if sourceID != art.id{sourceAlpha=try LoadedArtwork.extractAlpha(art.image);sourceID=art.id;cache.removeAll();paintedCache=nil}
        let w=art.image.width,h=art.image.height;var a=sourceAlpha
        if !s.whiteFollowsAlpha {let threshold=max(1,Int((s.threshold*2.55).rounded()));for i in 0..<a.count{let value=Int(a[i]);a[i]=value>=threshold ? 255:UInt8(min(255,value*255/threshold))}}
        try check();if s.whiteFill{a.withUnsafeMutableBufferPointer{p in acrylic_fill_holes(p.baseAddress,Int32(w),Int32(h),128)}}
        let radius=s.whiteInset*Double(h)/box.height
        if radius>0.001{
            let r=Int(ceil(radius)),kw=2*r+1,pw=w+2*r,ph=h+2*r;var padded=[UInt8](repeating:0,count:pw*ph),out=[UInt8](repeating:0,count:w*h)
            for y in 0..<h{padded.replaceSubrange((y+r)*pw+r..<(y+r)*pw+r+w,with:a[y*w..<(y+1)*w])}
            var kernel=[UInt8](repeating:0,count:kw*kw)
            for y in 0..<kw{for x in 0..<kw{kernel[y*kw+x]=UInt8((max(0,min(255,255*(1-max(0,hypot(Double(x-r),Double(y-r))-radius))))).rounded())}}
            let err=padded.withUnsafeMutableBytes{src in out.withUnsafeMutableBytes{dst in kernel.withUnsafeBufferPointer{k->vImage_Error in
                var sb=vImage_Buffer(data:src.baseAddress,height:UInt(ph),width:UInt(pw),rowBytes:pw),db=vImage_Buffer(data:dst.baseAddress,height:UInt(h),width:UInt(w),rowBytes:w)
                return vImageErode_Planar8(&sb,&db,UInt(r),UInt(r),k.baseAddress!,UInt(kw),UInt(kw),vImage_Flags(kvImageEdgeExtend))
            }}}
            guard err==kvImageNoError else{throw AppFailure("白墨内缩失败：\(err)")};a=out
        }
        try check();guard a.contains(where:{$0>0})else{throw AppFailure("内缩后白墨为空，请减小内缩。")}
        let result=try WhiteInk.make(alpha:a,width:w,height:h,cancellation:cancellation);cache.removeAll();cache[key]=result;return result
    }
}
