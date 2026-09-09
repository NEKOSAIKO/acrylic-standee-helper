const fs=require('node:fs/promises'),path=require('node:path'),crypto=require('node:crypto');
const PDFDocument=require('pdfkit'),sharp=require('sharp');
const {layout}=require('./export-layout.cjs');
const MM=72/25.4;
const fontPath=path.join(__dirname,'assets/fonts/NotoSansSC.ttf');
const profilePath=path.join(process.env.SystemRoot||'C:/Windows','System32/spool/drivers/color/RSWOP.icm');
const profileName='Agfa : Swop Standard (Windows RSWOP.icm)';
function validate(payload){
 const {geometry:g,settings:s}=payload;
 if(!g||!s||!g.tabReferenceOnly||g.bodyPath!==g.bodyOnlyPath)throw Error('导出缺少独立主体及插脚参考几何。');
 for(const k of ['widthMm','heightMm','totalHeightMm','totalWidthMm'])if(!Number.isFinite(g[k])||g[k]<=0||g[k]>1800)throw Error('导出尺寸无效。');
 if(s.whiteInset>0||s.whiteFill||s.whiteVector)throw Error('当前版本尚未支持白墨内缩、填孔或矢量输出，请关闭这些选项。');
 if(typeof payload.pngData!=='string'||!payload.pngData.startsWith('data:image/png;base64,'))throw Error('导出缺少原始 PNG。');
 return layout(g,s);
}
async function buffers(payload){
 const raw=Buffer.from(payload.pngData.split(',')[1],'base64');
 if(raw.subarray(0,8).toString('hex')!=='89504e470d0a1a0a')throw Error('无效 PNG。');
 const meta=await sharp(raw,{limitInputPixels:60000000}).metadata();if(meta.format!=='png')throw Error('仅支持 PNG');if(meta.orientation&&meta.orientation!==1)throw Error('PNG 含旋转方向标记，请先在图像软件中按正确方向另存后导出。');
 // Orientation is disabled in the preview (image-orientation:none), so preserve source rows here.
 const {data:rgba,info}=await sharp(raw,{limitInputPixels:60000000}).toColourspace('srgb').ensureAlpha().raw().toBuffer({resolveWithObject:true});
 const w=info.width,h=info.height,alpha=Buffer.alloc(w*h);for(let i=0;i<alpha.length;i++)alpha[i]=rgba[i*4+3];
 let icc;try{icc=await fs.readFile(profilePath);}catch{throw Error('Windows SWOP 色彩配置 RSWOP.icm 缺失，无法进行已验证的 CMYK 转换。');}
 const converted=await sharp(raw,{limitInputPixels:60000000}).removeAlpha().withIccProfile(profilePath,{attach:false}).toColourspace('cmyk').raw().toBuffer({resolveWithObject:true});
 if(converted.info.channels!==4||converted.info.hasAlpha||converted.data.length!==w*h*4)throw Error('CMYK 四通道转换失败。');
 const white=Buffer.from(payload.whiteAlpha||[]);if(white.length!==w*h)throw Error(`白墨蒙版必须为原图 ${w}×${h} 像素。`);
 if(!white.some(a=>a>0))throw Error('白墨蒙版为空。');
 return {w,h,alpha,white,cmyk:converted.data,icc,iccSha256:crypto.createHash('sha256').update(icc).digest('hex'),sourceSha256:crypto.createHash('sha256').update(raw).digest('hex')};
}
function newPDF(){return new PDFDocument({autoFirstPage:false,compress:true,pdfVersion:'1.4',info:{Title:'亚克力立牌 CMYK 制版文件',Creator:'亚克力立牌助手 Windows 0.1.1-preview.1',Subject:'毫米尺寸；原像素彩稿、K100 白墨、独立主体和插脚参考'}});}
function finish(doc){return new Promise((resolve,reject)=>{const chunks=[];doc.on('data',b=>chunks.push(b));doc.on('end',()=>resolve(Buffer.concat(chunks)));doc.on('error',reject);doc.end();});}
function images(doc,b,kind='six'){
 function create(data,alpha,space){const mask=doc.ref({Type:'XObject',Subtype:'Image',Width:b.w,Height:b.h,BitsPerComponent:8,ColorSpace:'DeviceGray',Decode:[0,1],Interpolate:true});mask.end(alpha);const image=doc.ref({Type:'XObject',Subtype:'Image',Width:b.w,Height:b.h,BitsPerComponent:8,ColorSpace:space,SMask:mask,Interpolate:true});image.end(data);return image;}
 const result={};if(kind!=='white'){const icc=doc.ref({N:4,Alternate:'DeviceCMYK'});icc.end(b.icc);result.art=create(b.cmyk,b.alpha,['ICCBased',icc]);}
 if(kind!=='art'){const black=Buffer.alloc(b.w*b.h*4);for(let i=3;i<black.length;i+=4)black[i]=255;result.white=create(black,b.white,'DeviceCMYK');}return result;
}
function place(doc,image,name,x,y,w,h){doc.page.xobjects[name]=image;doc.save().transform(w*MM,0,0,-h*MM,x*MM,(y+h)*MM).addContent('/'+name+' Do').restore();}
function stroke(doc,p,x,y,color){doc.save().translate(x*MM,y*MM).scale(MM).lineWidth(.1).lineJoin('round').lineCap('round').path(p).strokeColor(color).stroke().restore();}
function outlineText(doc,text,x,y,w,size=3.2,color=[0,0,0,85],maxHeight=Infinity){
 // Outlines avoid CJK font substitution when Illustrator embeds the PDF.
 doc.font(fontPath);const baseFont=doc._font.font,font=baseFont.getVariation?baseFont.getVariation({wght:400}):baseFont,scale=size/font.unitsPerEm,leading=size*1.5;let cx=x,cy=y+size;
 for(const ch of String(text)){if(ch==='\n'){cx=x;cy+=leading;continue;}const glyph=font.glyphForCodePoint(ch.codePointAt(0)),advance=glyph.advanceWidth*scale;if(cx+advance>x+w){cx=x;cy+=leading;}if(cy>y+maxHeight)throw Error('制版说明文字超出页面，请缩短项目名称或备注。');if(glyph.id===0&&!/\s/.test(ch))throw Error('中文字体缺少字形：'+ch);const svg=glyph.path.toSVG();if(svg)doc.save().translate(cx*MM,cy*MM).scale(scale*MM,-scale*MM).path(svg).fillColor(color).fill().restore();cx+=advance;}
 return cy-y;
}
function factory(doc,payload,b){const {settings:s,geometry:g}=payload;
 doc.addPage({size:[297*MM,210*MM],margin:0});doc.rect(0,0,297*MM,31*MM).fillColor([78,70,10,15]).fill();
 outlineText(doc,'ACRYLIC / 制版说明',12,7,265,7,[0,0,0,0]);outlineText(doc,'供印刷与加工核对 · 说明页不作为印刷图稿',13,23,270,3,[0,0,0,0]);
 outlineText(doc,payload.jobName||payload.name||'亚克力立牌',12,38,184,5,undefined,12);outlineText(doc,'WINDOWS 0.1.1 / 毫米尺寸',210,41,76,3);
 doc.rect(12*MM,56*MM,86*MM,124*MM).fillColor([2,2,0,2]).fill();outlineText(doc,'生产规格',17,60,72,4.3);
 const shape={circle:'圆形',square:'正方形',rectangle:'圆角矩形'}[s.baseShape];
 const lines=[`主体：${g.widthMm.toFixed(1)} × ${g.heightMm.toFixed(1)} mm`,`参考高：${g.totalHeightMm.toFixed(1)} mm`,`材料厚度：${s.thickness.toFixed(2)} mm`,`透明边：${s.offset.toFixed(2)} mm`,`底座：${shape} ${s.baseWidth} × ${s.baseShape==='rectangle'?s.baseLength:s.baseWidth} mm`,`插脚：${g.tabs.length} 个，宽 ${s.tabWidth} / 深 ${s.tabDepth} mm`,`参考框额外延展：${s.tabOverlap} mm`,`插槽：${(s.tabWidth+s.fit).toFixed(2)} × ${(s.thickness+s.fit).toFixed(2)} mm`,`白墨：K100，原像素蒙版`,`模式：${s.whiteFollowsAlpha?'跟随透明度':'实白底'}；阈值 ${s.threshold}%`,`手动补白：${payload.strokeCount||0} 笔`,`原图：${b.w} × ${b.h} px`,`有效分辨率：${(b.h/g.imageBox.height*25.4).toFixed(0)} ppi`,`彩稿 ICC：Agfa Swop Standard`,`原稿方向，未自动镜像`];
 outlineText(doc,lines.join('\n'),17,73,77,2.9,undefined,104);
 outlineText(doc,'图层与文件用途',105,59,176,4.3);
 const rows=[['01 彩色图稿 CMYK','保留原像素与透明度，不依赖外部图片链接。'],['02 白墨 K100','黑色代表白墨覆盖，不作为黑色图案印刷。'],['03 主体刀线','洋红成品边界，不含插脚，不印刷。'],['04 插脚位置参考','青蓝空心框，由工厂调整并连接主体。'],['05 底座与插槽','底座不铺白墨，插槽按材料厚度计算。'],['06 制版说明','独立说明画板，不随生产图稿输出。']];
 rows.forEach(([a,c],i)=>{const y=72+i*16;doc.rect(104*MM,(y-1)*MM,181*MM,15*MM).fillColor([0,0,0,i%2?0:3]).fill();outlineText(doc,a,108,y,169,3.3);outlineText(doc,c,108,y+6,169,2.8);});
 outlineText(doc,'投产前：核对彩稿 / 白墨对位、跨接开口、插脚连接及插槽公差。',105,171,180,2.8);outlineText(doc,'刀线未应用刀具中心补偿；插脚参考框不直接切割。',105,178,180,2.8);
 outlineText(doc,'备注：'+(payload.notes||'工厂如需不同 ICC、白墨或刀线命名，请在生产前确认。'),13,190,271,2.8,undefined,12);outlineText(doc,'当前参数生成 · 文件检查不等同于工厂试切验收',13,203,270,2.5,[0,0,0,55]);
}
async function render(payload,b,l,kind){const doc=newPDF();if(kind==='factory'){factory(doc,payload,b);return finish(doc);}const im=images(doc,b,kind),g=payload.geometry;
 if(kind==='art'||kind==='white'){const box=g.imageBox;doc.addPage({size:[box.width*MM,box.height*MM],margin:0});place(doc,im[kind],kind,0,0,box.width,box.height);return finish(doc);}
 for(let page=1;page<=6;page++){if(page===6){factory(doc,payload,b);continue;}doc.addPage({size:[l.pageWidth*MM,l.pageHeight*MM],margin:0});
  if(page===1){
   doc.save();doc.translate(l.bodyX*MM,l.bodyY*MM).scale(MM).path(g.bodyOnlyPath).clip('even-odd');doc.scale(1/MM).translate(-l.bodyX*MM,-l.bodyY*MM);const box=g.imageBox;place(doc,im.art,'Art',l.bodyX+box.x,l.bodyY+box.y,box.width,box.height);doc.restore();}
  if(page===2){const box=g.imageBox;place(doc,im.white,'White',l.bodyX+box.x,l.bodyY+box.y,box.width,box.height);}
  if(page===1||page===3)stroke(doc,g.bodyOnlyPath,l.bodyX,l.bodyY,[0,100,0,0]);
  if(page===1||page===5)l.tabs.forEach(t=>stroke(doc,t,l.bodyX,l.bodyY,[100,0,0,0]));
  if(page===1||page===4){stroke(doc,l.basePath,l.baseX,l.baseY,[0,100,0,0]);l.slots.forEach(t=>stroke(doc,t,l.baseX,l.baseY,[0,100,0,0]));}
 }return finish(doc);
}
async function exportFiles(payload,output,kind){const l=validate(payload),b=await buffers(payload);output=path.resolve(output);const ext=kind==='ai'?'.ai':'.pdf';if(path.extname(output).toLowerCase()!==ext)throw Error('输出扩展名应为 '+ext);
 try{await fs.access(output);throw Error('同名文件已经存在，请另存为新名称。');}catch(e){if(e.code!=='ENOENT')throw e;}
 const audit={sourcePixels:[b.w,b.h],sourceSha256:b.sourceSha256,colorSpace:'ICCBased CMYK',icc:profileName,iccSha256:b.iccSha256,whiteCMYK:[0,0,0,100],whiteMaskPixels:[b.w,b.h],whiteMaskSha256:crypto.createHash('sha256').update(b.white).digest('hex'),pageMm:[l.pageWidth,l.pageHeight],sourceSettings:payload.settings,strokeCount:payload.strokeCount||0};
 if(kind==='pdf'){const data=await render(payload,b,l,'six');await fs.writeFile(output,data,{flag:'wx'});return {output,audit};}
 const folder=await fs.mkdtemp(path.join(path.dirname(output),path.basename(output,'.ai')+'-制版数据-'));
 const artPath=path.join(folder,'artwork-cmyk.pdf'),whitePath=path.join(folder,'white-k100.pdf'),factoryPath=path.join(folder,'factory-sheet.pdf');
 for(const [file,k]of [[artPath,'art'],[whitePath,'white'],[factoryPath,'factory']])await fs.writeFile(file,await render(payload,b,l,k),{flag:'wx'});
 const helper=path.join(folder,'illustrator-helper.jsx');const helperSource=require('node:fs').existsSync(path.join(__dirname,'core/illustrator-helper.jsx'))?path.join(__dirname,'core/illustrator-helper.jsx'):path.join(__dirname,'../src/illustrator-helper.jsx');await fs.copyFile(helperSource,helper);
 const g=payload.geometry,box=g.imageBox,job={schemaVersion:3,outputPath:output,document:{widthMm:l.pageWidth,heightMm:l.pageHeight},artwork:{path:artPath,xMm:l.bodyX+box.x,yMm:l.bodyY+box.y,widthMm:box.width,heightMm:box.height},body:{path:g.bodyOnlyPath,xMm:l.bodyX,yMm:l.bodyY},tabReferences:l.tabs.map(p=>({path:p,xMm:l.bodyX,yMm:l.bodyY})),white:{imagePath:whitePath,xMm:l.bodyX+box.x,yMm:l.bodyY+box.y,widthMm:box.width,heightMm:box.height,visible:false},factorySheet:{imagePath:factoryPath,widthMm:297,heightMm:210},base:{path:l.basePath,xMm:l.baseX,yMm:l.baseY},slots:l.slots.map(p=>({path:p,xMm:l.baseX,yMm:l.baseY})),cutStrokeMm:.1,warnings:g.warnings,settings:payload.settings};
 const jobPath=path.join(folder,'standee-job.json'),launcher=path.join(folder,'在Illustrator中生成.jsx');await fs.writeFile(jobPath,JSON.stringify(job,null,2),{flag:'wx'});
 const launchCode='#target illustrator\n$.evalFile(new File('+JSON.stringify(helper)+'));\n(function(){var prior=app.userInteractionLevel;try{app.userInteractionLevel=UserInteractionLevel.DONTDISPLAYALERTS;var answer=AcrylicStandeeImport.run('+JSON.stringify(jobPath)+');var r=AcrylicIllustrator.parseJSON(answer);r.windowsIllustratorVersion=app.version;r.effectiveDocumentICC=app.activeDocument.colorProfileName;var f=new File('+JSON.stringify(output+'.windows-color.json')+');if(f.exists)throw new Error("色彩报告已存在");f.encoding="UTF-8";if(!f.open("w"))throw new Error("无法保存色彩报告");f.write(AcrylicIllustrator.stringify(r));f.close();return answer;}finally{app.userInteractionLevel=prior;}}());\n';
 await fs.writeFile(launcher,launchCode,{flag:'wx'});
 await fs.writeFile(path.join(folder,'色彩与像素校验.json'),JSON.stringify(audit,null,2));await fs.writeFile(path.join(folder,'使用说明.txt'),'在 Illustrator 中选择 文件 → 脚本 → 其他脚本，打开“在Illustrator中生成.jsx”。\n脚本新建 CMYK 文档并保存 AI，不覆盖现有文件。白墨默认隐藏；插脚参考框不与主体合并。\n自动连接失败不代表 AI 已生成；请核对输出文件和报告。\n');
 return {output,folder,job:jobPath,launcher,audit};
}
module.exports={exportFiles,buffers,render,validate};
