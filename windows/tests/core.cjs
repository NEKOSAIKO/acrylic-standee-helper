const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {build}=require('../geometry.cjs');
const {baseLayout}=require('../ui/layout.js');
const checks=[];
function test(name,fn){fn();checks.push(name);console.log('PASS',name);}
function image(w,h,fn){const alpha=new Uint8Array(w*h);for(let y=0;y<h;y++)for(let x=0;x<w;x++)alpha[y*w+x]=fn(x,y);return {width:w,height:h,originalWidth:w,originalHeight:h,alpha};}
const rect=image(100,150,(x,y)=>x>15&&x<85&&y>10&&y<140?255:0);
const opts={height:150,offset:3,curveSmooth:60,cornerRadius:1,toolDiameter:3,bridgeWidth:16,maxNotchDepth:1,tabWidth:18,tabDepth:3,tabPosition:0,tabOverlap:3,tabCount:1,cncBridge:true,threshold:26};
const r=build(rect,opts);
test('主体闭合，真实毫米高度，插脚不合并',()=>{assert.match(r.bodyPath,/Z/);assert.equal(r.bodyPath,r.bodyOnlyPath);assert.equal(r.tabReferenceOnly,true);assert.ok(Math.abs(r.heightMm-150)<.6);assert.ok(r.curveNodes>0);assert.equal(r.tabs[0].width,18);});
test('参考框顶部额外延展 3 mm，底部和主体不变',()=>{const a=build(rect,{...opts,tabOverlap:0});assert.ok(Math.abs(a.tabs[0].y-r.tabs[0].y-3)<1e-6);assert.equal(a.bodyPath,r.bodyPath);assert.ok(Math.abs(a.tabs[0].y+a.tabs[0].height-r.tabs[0].y-r.tabs[0].height)<1e-6);});
test('双插脚参考独立且不修改主体',()=>{const a=build(rect,{...opts,tabCount:2});assert.equal(a.tabs.length,2);assert.equal(a.bodyOnlyPath,r.bodyOnlyPath);});
test('换图不复用旧透明度缓存',()=>{const circle=image(100,150,(x,y)=>(x-50)**2+(y-75)**2<30**2?255:0);const a=build(circle,opts);assert.notEqual(a.bodyPath,r.bodyPath);});
test('全透明输入返回明确错误',()=>assert.throws(()=>build(image(10,10,()=>0),opts),/没有图案/));
const s={baseShape:'circle',baseWidth:65,baseLength:45,tabWidth:18,thickness:3,fit:0};
test('底座插槽按厚度，非插入深度计算',()=>{const b=baseLayout(r,{...s,tabDepth:8});assert.equal(b.slots[0].width,18);assert.equal(b.slots[0].height,3);assert.equal(b.slots[0].radius,.4);});
test('越界底座插槽被拒绝',()=>assert.throws(()=>baseLayout(r,{...s,baseWidth:15}),/边缘/));
test('修正后的插槽不能为零或负',()=>assert.throws(()=>baseLayout(r,{...s,fit:-4}),/无效/));
const upstream={};for(const f of ['acrylic-geometry.js','curve-fit.js','NativeGeometry.cpp','NativeGeometry.h','illustrator-helper.jsx'])upstream[f]=crypto.createHash('sha256').update(fs.readFileSync(path.join(__dirname,'../../src',f))).digest('hex');
fs.writeFileSync(path.join(__dirname,'results.json'),JSON.stringify({date:new Date().toISOString(),platform:process.platform,arch:process.arch,checks,sample:{heightMm:r.heightMm,widthMm:r.widthMm},upstream},null,2));
