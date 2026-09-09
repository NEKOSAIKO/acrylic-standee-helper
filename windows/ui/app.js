'use strict';
const $=id=>document.getElementById(id),clone=v=>structuredClone(v);
const defaults={height:150,thickness:3,offset:3,curveSmooth:60,cornerRadius:1,toolDiameter:3,bridgeWidth:16,maxNotchDepth:1,tabWidth:18,tabDepth:3,tabPosition:0,tabOverlap:3,tabCount:1,whiteBrushSize:2,whiteFollowsAlpha:false,threshold:10,cncBridge:true,baseShape:'circle',baseWidth:65,baseLength:45,fit:0,disabledBridges:[]};
let settings=clone(defaults),art=null,result=null,base=null,mode='art',tab='cut',strokes=[],history=[],revision=0,loadRevision=0,whiteRevision=0,white=null,whiteWorker=null,zoom=1,pan={x:0,y:0},view=null,showBridges=false,drag=null,whiteTimer;
const fields=[
 ['bodyfields','height','主体高度',20,500,1,'mm'],['bodyfields','offset','最小透明边',0,15,.1,'mm'],['bodyfields','curveSmooth','曲线平滑',0,100,1,''],
 ['cutadvanced','cornerRadius','凹角圆滑 R',0,10,.1,'mm'],['cutadvanced','bridgeWidth','跨接开口上限',1,40,.5,'mm'],['cutadvanced','maxNotchDepth','凹口深度阈值',.1,10,.1,'mm'],['toolfields','toolDiameter','刀具直径',.5,10,.1,'mm'],
 ['brushfields','whiteBrushSize','画笔直径',.2,20,.2,'mm'],['whitefields','threshold','透明度阈值',1,99,1,'%'],
 ['basefields','baseWidth','底座宽度',10,200,1,'mm'],['basefields','baseLength','矩形长度',10,200,1,'mm'],['basefields','thickness','材料厚度',.5,15,.1,'mm'],
 ['tabfields','tabWidth','插脚宽度',1,80,.5,'mm'],['tabfields','tabDepth','插入深度',.5,15,.1,'mm'],['tabfields','tabPosition','插脚位置',-100,100,1,'%'],
 ['baseadvanced','tabOverlap','参考框向上延展',0,20,.1,'mm'],['baseadvanced','fit','插槽尺寸修正',-1,3,.05,'mm']
];
for(const [parent,key,label,min,max,step,unit] of fields){const div=document.createElement('div');div.className='field';div.innerHTML=`<div class="fieldhead"><label for="n-${key}">${label}</label><input id="n-${key}" data-key="${key}" type="number" min="${min}" max="${max}" step="${step}"><span>${unit}</span></div><input aria-label="${label}滑块" data-key="${key}" type="range" min="${min}" max="${max}" step="${step}">`;$(parent).append(div);}
function sync(){document.querySelectorAll('[data-key]').forEach(e=>{if(e.type==='checkbox')e.checked=settings[e.dataset.key];else e.value=settings[e.dataset.key];});$('strokecount').textContent=strokes.length+' 笔手动补白';}
function saveUndo(){history.push({settings:clone(settings),strokes:clone(strokes)});if(history.length>40)history.shift();}
function undo(){if(!history.length)return;const h=history.pop();settings=h.settings;strokes=h.strokes;sync();compute();}
document.querySelectorAll('[data-key]').forEach(e=>{e.addEventListener('input',()=>{if(e.type==='range'){const n=$('n-'+e.dataset.key);if(n)n.value=e.value;}});e.addEventListener('change',()=>{
 let v=e.type==='checkbox'?e.checked:e.tagName==='SELECT'&&e.dataset.key==='baseShape'?e.value:Number(e.value);
 if(typeof v==='number'&&(!Number.isFinite(v)||(e.min!==''&&v<Number(e.min))||(e.max!==''&&v>Number(e.max)))){sync();return;}
 if(settings[e.dataset.key]===v)return;saveUndo();settings[e.dataset.key]=v;sync();compute();
});});
function setTab(t){tab=t;document.querySelectorAll('[data-panel]').forEach(e=>e.hidden=e.dataset.panel!==t);document.querySelectorAll('[data-tab]').forEach(e=>e.classList.toggle('selected',e.dataset.tab===t));if(t==='white')setMode('white');}
function setMode(m){mode=m;document.querySelectorAll('[data-mode]').forEach(e=>e.classList.toggle('selected',e.dataset.mode===m));if(m==='white')updateWhite();draw();}
document.querySelectorAll('[data-tab]').forEach(e=>e.onclick=()=>setTab(e.dataset.tab));document.querySelectorAll('[data-mode]').forEach(e=>e.onclick=()=>setMode(e.dataset.mode));
$('advanced').onchange=()=>{document.body.classList.toggle('advanced-open',$('advanced').checked);localStorage.setItem('advanced',String($('advanced').checked));positionTour();};
$('advanced').checked=localStorage.getItem('advanced')==='true';document.body.classList.toggle('advanced-open',$('advanced').checked);
$('reset').onclick=()=>{saveUndo();settings=clone(defaults);sync();compute();};$('undo').onclick=undo;
$('undoStroke').onclick=()=>{if(!strokes.length)return;saveUndo();strokes.pop();sync();updateWhite();};$('clearStrokes').onclick=()=>{if(!strokes.length)return;saveUndo();strokes=[];sync();updateWhite();};
$('brush').onchange=()=>{if($('brush').checked)setMode('white');};$('compare').onchange=draw;
$('bridges').onclick=()=>{showBridges=!showBridges;draw();};
async function load(input){if(!input)return;const id=++loadRevision;const img=new Image();img.src=input.data;await img.decode();if(id!==loadRevision)return;
 const ratio=Math.min(1,960/Math.max(img.naturalWidth,img.naturalHeight)),c=document.createElement('canvas');c.width=Math.max(1,Math.round(img.naturalWidth*ratio));c.height=Math.max(1,Math.round(img.naturalHeight*ratio));const ctx=c.getContext('2d',{willReadFrequently:true});ctx.drawImage(img,0,0,c.width,c.height);const rgba=ctx.getImageData(0,0,c.width,c.height).data,alpha=new Uint8Array(c.width*c.height);for(let i=0;i<alpha.length;i++)alpha[i]=rgba[i*4+3];if(!alpha.some(v=>v>0))throw Error('图片完全透明，没有可提取的轮廓。');
 art={img,name:input.name,source:{width:c.width,height:c.height,alpha,originalWidth:img.naturalWidth,originalHeight:img.naturalHeight}};strokes=[];history=[];settings.disabledBridges=[];whiteRevision++;if(whiteWorker)whiteWorker.terminate();if(white)white.close();white=null;zoom=1;pan={x:0,y:0};$('filename').textContent=input.name;$('imageinfo').textContent=`原图 ${img.naturalWidth} × ${img.naturalHeight} px · 几何分析 ${c.width} × ${c.height} px · 本地处理`;sync();await compute();}
