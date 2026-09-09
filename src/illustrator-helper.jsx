#target illustrator
/* Acrylic Standee local application handoff. ES3 / ExtendScript.
   No JSON eval, no modification of existing documents, no overwrite.
   Load with $.evalFile(), then call
   AcrylicStandeeImport.run('/absolute/job.json'). No autorun on load. */
var AcrylicIllustrator = (function () {
    var PT = 72 / 25.4;
    function fail(message) { throw new Error(message); }
    function number(value, label, min, max) {
        if (typeof value !== 'number' || !isFinite(value) || value < min || value > max) fail(label + ' 数值无效');
        return value;
    }
    function own(obj, key) { return Object.prototype.hasOwnProperty.call(obj, key); }
    function array(value) { return Object.prototype.toString.call(value) === '[object Array]'; }
    function parseJSON(text) {
        var i = 0, depth = 0;
        if (typeof text !== 'string' || text.length > 10000000) fail('任务文件过大或格式无效');
        if (text.charCodeAt(0) === 65279) text = text.substring(1);
        function ws() { while (i < text.length && /[ \t\r\n]/.test(text.charAt(i))) i++; }
        function string() {
            var out = '', ch, h, escapes = {'"':'"', '\\':'\\', '/':'/', 'b':'\b', 'f':'\f', 'n':'\n', 'r':'\r', 't':'\t'};
            if (text.charAt(i++) !== '"') fail('JSON 字符串格式错误');
            while (i < text.length) {
                ch = text.charAt(i++);
                if (ch === '"') return out;
                if (ch === '\\') {
                    ch = text.charAt(i++);
                    if (ch === 'u') { h = text.substr(i, 4); if (!/^[0-9a-fA-F]{4}$/.test(h)) fail('JSON Unicode 转义错误'); out += String.fromCharCode(parseInt(h, 16)); i += 4; }
                    else if (own(escapes, ch)) out += escapes[ch];
                    else fail('JSON 转义错误');
                } else { if (ch.charCodeAt(0) < 32) fail('JSON 控制字符无效'); out += ch; }
            }
            fail('JSON 字符串未闭合');
        }
        function value() {
            var ch, result, key, match;
            ws(); if (++depth > 40) fail('JSON 嵌套过深'); ch = text.charAt(i);
            if (ch === '"') result = string();
            else if (ch === '{') {
                result = {}; i++; ws();
                if (text.charAt(i) === '}') i++;
                else while (true) {
                    ws(); if (text.charAt(i) !== '"') fail('JSON 属性格式错误'); key = string();
                    if (key === '__proto__' || key === 'prototype' || key === 'constructor' || own(result, key)) fail('JSON 重复或保留属性');
                    ws(); if (text.charAt(i++) !== ':') fail('JSON 缺少冒号'); result[key] = value(); ws(); ch = text.charAt(i++);
                    if (ch === '}') break; if (ch !== ',') fail('JSON 对象格式错误');
                }
            } else if (ch === '[') {
                result = []; i++; ws();
                if (text.charAt(i) === ']') i++;
                else while (true) { result.push(value()); if (result.length > 20000) fail('JSON 数组过大'); ws(); ch = text.charAt(i++); if (ch === ']') break; if (ch !== ',') fail('JSON 数组格式错误'); }
            } else if (text.substr(i, 4) === 'true') { result = true; i += 4; }
            else if (text.substr(i, 5) === 'false') { result = false; i += 5; }
            else if (text.substr(i, 4) === 'null') { result = null; i += 4; }
            else { match = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/.exec(text.substring(i)); if (!match) fail('JSON 值格式错误'); result = Number(match[0]); if (!isFinite(result)) fail('JSON 数字溢出'); i += match[0].length; }
            depth--; return result;
        }
        var result = value(); ws(); if (i !== text.length) fail('JSON 尾部含无效内容'); return result;
    }
    function point(x, y) { return {anchor:[x,y], left:[x,y], right:[x,y]}; }
    function same(a, b) { return Math.abs(a[0]-b[0]) < 0.0000001 && Math.abs(a[1]-b[1]) < 0.0000001; }
    function parsePath(d) {
        if (typeof d !== 'string' || !d.length || d.length > 4000000) fail('刀线路径为空或过大');
        var token = /[MLHVQCZmlhvqcz]|[-+]?(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][-+]?[0-9]+)?/g;
        var tokens = [], match, end = 0, i = 0, cmd = '', paths = [], points = null, x = 0, y = 0, total = 0;
        while ((match = token.exec(d)) !== null) { if (!/^[\s,]*$/.test(d.substring(end, match.index))) fail('刀线包含不支持的 SVG 指令'); tokens.push(match[0]); end = token.lastIndex; }
        if (!/^[\s,]*$/.test(d.substring(end))) fail('刀线尾部格式错误');
        function next() { if (i >= tokens.length || /^[a-zA-Z]$/.test(tokens[i])) fail('刀线坐标数量不足'); return number(Number(tokens[i++]), '刀线坐标', -10000, 10000); }
        function add(nx, ny, c1, c2) {
            number(nx,'刀线 X',-10000,10000); number(ny,'刀线 Y',-10000,10000);
            var p = point(nx, ny);
            if (c1) { points[points.length-1].right = c1; p.left = c2; }
            points.push(p); x = nx; y = ny; if (++total > 50000) fail('刀线节点过多');
        }
        while (i < tokens.length) {
            if (/^[a-zA-Z]$/.test(tokens[i])) cmd = tokens[i++];
            else if (!cmd) fail('刀线缺少指令');
            var upper = cmd.toUpperCase(), relative = upper !== cmd, nx, ny, qx, qy, c1, c2, ox = x, oy = y;
            if (upper === 'Z') {
                if (!points || points.length < 3) fail('闭合刀线至少需要三个节点');
                if (same(points[points.length-1].anchor, points[0].anchor)) { points[0].left = points[points.length-1].left; points.pop(); }
                if (points.length < 3) fail('闭合刀线节点不足');
                x = points[0].anchor[0]; y = points[0].anchor[1]; paths.push(points); points = null; cmd = ''; if (paths.length > 1024) fail('子路径过多'); continue;
            }
            if (upper === 'M') {
                if (points) fail('所有刀线与白墨子路径必须使用 Z 闭合');
                nx = next() + (relative ? ox : 0); ny = next() + (relative ? oy : 0); points = [point(nx,ny)]; x = nx; y = ny; total++; cmd = relative ? 'l' : 'L'; continue;
            }
            if (!points) fail('刀线必须以 M 开始');
            if (upper === 'L') { nx = next() + (relative ? ox : 0); ny = next() + (relative ? oy : 0); add(nx,ny); }
            else if (upper === 'H') add(next() + (relative ? ox : 0), y);
            else if (upper === 'V') add(x, next() + (relative ? oy : 0));
            else if (upper === 'Q') {
                qx = next() + (relative ? ox : 0); qy = next() + (relative ? oy : 0); nx = next() + (relative ? ox : 0); ny = next() + (relative ? oy : 0);
                add(nx,ny,[ox + (qx-ox)*2/3, oy + (qy-oy)*2/3],[nx + (qx-nx)*2/3, ny + (qy-ny)*2/3]);
            } else if (upper === 'C') {
                c1 = [next() + (relative ? ox : 0), next() + (relative ? oy : 0)]; c2 = [next() + (relative ? ox : 0), next() + (relative ? oy : 0)];
                nx = next() + (relative ? ox : 0); ny = next() + (relative ? oy : 0); add(nx,ny,c1,c2);
            } else fail('不支持的刀线指令 ' + cmd);
        }
        if (points || !paths.length) fail('所有刀线与白墨子路径必须使用 Z 闭合');
        return paths;
    }
    function absolute(value, label) {
        if (typeof value !== 'string' || /[\x00\r\n]/.test(value) || !(/^(\/|[A-Za-z]:[\\\/])/.test(value))) fail(label + '必须是本地绝对路径');
        return value;
    }
    function xy(value, label) { return number(value === undefined ? 0 : value, label, -10000, 10000); }
    function shape(value, label, optional) {
        if (!value && optional) return null;
        if (!value || typeof value !== 'object' || array(value)) fail(label + '格式错误');
        return {paths:parsePath(value.path), x:xy(value.xMm, label+' X'), y:xy(value.yMm, label+' Y'), visible:value.visible !== false};
    }
    function validate(job) {
        if (!job || job.schemaVersion !== 1 && job.schemaVersion !== 2 && job.schemaVersion !== 3) fail('不支持的任务格式版本');
        var d = job.document, art = job.artwork, result, i;
        if (!d || !art) fail('缺少画板或图稿参数');
        result = {
            width:number(d.widthMm,'画板宽度',1,1800), height:number(d.heightMm,'画板高度',1,1800),
            outputPath:absolute(job.outputPath,'输出路径'),
            imagePath:absolute(art.path,'图稿路径'),
            artX:xy(art.xMm,'图稿 X'), artY:xy(art.yMm,'图稿 Y'),
            artWidth:number(art.widthMm,'图稿宽度',0.1,1800), artHeight:number(art.heightMm,'图稿高度',0.1,1800),
            dpi:number(art.resolutionDpi === undefined ? 300 : art.resolutionDpi,'图稿分辨率',72,1200),
            body:shape(job.body,'主体刀线',false), white:job.white && job.white.imagePath ? null:shape(job.white,'白墨',true), base:shape(job.base,'底座刀线',true), slots:[], tabReferences:[],
            stroke:number(job.cutStrokeMm === undefined ? 0.1 : job.cutStrokeMm,'刀线线宽',0.01,1), closeAfterSave:job.closeAfterSave === true
        };
        if (result.white) result.white.visible = job.white.visible === true;
        function imageSpec(v,label){return {path:absolute(v.imagePath,label),x:xy(v.xMm,label+' X'),y:xy(v.yMm,label+' Y'),width:number(v.widthMm,label+' 宽',.01,1800),height:number(v.heightMm,label+' 高',.01,1800)};}
        result.whiteImage=job.white && job.white.imagePath?imageSpec(job.white,'白墨蒙版'):null;
        result.factorySheet=job.factorySheet?imageSpec(job.factorySheet,'说明画板'):null;
        result.verificationWhitePDF=job.verificationWhitePDF?absolute(job.verificationWhitePDF,'白墨校验路径'):null;
        if (!/\.ai$/i.test(result.outputPath)) fail('输出文件必须以 .ai 结尾');
        if (!/\.(png|tif|tiff|psd|jpg|jpeg|pdf)$/i.test(result.imagePath)) fail('图稿必须为 PNG、TIFF、PSD 或 JPEG');
        if (job.slots !== undefined && !array(job.slots)) fail('插槽必须是数组');
        if (job.slots && job.slots.length > 20) fail('插槽过多');
        for (i=0; job.slots && i<job.slots.length; i++) result.slots.push(shape(job.slots[i],'插槽',false));
        if (job.schemaVersion === 3 && (!array(job.tabReferences) || job.tabReferences.length < 1 || job.tabReferences.length > 2)) fail('插脚参考框必须为 1 或 2 个');
        if (job.tabReferences !== undefined && !array(job.tabReferences)) fail('插脚参考框必须是数组');
        if (job.tabReferences && job.tabReferences.length > 2) fail('插脚参考框过多');
        for (i=0; job.tabReferences && i<job.tabReferences.length; i++) {
            var reference=shape(job.tabReferences[i],'插脚位置参考',false);
            if(reference.paths.length!==1 || reference.paths[0].length!==4) fail('插脚参考框必须是独立四角矩形');
            var points=reference.paths[0];
            for(var pi=0;pi<4;pi++) {
                var point=points[pi],nextPoint=points[(pi+1)%4];
                if(point.left[0]!==point.anchor[0] || point.left[1]!==point.anchor[1] || point.right[0]!==point.anchor[0] || point.right[1]!==point.anchor[1]) fail('插脚参考框必须是直线矩形');
                var dx=nextPoint.anchor[0]-point.anchor[0],dy=nextPoint.anchor[1]-point.anchor[1];
                if((dx===0)===(dy===0)) fail('插脚参考框必须是轴向矩形');
                var opposite=points[(pi+2)%4].anchor;
                if(point.anchor[0]===opposite[0] || point.anchor[1]===opposite[1]) fail('插脚参考框尺寸无效');
            }
            result.tabReferences.push(reference);
        }
        return result;
    }
    function readJob(path) {
        var file = new File(absolute(path,'任务路径')), content;
        if (!file.exists) fail('任务文件不存在');
        if (file.length > 10000000) fail('任务文件过大');
        file.encoding = 'UTF-8'; if (!file.open('r')) fail('无法读取任务文件');
        try { content = file.read(); } finally { file.close(); }
        return validate(parseJSON(content));
    }
    function color(c,m,y,k) { var value = new CMYKColor(); value.cyan=c; value.magenta=m; value.yellow=y; value.black=k; return value; }
    function transform(p, shape, height) { return [(p[0]+shape.x)*PT, (height-p[1]-shape.y)*PT]; }
    function putShape(layer, data, height, fill, stroke, width, name) {
        var owner = data.paths.length > 1 ? layer.compoundPathItems.add() : layer;
        if (owner !== layer) owner.name = name;
        var i,j,item,node,p;
        for (i=0;i<data.paths.length;i++) {
            item = owner.pathItems.add(); item.name = name + (data.paths.length>1 ? ' '+(i+1) : '');
            item.closed=true; item.evenodd=true; item.filled=!!fill; item.stroked=!!stroke;
            if (fill) { item.fillColor=fill; item.fillOverprint=false; }
            if (stroke) { item.strokeColor=stroke; item.strokeWidth=width*PT; item.strokeOverprint=false; }
            for (j=0;j<data.paths[i].length;j++) {
                node=data.paths[i][j]; p=item.pathPoints.add(); p.anchor=transform(node.anchor,data,height); p.leftDirection=transform(node.left,data,height); p.rightDirection=transform(node.right,data,height); p.pointType=PointType.CORNER;
            }
        }
        layer.visible=data.visible;
    }
    function stringify(value) {
        var parts=[],i,k;
        if (value===null) return 'null';
        if (typeof value==='string') return '"'+value.replace(/[\\"\x00-\x1f]/g,function(ch){if(ch==='\\')return '\\\\';if(ch==='"')return '\\"';var code=ch.charCodeAt(0).toString(16);return '\\u'+('0000'+code).slice(-4);})+'"';
        if (typeof value==='number' || typeof value==='boolean') return String(value);
        if (array(value)) {for(i=0;i<value.length;i++)parts.push(stringify(value[i]));return '['+parts.join(',')+']';}
        for(k in value)if(own(value,k))parts.push(stringify(k)+':'+stringify(value[k]));
        return '{'+parts.join(',')+'}';
    }
    function run(path) {
        var priorPDFBox=null;
        var job=readJob(path), out=new File(job.outputPath), reportFile=new File(job.outputPath+'.report.json'), source=new File(job.imagePath), doc=null, saved=false, priorCoordinates=app.coordinateSystem;
        if (reportFile.exists) fail('同名校验报告已存在，请选择新的文件名。');
        if (out.exists) fail('输出文件已存在，请在应用中选择新的文件名；未覆盖原文件。');
        if (!out.parent.exists) fail('输出文件夹不存在');
        if (!source.exists) fail('图稿文件不存在');
        try {
            app.coordinateSystem=CoordinateSystem.DOCUMENTCOORDINATESYSTEM;
            if(job.whiteImage || /\.pdf$/i.test(job.imagePath)) {priorPDFBox=app.preferences.PDFFileOptions.pDFCropToBox;app.preferences.PDFFileOptions.pDFCropToBox=PDFBoxType.PDFMEDIABOX;}
            function placePDF(layer,file,x,y,w,h,name){var asset=new File(file);if(!asset.exists)fail(name+'文件缺失');var p=doc.placedItems.add();p.file=asset;p.move(layer,ElementPlacement.PLACEATBEGINNING);p.width=w*PT;p.height=h*PT;p.position=[x*PT,(job.height-y)*PT];p.name=name;p.embed();}

            var preset=new DocumentPreset();
            preset.colorMode=DocumentColorSpace.CMYK;preset.units=RulerUnits.Millimeters;
            preset.width=job.width*PT;preset.height=job.height*PT;preset.numArtboards=1;
            doc=app.documents.addDocument('',preset,false);
            if(doc.rulerUnits!==RulerUnits.Millimeters)fail('文档毫米单位校验失败');
            doc.artboards[0].artboardRect=[0,job.height*PT,job.width*PT,0];
            var ink=doc.layers[0]; ink.name='02 白墨 K100';
            if (job.white) putShape(ink,job.white,job.height,color(0,0,0,100),null,0,'白墨');
            else if(job.whiteImage){placePDF(ink,job.whiteImage.path,job.whiteImage.x,job.whiteImage.y,job.whiteImage.width,job.whiteImage.height,'白墨 K100 原图蒙版');ink.visible=false;}
            else ink.visible=false;
            var artwork=doc.layers.add(); artwork.name='01 彩色图稿 CMYK';
            var raster=null;
            if(/\.pdf$/i.test(job.imagePath)){placePDF(artwork,job.imagePath,job.artX,job.artY,job.artWidth,job.artHeight,'原像素 CMYK 彩稿');}
            else {
                var placed=doc.placedItems.add();placed.file=source;placed.move(artwork,ElementPlacement.PLACEATBEGINNING);placed.width=job.artWidth*PT;placed.height=job.artHeight*PT;placed.position=[job.artX*PT,(job.height-job.artY)*PT];
                var opts=new RasterizeOptions();opts.colorModel=RasterizationColorModel.DEFAULTCOLORMODEL;opts.resolution=job.dpi;opts.transparency=true;opts.padding=0;opts.clippingMask=false;opts.antiAliasingMethod=AntiAliasingMethod.ARTOPTIMIZED;
                raster=doc.rasterize(placed,placed.geometricBounds,opts);raster.name='嵌入 CMYK 彩稿';
                if(raster.imageColorSpace!==ImageColorSpace.CMYK || !raster.embedded)fail('CMYK 彩稿嵌入失败');
            }
            if (doc.documentColorSpace !== DocumentColorSpace.CMYK) fail('文档色彩模式校验失败');
            var cut=doc.layers.add(); cut.name='03 主体刀线'; putShape(cut,job.body,job.height,null,color(0,100,0,0),job.stroke,'主体刀线（成品边界）');
            if(job.tabReferences.length){var refs=doc.layers.add();refs.name='04 插脚位置参考（工厂调整）';for(var ti=0;ti<job.tabReferences.length;ti++)putShape(refs,job.tabReferences[ti],job.height,null,color(100,0,0,0),job.stroke,'插脚位置参考 '+(ti+1)+'（不作刀线）');}
            var base=doc.layers.add(); base.name=job.tabReferences.length?'05 底座与插槽刀线':'04 底座与插槽刀线';
            if (job.base) putShape(base,job.base,job.height,null,color(0,100,0,0),job.stroke,'透明底座');
            for (var i=0;i<job.slots.length;i++) putShape(base,job.slots[i],job.height,null,color(0,100,0,0),job.stroke,'插槽 '+(i+1));
            if (!job.base && !job.slots.length) base.visible=false;
            if(job.factorySheet){var noteLayer=doc.layers.add();noteLayer.name=job.tabReferences.length?'06 制版说明（独立画板）':'05 制版说明（独立画板）';var nx=job.width+20,ny=0;doc.artboards.add([nx*PT,job.height*PT,(nx+job.factorySheet.width)*PT,(job.height-job.factorySheet.height)*PT]);doc.artboards[1].name='制版说明 - 不参与印刷';placePDF(noteLayer,job.factorySheet.path,nx,ny,job.factorySheet.width,job.factorySheet.height,'工厂制版说明');noteLayer.locked=true;}
            if (new File(job.outputPath).exists) fail('保存前检测到同名文件，请换新名称。');
            var save=new IllustratorSaveOptions(); save.pdfCompatible=true; save.compressed=true; save.embedICCProfile=true;
            doc.saveAs(out,save); saved=true;
            if (!new File(job.outputPath).exists || new File(job.outputPath).length===0) fail('Illustrator 未生成有效文件');
            if(doc.placedItems.length!==0)fail('存在未嵌入链接');
            var rasterAudit=[];for(var ri=0;ri<doc.rasterItems.length;ri++){var rr=doc.rasterItems[ri];rasterAudit.push({embedded:rr.embedded,colorSpace:String(rr.imageColorSpace),boundingBox:rr.boundingBox,width:rr.width,height:rr.height});}
            var report={rasterAudit:rasterAudit,ok:true,helperVersion:'0.2.3',outputPath:out.fsName,reportPath:reportFile.fsName,documentColorSpace:'CMYK',rulerUnits:String(doc.rulerUnits),artworkColorSpace:'CMYK',artworkEmbedded:raster?!!raster.embedded:true,artworkTransparent:raster?!!raster.transparent:true,artworkResolutionDpi:raster?job.dpi:null,artworkPreservesSourcePixels:!raster,whiteRaster:!!job.whiteImage,factoryArtboard:!!job.factorySheet,documentWidthMm:job.width,documentHeightMm:job.height,bodySubpaths:job.body.paths.length,whiteSubpaths:job.white?job.white.paths.length:0,whiteVisible:job.white?job.white.visible:false,whiteCMYK:[0,0,0,100],baseSubpaths:job.base?job.base.paths.length:0,slotCount:job.slots.length,tabReferenceCount:job.tabReferences.length,tabReferenceOnly:job.tabReferences.length>0,bodyExcludesTabs:job.tabReferences.length>0,cutPathsClosed:true,cutPathsAreFinishedBoundary:true,toolCompensationApplied:false,pdfCompatible:true};
            var reportText=stringify(report);
            if (reportFile.exists) fail('AI 已保存，但同名校验报告已存在。');
            reportFile.encoding='UTF-8'; if (!reportFile.open('w')) fail('AI 已保存，但校验报告无法写入。');
            try { if (!reportFile.write(reportText)) fail('AI 已保存，但校验报告写入失败。'); } finally { reportFile.close(); }
            if(job.verificationWhitePDF){var vf=new File(job.verificationWhitePDF);if(vf.exists)fail('校验 PDF 已存在');for(var li=0;li<doc.layers.length;li++)doc.layers[li].visible=false;ink.visible=true;var proof=new PDFSaveOptions();proof.preserveEditability=false;proof.artboardRange='1';doc.saveAs(vf,proof);doc.close(SaveOptions.DONOTSAVECHANGES);return reportText;}
            if (job.closeAfterSave) doc.close(SaveOptions.DONOTSAVECHANGES);
            return reportText;
        } catch (error) {
            if (doc && !saved) { try { doc.close(SaveOptions.DONOTSAVECHANGES); } catch(ignore) {} }
            throw error;
        } finally { if(priorPDFBox!==null){try{app.preferences.PDFFileOptions.pDFCropToBox=priorPDFBox;}catch(ignore){}} app.coordinateSystem=priorCoordinates; }
    }
    return {run:run, parseJSON:parseJSON, parsePath:parsePath, validate:validate, transform:transform, stringify:stringify, version:'0.2.3'};
}());
var AcrylicStandeeImport = AcrylicIllustrator;
if (typeof ACRYLIC_JOB_PATH !== 'undefined' && ACRYLIC_JOB_PATH) AcrylicStandeeImport.run(ACRYLIC_JOB_PATH);
