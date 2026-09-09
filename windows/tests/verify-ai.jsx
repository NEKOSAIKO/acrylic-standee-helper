#target illustrator
// ACRYLIC_VERIFY_CONFIG supplies paths created for this test only.
(function(){
 var cfg=ACRYLIC_VERIFY_CONFIG,prior=app.userInteractionLevel,doc=null,checks=[];
 $.evalFile(new File(cfg.helper));
 function check(ok,name){if(!ok)throw new Error('验收失败：'+name);checks.push(name);}
 function write(file,value){file=new File(file);if(file.exists)throw new Error('验收报告已存在');file.encoding='UTF-8';if(!file.open('w'))throw new Error('无法写入验收报告');file.write(AcrylicIllustrator.stringify(value));file.close();}
 function closeTarget(file){for(var i=app.documents.length-1;i>=0;i--){var d=app.documents[i];try{if(d.fullName.fsName===file.fsName)d.close(SaveOptions.DONOTSAVECHANGES);}catch(e){}}}
 try{
  app.userInteractionLevel=UserInteractionLevel.DONTDISPLAYALERTS;
  var file=new File(cfg.ai);check(file.exists,'Illustrator 原生 AI 文件存在');closeTarget(file);doc=app.open(file);
  check(doc.documentColorSpace===DocumentColorSpace.CMYK,'关闭重开后为 CMYK 文档');check(doc.rulerUnits===RulerUnits.Millimeters,'关闭重开后使用毫米');check(doc.artboards.length===2,'两个独立画板');check(doc.placedItems.length===0,'没有外部图片链接');
  var names=['01 彩色图稿 CMYK','02 白墨 K100','03 主体刀线','04 插脚位置参考（工厂调整）','05 底座与插槽刀线','06 制版说明（独立画板）'],layers=[];
  for(var i=0;i<names.length;i++){var l=doc.layers.getByName(names[i]);check(!!l,'图层存在：'+names[i]);layers.push({name:l.name,visible:l.visible,locked:l.locked,items:l.pageItems.length});}
  var ink=doc.layers.getByName(names[1]),cut=doc.layers.getByName(names[2]),refs=doc.layers.getByName(names[3]),base=doc.layers.getByName(names[4]);
  check(ink.visible===false,'白墨图层默认隐藏');check(refs.pathItems.length===cfg.tabs,'独立插脚参考框数量');check(base.pathItems.length===cfg.tabs+1,'底座外形与独立插槽数量');
  for(var i=0;i<refs.pathItems.length;i++){var p=refs.pathItems[i];check(p.closed&&p.pathPoints.length===4&&!p.filled,'插脚为闭合空心四角矩形 '+i);check(p.strokeColor.typename==='CMYKColor'&&p.strokeColor.cyan===100&&p.strokeColor.magenta===0,'插脚为青色参考 '+i);}
  for(var i=0;i<cut.pathItems.length;i++)check(cut.pathItems[i].closed&&!cut.pathItems[i].filled,'主体刀线闭合且不填充 '+i);
  check(doc.textFrames.length===0,'制版说明文字为轮廓，不依赖工厂字体');
  var rasters=[];for(var i=0;i<doc.rasterItems.length;i++){var r=doc.rasterItems[i],bb=r.boundingBox;check(r.embedded,'栅格已嵌入 '+i);check(r.imageColorSpace===ImageColorSpace.CMYK,'栅格色彩为 CMYK '+i);check(Math.round(bb[2]-bb[0])===cfg.width&&Math.round(bb[1]-bb[3])===cfg.height,'栅格保留原像素 '+i);rasters.push({width:bb[2]-bb[0],height:bb[1]-bb[3],transparent:r.transparent,embedded:r.embedded,colorSpace:String(r.imageColorSpace)});}
  check(rasters.length===2,'彩稿和白墨各一张原像素栅格');
  var report={ok:true,version:app.version,icc:doc.colorProfileName,artboards:doc.artboards.length,layers:layers,rasters:rasters,checks:checks};
  var proof=new File(cfg.proof);check(!proof.exists,'白墨校验 PDF 不覆盖原文件');for(var i=0;i<doc.layers.length;i++)doc.layers[i].visible=false;ink.visible=true;
  var opts=new PDFSaveOptions();opts.preserveEditability=false;opts.artboardRange='1';doc.saveAs(proof,opts);doc.close(SaveOptions.DONOTSAVECHANGES);doc=null;
  check(proof.exists&&proof.length>0,'Illustrator 实际导出白墨校验 PDF');
  write(cfg.report,report);doc=app.open(file);return AcrylicIllustrator.stringify(report);
 }finally{app.userInteractionLevel=prior;}
}());