async function open(){try{await load(await desktop.openPNG());}catch(e){$('status').textContent=e.message;}}
$('open').onclick=open;$('sample').onclick=async()=>{try{await load(await desktop.sample());}catch(e){$('status').textContent=e.message;}};
async function compute(){const rev=++revision;result=null;base=null;draw();if(!art)return;$('status').textContent='正在计算真实刀线…';const snapshot=clone(settings);try{
 if(settings.height<=2*(settings.offset+.2))throw Error('主体高度过小，请减小透明边。');
 const r=await desktop.geometry({source:art.source,options:{...snapshot,threshold:Math.round(snapshot.threshold*2.55)}});if(rev!==revision||r.cancelled)return;if(r.error)throw Error(r.error);result=r.result;
 try{base=baseLayout(result,snapshot);}catch(e){base=null;$('status').textContent=e.message;}
 const g=result;$('dimensions').textContent=`主体 ${g.widthMm.toFixed(1)} × ${g.heightMm.toFixed(1)} mm　含参考框 ${g.totalHeightMm.toFixed(1)} mm　插槽 ${(snapshot.tabWidth+snapshot.fit).toFixed(2)} × ${(snapshot.thickness+snapshot.fit).toFixed(2)} mm`;
 if(base)$('status').textContent=`已跨接 ${g.bridgeDiagnostics.bridged} 处 · ${g.curveNodes} 段曲线 · ${(g.engineMs/1000).toFixed(2)} 秒。${g.warnings.join(' ')} 主体不含插脚；导出尚未验收。`;
 const list=$('bridgelist');list.replaceChildren();for(const r of g.bridgeRegions){const b=document.createElement('button');b.textContent=`${r.index+1}：${r.enabled?'取消跨接':'保留跨接'}`;b.onclick=()=>{saveUndo();settings.disabledBridges=r.enabled?[...settings.disabledBridges,r.index]:settings.disabledBridges.filter(i=>i!==r.index);compute();};list.append(b);}
 updateWhite();draw();return g;
 }catch(e){if(rev===revision){result=null;base=null;$('dimensions').textContent='无法生成当前参数的刀线';$('status').textContent=e.message;draw();}}}
