import AppKit
import CoreText
struct FactorySheet {
    static let width=297.0,height=210.0
    static func data(art:LoadedArtwork,result:GeometryResult,settings:StandeeSettings,white:WhiteInk,color:CGImage)throws->Data{
        let d=NSMutableData();var box=CGRect(x:0,y:0,width:width*72/25.4,height:height*72/25.4)
        guard let consumer=CGDataConsumer(data:d as CFMutableData),let c=CGContext(consumer:consumer,mediaBox:&box,nil)else{throw AppFailure("说明页创建失败。")}
        c.beginPDFPage(nil);draw(c,art:art,result:result,settings:settings,white:white,color:color);c.endPDFPage();c.closePDF();return d as Data
    }
    static func draw(_ c:CGContext,art:LoadedArtwork,result r:GeometryResult,settings s:StandeeSettings,white:WhiteInk,color:CGImage){
        c.saveGState();c.translateBy(x:0,y:height*72/25.4);c.scaleBy(x:72/25.4,y:-72/25.4)
        let prior=NSGraphicsContext.current;NSGraphicsContext.current=NSGraphicsContext(cgContext:c,flipped:true);defer{NSGraphicsContext.current=prior;c.restoreGState()}
        func ink(_ k:CGFloat)->NSColor{NSColor(deviceCyan:0,magenta:0,yellow:0,black:k,alpha:1)}
        func rect(_ x:Double,_ y:Double,_ w:Double,_ h:Double,_ fill:[CGFloat]){c.setFillColorSpace(CGColorSpaceCreateDeviceCMYK());c.setFillColor(fill);c.fill(CGRect(x:x,y:y,width:w,height:h))}
        func text(_ value:String,_ x:Double,_ y:Double,_ w:Double,_ h:Double,_ size:CGFloat=3.25,_ bold:Bool=false,_ k:CGFloat=0.85){
            let para=NSMutableParagraphStyle();para.lineSpacing=1.5;para.lineBreakMode = .byWordWrapping
            let attr=NSAttributedString(string:value,attributes:[.font:NSFont.systemFont(ofSize:size,weight:bold ? .semibold:.regular),.paragraphStyle:para])
            let framesetter=CTFramesetterCreateWithAttributedString(attr),box=CGPath(rect:CGRect(x:0,y:0,width:w,height:h),transform:nil)
            let frame=CTFramesetterCreateFrame(framesetter,CFRange(location:0,length:attr.length),box,nil),lines=CTFrameGetLines(frame) as! [CTLine]
            var origins=[CGPoint](repeating:.zero,count:lines.count);CTFrameGetLineOrigins(frame,CFRange(location:0,length:0),&origins)
            c.saveGState();c.translateBy(x:x,y:y+h);c.scaleBy(x:1,y:-1);c.clip(to:CGRect(x:0,y:0,width:w,height:h));c.setFillColorSpace(CGColorSpaceCreateDeviceCMYK());c.setFillColor([0,0,0,k,1])
            for (i,line) in lines.enumerated(){for run in CTLineGetGlyphRuns(line) as! [CTRun]{
                let attrs=CTRunGetAttributes(run) as NSDictionary,font=attrs[kCTFontAttributeName] as! CTFont,n=CTRunGetGlyphCount(run)
                var glyphs=[CGGlyph](repeating:0,count:n),positions=[CGPoint](repeating:.zero,count:n)
                CTRunGetGlyphs(run,CFRange(location:0,length:0),&glyphs);CTRunGetPositions(run,CFRange(location:0,length:0),&positions)
                for j in 0..<n{if let outline=CTFontCreatePathForGlyph(font,glyphs[j],nil){var t=CGAffineTransform(translationX:origins[i].x+positions[j].x,y:origins[i].y+positions[j].y);if let path=outline.copy(using:&t){c.addPath(path)}}}
                c.fillPath()
            }};c.restoreGState()
        }
        rect(0,0,width,height,[0,0,0,0,1]);rect(0,0,width,31,[0.78,0.70,0.10,0.15,1]);
        // White title is process CMYK 0,0,0,0.
        text("ACRYLIC / 制版说明",12,8,220,12,7,true,0);text("供印刷与加工核对 · 说明页不作为印刷图稿",13,23,220,6,3,false,0)
        let name=s.jobName.isEmpty ? art.url.deletingPathExtension().lastPathComponent:s.jobName
        text(name,12,38,182,12,5.8,true);text("版本 0.2.7  /  100% 毫米尺寸",212,40,73,8,3,false)
        rect(12,55,84,130,[0.025,0.018,0,0.015,1]);text("生产规格",17,60,72,9,4.3,true)
        let g=r.model,dpi=Double(art.image.height)/g.imageBox.height*25.4
        let spec=[String(format:"主体：%0.1f × %0.1f mm",g.widthMm,g.heightMm),String(format:"参考高：%0.1f mm（含位置框）",g.totalHeightMm),String(format:"立牌厚度：%0.2f mm",s.thickness),String(format:"最小透明边：%0.2f mm",s.offset),"底座：\(s.baseShape=="circle" ? "圆形":s.baseShape=="square" ? "正方形":"长方形")",String(format:"底座：%0.1f × %0.1f × %0.2f mm",s.baseWidth,s.baseHeight,s.tabDepth),String(format:"插脚参考：%d 个，宽 %0.2f / 深 %0.2f mm",s.tabCount,s.tabWidth,s.tabDepth),String(format:"插槽：%0.2f × %0.2f mm",s.tabWidth+s.fit,s.thickness+s.fit),String(format:"白墨：K100，内缩 %0.2f mm",s.whiteInset),"白墨模式：\(s.whiteFollowsAlpha ? "跟随原图透明度":"实白底")", "白墨输出：\(s.whiteVector ? "矢量实白":"原图像素蒙版")", "手动补白：\(s.whiteStrokes.count) 笔（已合入白墨）", "原图：\(art.image.width) × \(art.image.height) px",String(format:"有效分辨率：约 %0.0f ppi",dpi),"色彩：CMYK / Generic CMYK", "方向：原稿方向，未自动镜像"]
        text(spec.joined(separator:"\n"),17,74,73,109,3.0)
        text("图层与文件用途",104,58,110,10,4.3,true)
        let rows=[("01 彩色图稿","CMYK 彩稿；按成品尺寸定位，保留原像素。"),("02 白墨 K100","黑色表示白墨版，不作为黑色图案印刷。"),("03 主体刀线","洋红线仅为主体边界，不含插脚；不印刷。"),("04 插脚位置参考","青蓝空心框仅定位，由工厂调整并连接主体。"),("05 底座与插槽","透明底座不铺白墨；插槽尺寸见左侧。"),("06 制版说明","独立说明画板，不随生产图稿输出。")]
        for (i,row) in rows.enumerated(){let y=73.0+Double(i)*13;rect(104,y-1,181,12,[0,0,0,i%2==0 ? 0.025:0,1]);text(row.0,107,y,41,10,3.15,true);text(row.1,151,y,129,11,3.05)}
        text("投产前核对",105,153,174,9,4.2,true)
        text("插脚框不印刷、不直接切割；工厂须调整插脚并与主体连接。\n□ 彩稿 / 白墨对位  □ 印刷方向  □ 主体跨接  □ 插脚与插槽配合\n文件未应用刀具中心补偿；插槽内角、板厚与公差须复核。",105,165,179,23,3.05)
        let notes=s.notes.isEmpty ? "工厂如需不同 ICC、白墨或刀线命名，请在生产前确认。":s.notes
        text("备注："+notes,13,190,270,11,3.0)
        text("生成自当前参数 · 说明不构成已完成生产审核的声明",13,202,270,5,2.7,false,0.55)
    }
}
