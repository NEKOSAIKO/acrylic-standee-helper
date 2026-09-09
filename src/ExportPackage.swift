import AppKit

struct PreparedExport {
    let folder:URL, job:URL, launcher:URL, output:URL
}

enum ExportPackage {
    static func quote(_ s:String) -> String { let d=try! JSONSerialization.data(withJSONObject:[s],options:[.fragmentsAllowed,.withoutEscapingSlashes]); let j=String(data:d,encoding:.utf8)!; return String(j.dropFirst().dropLast()) }
    static func roundedRect(_ x:Double,_ y:Double,_ w:Double,_ h:Double,_ r:Double) -> String { ExportLayout.roundedRect(x,y,w,h,r) }
    static func ellipse(_ w:Double,_ h:Double) -> String { ExportLayout.ellipse(w,h) }
    static func make(art:LoadedArtwork,result:GeometryResult,settings:StandeeSettings,white:WhiteInk,output:URL,helper:URL) throws -> PreparedExport {
        let fm=FileManager.default
        let layout = try ExportLayout.make(result:result,settings:settings)
        guard output.pathExtension.lowercased()=="ai" else {throw AppFailure("输出文件需要使用 .ai 扩展名。")}
        guard !fm.fileExists(atPath:output.path) else {throw AppFailure("同名文件已经存在，请另存为新名称。")}
        let folder=output.deletingLastPathComponent().appendingPathComponent(output.deletingPathExtension().lastPathComponent+"-制版数据-"+String(UUID().uuidString.prefix(6)),isDirectory:true)
        try fm.createDirectory(at:folder,withIntermediateDirectories:true)
        let asset=folder.appendingPathComponent("artwork-cmyk.pdf"),helperCopy=folder.appendingPathComponent("illustrator-helper.jsx")
        let color=try CMYKPDF.makeCMYKImage(art.image)
        try CMYKPDF.imagePage(color,widthMm:result.model.imageBox.width,heightMm:result.model.imageBox.height).write(to:asset,options:.withoutOverwriting)
        let whiteFile=folder.appendingPathComponent("white-k100.pdf"),infoFile=folder.appendingPathComponent("factory-sheet.pdf")
        try white.pdfData(widthMm:result.model.imageBox.width,heightMm:result.model.imageBox.height).write(to:whiteFile,options:.withoutOverwriting)
        try FactorySheet.data(art:art,result:result,settings:settings,white:white,color:color).write(to:infoFile,options:.withoutOverwriting)
        try fm.copyItem(at:helper,to:helperCopy)
        let g=result.json
        guard let image=g["imageBox"] as? [String:Double] else {throw AppFailure("输出尺寸缺失。")}
        let slots=layout.slots.map { ["path":$0.path,"xMm":layout.baseX,"yMm":layout.baseY] as [String:Any] }
        let body:[String:Any]=["path":result.model.bodyPath,"xMm":layout.bodyX,"yMm":layout.bodyY]
        let tabReferences = result.model.tabs.map { ["path":$0.referencePath,"xMm":layout.bodyX,"yMm":layout.bodyY] as [String:Any] }
        let whiteSpec:[String:Any]=white.vectorPath.map{["path":$0,"xMm":layout.bodyX,"yMm":layout.bodyY,"visible":false]} ?? ["imagePath":(whiteFile.path as String),"xMm":layout.bodyX+result.model.imageBox.x,"yMm":layout.bodyY+result.model.imageBox.y,"widthMm":result.model.imageBox.width,"heightMm":result.model.imageBox.height,"visible":false]
        let infoSpec:[String:Any]=["imagePath":(infoFile.path as String),"widthMm":FactorySheet.width,"heightMm":FactorySheet.height]
        let base:[String:Any]=["path":layout.basePath,"xMm":layout.baseX,"yMm":layout.baseY]
        guard let ix=image["x"],let iy=image["y"],let iw=image["width"],let ih=image["height"] else {throw AppFailure("彩稿定位尺寸无效。")}
        let artworkSpec:[String:Any] = ["path":(asset.path as String),"xMm":layout.bodyX+ix,"yMm":layout.bodyY+iy,"widthMm":iw,"heightMm":ih]
        let job:[String:Any]=["schemaVersion":3,"outputPath":(output.path as String),"document":["widthMm":layout.pageWidth,"heightMm":layout.pageHeight],"artwork":artworkSpec,"body":body,"tabReferences":tabReferences,"white":whiteSpec,"factorySheet":infoSpec,"base":base,"slots":slots,"cutStrokeMm":0.1,"warnings":g["warnings"] ?? [],"settings":settings.options]
        guard JSONSerialization.isValidJSONObject(job) else {
            var invalid:[String]=[]
            func inspect(_ value:Any,_ key:String){
                if let dict=value as? [String:Any]{for (k,v) in dict{inspect(v,key+"."+k)};return}
                if let list=value as? [Any]{for (i,v) in list.enumerated(){inspect(v,key+"["+String(i)+"]")};return}
                if !JSONSerialization.isValidJSONObject(["value":value]){invalid.append(key+" ("+String(describing:type(of:value))+")")}
            }
            inspect(job,"job");throw AppFailure("输出资料格式错误："+invalid.joined(separator:", "))
        }
        let jobURL=folder.appendingPathComponent("standee-job.json"),launcher=folder.appendingPathComponent("在Illustrator中生成.jsx")
        try JSONSerialization.data(withJSONObject:job,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]).write(to:jobURL,options:.atomic)
        let code="#target illustrator\n$.evalFile(new File(\(quote(helperCopy.path))));\nAcrylicStandeeImport.run(\(quote(jobURL.path)));\n"
        try code.write(to:launcher,atomically:true,encoding:.utf8)
        let note="本资料包由亚克力立牌助手生成。\n在 Illustrator 中选择：文件 → 脚本 → 其他脚本，打开「在Illustrator中生成.jsx」。\n脚本会创建新 CMYK 文档并另存为 \(output.lastPathComponent)，不修改原有文档。\n白墨图层使用 K100，默认隐藏；刀线为贝塞尔矢量，白墨默认保留原图像素蒙版。AI 含独立制版说明画板。\n04 插脚位置参考：青蓝色空心矩形，只标识位置，不参与印刷或直接切割，未与主体刀线合并。工厂须按实际工艺调整插脚并连接主体。\n当前几何仍需生产复核；尤其是插脚连接、插槽圆端/避空、刀具补偿及配合公差。\n"
        try note.write(to:folder.appendingPathComponent("使用说明.txt"),atomically:true,encoding:.utf8)
        return PreparedExport(folder:folder,job:jobURL,launcher:launcher,output:output)
    }
    static func sendToIllustrator(_ prepared:PreparedExport) throws -> String {
        func asQuote(_ s:String)->String {"\""+s.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"")+"\""}
        let source="with timeout of 180 seconds\ntell application id \"com.adobe.illustrator\"\nactivate\ndo javascript (POSIX file \(asQuote(prepared.launcher.path)))\nend tell\nend timeout"
        var info:NSDictionary?
        guard let script=NSAppleScript(source:source) else {throw AppFailure("无法创建 Illustrator 连接。")}
        let reply=script.executeAndReturnError(&info)
        if let info=info {throw AppFailure(info[NSAppleScript.errorMessage] as? String ?? "Illustrator 连接失败；可改用资料包中的脚本手动生成。")}
        guard FileManager.default.fileExists(atPath:prepared.output.path) else {throw AppFailure("Illustrator 未确认保存文件。请查看生成资料包中的报告。")}
        return reply.stringValue ?? "已生成 CMYK 文件。"
    }
}