async function updateWhite(){const id=++whiteRevision;if(whiteWorker){whiteWorker.terminate();whiteWorker=null;}if(white){white.close();white=null;}if(!art||!result||mode!=='white'){draw();return;}
 const bitmap=await createImageBitmap(art.img);if(id!==whiteRevision){bitmap.close();return;}const worker=new Worker('white-worker.js');whiteWorker=worker;worker.onmessage=({data})=>{worker.terminate();if(whiteWorker===worker)whiteWorker=null;if(id!==whiteRevision){data.bitmap?.close();return;}if(data.error){$('status').textContent='白墨预览失败：'+data.error;return;}white=data.bitmap;draw();};worker.onerror=e=>{$('status').textContent='白墨线程失败：'+e.message;worker.terminate();};worker.postMessage({bitmap,s:clone(settings),g:result,strokes:clone(strokes)},[bitmap]);}
const canvas=$('canvas'),ctx=canvas.getContext('2d');
function draw(){const rect=canvas.getBoundingClientRect(),dpr=devicePixelRatio;canvas.width=Math.round(rect.width*dpr);canvas.height=Math.round(rect.height*dpr);ctx.setTransform(dpr,0,0,dpr,0,0);ctx.clearRect(0,0,rect.width,rect.height);const css=getComputedStyle(document.documentElement),ink=css.getPropertyValue('--muted'),grid=css.getPropertyValue('--grid');
 if(!result){ctx.fillStyle=ink;ctx.font='16px Microsoft YaHei';ctx.textAlign='center';ctx.fillText(art?'正在更新刀线…':'打开 PNG，开始制作你的立牌',rect.width/2,rect.height/2);return;}
 const g=result,bx=g.bounds.x+g.bounds.width+24,by=(g.totalHeightMm-(base?.height||65))/2,w=g.bounds.width+24+(base?.width||65),h=Math.max(g.totalHeightMm,base?.height||65);
 const scale=Math.max(.1,Math.min((rect.width-90)/w,(rect.height-105)/h))*zoom,ox=(rect.width-w*scale)/2-g.bounds.x*scale+pan.x,oy=(rect.height-h*scale)/2+12+pan.y;view={scale,ox,oy};
 ctx.save();ctx.translate(ox,oy);ctx.scale(scale,scale);
 function pathStroke(p,color,width=.4,dash=[]){ctx.strokeStyle=color;ctx.lineWidth=width;ctx.setLineDash(dash);ctx.stroke(new Path2D(p));ctx.setLineDash([]);}
 function checker(p,x,y,w,h){ctx.save();ctx.clip(p,'evenodd');ctx.fillStyle=css.getPropertyValue('--control');ctx.fillRect(x,y,w,h);ctx.fillStyle=grid;for(let yy=Math.floor(y/5)*5;yy<y+h;yy+=5)for(let xx=Math.floor(x/5)*5;xx<x+w;xx+=5)if((Math.round(xx/5)+Math.round(yy/5))%2===0)ctx.fillRect(xx,yy,5,5);ctx.restore();}
 checker(new Path2D(g.bodyOnlyPath),g.bounds.x,0,g.bounds.width,g.heightMm);
 if(mode!=='cut'){const b=g.imageBox;if(mode==='white'){ctx.globalAlpha=.18;ctx.drawImage(art.img,b.x,b.y,b.width,b.height);ctx.globalAlpha=1;if(white)ctx.drawImage(white,b.x,b.y,b.width,b.height);}else ctx.drawImage(art.img,b.x,b.y,b.width,b.height);}
 if($('compare').checked)pathStroke(g.baselinePath,'#9ca4b3',.2,[1,1]);pathStroke(g.bodyOnlyPath,'#ff4299',.4);
 ctx.strokeStyle='#289dff';ctx.lineWidth=.35;for(const t of g.tabs)ctx.strokeRect(t.x,t.y,t.width,t.height);
 if(showBridges){for(const r of g.bridgeRegions){ctx.strokeStyle=r.enabled?'#00ab94':'#f6a13b';ctx.lineWidth=.6;ctx.strokeRect(r.bounds.x,r.bounds.y,r.bounds.width,r.bounds.height);ctx.fillStyle=ink;ctx.font='3px Microsoft YaHei';ctx.fillText(String(r.index+1),r.bounds.x,r.bounds.y-1);}}
 if(base){ctx.save();ctx.translate(bx,by);const p=new Path2D();if(settings.baseShape==='circle')p.ellipse(base.width/2,base.height/2,base.width/2,base.height/2,0,0,Math.PI*2);else p.roundRect(0,0,base.width,base.height,Math.min(3,base.width/2,base.height/2));checker(p,0,0,base.width,base.height);ctx.strokeStyle='#ff4299';ctx.lineWidth=.4;ctx.stroke(p);for(const s of base.slots){ctx.beginPath();ctx.roundRect(s.x,s.y,s.width,s.height,s.radius);ctx.fillStyle=ink;ctx.fill();ctx.stroke();}ctx.restore();}
 ctx.restore();ctx.fillStyle=ink;ctx.textAlign='center';ctx.font='bold 14px Microsoft YaHei';ctx.fillText('主体 · 正面',ox+g.widthMm*scale/2,Math.max(25,oy-30));if(base)ctx.fillText('底座 · 俯视',ox+(bx+base.width/2)*scale,oy+by*scale-25);
}
new ResizeObserver(()=>{draw();positionTour();}).observe($('canvaswrap'));matchMedia('(prefers-color-scheme: dark)').addEventListener('change',draw);
$('fit').onclick=()=>{zoom=1;pan={x:0,y:0};draw();};$('actual').onclick=()=>{if(!view)return;zoom*=96/25.4/view.scale;pan={x:0,y:0};draw();};$('pixels').onclick=()=>{if(!view||!art)return;zoom*=art.img.naturalHeight/result.imageBox.height/view.scale;pan={x:0,y:0};draw();};
canvas.onwheel=e=>{e.preventDefault();zoom=Math.max(.1,Math.min(30,zoom*Math.exp(-e.deltaY*.001)));draw();};
function point(e){const r=canvas.getBoundingClientRect(),b=result.imageBox;return {x:((e.clientX-r.left-view.ox)/view.scale-b.x)/b.width,y:((e.clientY-r.top-view.oy)/view.scale-b.y)/b.height};}
canvas.onpointerdown=e=>{if(!result||tourIndex>=0)return;canvas.setPointerCapture(e.pointerId);if($('brush').checked&&mode==='white'&&!e.altKey&&e.button===0){const p=point(e);if(p.x<0||p.x>1||p.y<0||p.y>1)return;saveUndo();const stroke={points:[p],radius:settings.whiteBrushSize/2/result.imageBox.height};strokes.push(stroke);drag={stroke};sync();updateWhite();}else drag={x:e.clientX,y:e.clientY,pan:{...pan}};};
canvas.onpointermove=e=>{if(!drag)return;if(drag.stroke){drag.stroke.points.push(point(e));clearTimeout(whiteTimer);whiteTimer=setTimeout(updateWhite,80);}else{pan={x:drag.pan.x+e.clientX-drag.x,y:drag.pan.y+e.clientY-drag.y};draw();}};
canvas.onpointerup=()=>{if(drag?.stroke){clearTimeout(whiteTimer);updateWhite();}drag=null;};canvas.onpointercancel=canvas.onpointerup;
$('pdf').onclick=$('export').onclick=()=>desktop.exportInfo();
let tourIndex=-1,tourSaved;
const steps=[['open',null,'导入透明 PNG','点击真实按钮选择 PNG，取消选择也可以继续。'],['bodyTarget','cut','主体尺寸与透明边','调整主体高度、透明边和平滑，刀线在后台重新计算。'],['whiteTarget','white','原像素白墨与补白','黑色是覆盖预览。启用画笔后结束引导，即可在画布单击或拖动补白。'],['baseTarget','base','底座与插槽','插槽宽度为插脚宽度加修正，高度为材料厚度加修正。'],['tabTarget','base','独立插脚参考框','参考框不与主体刀线合并，顶部默认再延展 3 mm。'],['advancedTarget',null,'高级设置','展开精细参数。收起只改变显示，不重置参数。'],['notesTarget','delivery','工厂备注','记录项目名与加工要求。当前预览版尚未提供会话保存。'],['export','delivery','生成 .ai 文件','此按钮名称保持一致。Windows 导出仍待适配与验收，当前不会打开 Illustrator。']];
function startTour(){if(tourIndex>=0)return;tourSaved={tab,mode};tourIndex=0;$('tour').hidden=false;showStep();}
function endTour(){tourIndex=-1;$('tour').hidden=true;setTab(tourSaved.tab);setMode(tourSaved.mode);localStorage.setItem('tutorialSeen','true');}
function showStep(){const s=steps[tourIndex];if(s[1])setTab(s[1]);$(s[0]).scrollIntoView({block:'nearest'});$('tourStep').textContent=`操作引导 ${tourIndex+1} / 8`;$('tourTitle').textContent=s[2];$('tourText').textContent=s[3];$('prev').disabled=tourIndex===0;$('next').textContent=tourIndex===7?'完成':'下一步';requestAnimationFrame(positionTour);}
function positionTour(){if(tourIndex<0)return;const r=$(steps[tourIndex][0]).getBoundingClientRect(),x=Math.max(0,r.left-5),y=Math.max(0,r.top-5),right=Math.min(innerWidth,r.right+5),bottom=Math.min(innerHeight,r.bottom+5),w=right-x,h=bottom-y;
 function box(id,l,t,w,h){Object.assign($(id).style,{left:l+'px',top:t+'px',width:Math.max(0,w)+'px',height:Math.max(0,h)+'px'});}
 box('shadeTop',0,0,innerWidth,y);box('shadeBottom',0,bottom,innerWidth,innerHeight-bottom);box('shadeLeft',0,y,x,h);box('shadeRight',right,y,innerWidth-right,h);box('highlight',x,y,w,h);
 const card=$('tourCard'),cw=320,ch=card.offsetHeight;let cx=x>cw+35?x-cw-20:Math.min(innerWidth-cw-12,right+20),cy=Math.min(innerHeight-ch-12,Math.max(12,y));if(!(cx+cw<x||cx>right)){cy=bottom+15;if(cy+ch>innerHeight)cy=Math.max(12,y-ch-15);}card.style.left=Math.max(12,cx)+'px';card.style.top=cy+'px';}
$('tutorial').onclick=startTour;$('prev').onclick=()=>{if(tourIndex>0){tourIndex--;showStep();}};$('next').onclick=()=>{if(tourIndex===7)endTour();else{tourIndex++;showStep();}};$('end').onclick=endTour;
document.addEventListener('scroll',positionTour,true);window.addEventListener('resize',positionTour);document.addEventListener('keydown',e=>{if(e.key==='Escape'&&tourIndex>=0)endTour();if(tourIndex>=0&&e.key==='Tab'){const target=$(steps[tourIndex][0]);const allowed=[...target.querySelectorAll('button,input,select,textarea'),...$('tourCard').querySelectorAll('button')];if(target.matches('button,input'))allowed.unshift(target);const usable=allowed.filter(x=>!x.disabled&&x.getClientRects().length);e.preventDefault();const i=usable.indexOf(document.activeElement);usable[(i+(e.shiftKey?-1:1)+usable.length)%usable.length]?.focus();}});
desktop.onCommand(c=>{if(tourIndex>=0&&c!=='tutorial'&&!(c==='open'&&tourIndex===0)&&!(c==='export'&&tourIndex===7))return;if(c==='open')open();if(c==='undo')undo();if(c==='export')desktop.exportInfo();if(c==='tutorial')startTour();});
window.runSmoke=async()=>{await load(await desktop.sample());if(!result||!base)throw Error('示例没有生成几何');const first={width:result.widthMm,height:result.heightMm,tabs:clone(result.tabs),slots:clone(base.slots),nodes:result.curveNodes};settings.tabOverlap=6;await compute();if(result.tabs[0].y>=first.tabs[0].y)throw Error('向上延展未生效');settings=clone(defaults);await compute();const sampleName=art.name;let rejected=false;try{const c=document.createElement('canvas');c.width=c.height=8;await load({name:'全透明.png',data:c.toDataURL()});}catch{rejected=true;}if(!rejected||art.name!==sampleName)throw Error('透明图错误处理失败');setMode('art');return {ok:true,platform:navigator.userAgent,original:[art.img.naturalWidth,art.img.naturalHeight],analysis:[art.source.width,art.source.height],first,transparentRejected:rejected,bodyIndependent:result.bodyPath===result.bodyOnlyPath,baseline:'9f64997d0305ebf300d752035c562906f3cf8d0c'};};
sync();draw();desktop.initialPNG().then(load).catch(e=>{$('status').textContent=e.message;});
