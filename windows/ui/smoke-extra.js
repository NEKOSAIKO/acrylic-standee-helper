// Runs only when explicitly invoked by the desktop --smoke harness.
window.makeExportSmokePayload=async(brush=false)=>{if(brush){const c=document.createElement('canvas');c.width=96;c.height=128;const x=c.getContext('2d');x.fillStyle='#f34b52';x.fillRect(12,12,72,104);x.fillStyle='#306ddd';x.fillRect(12,76,36,40);x.fillStyle='#29b678';x.fillRect(48,76,36,40);x.clearRect(34,48,28,28);x.clearRect(16,20,64,16);for(let i=0;i<64;i++){x.fillStyle=`rgba(30,30,30,${i/63})`;x.fillRect(16+i,20,1,16);}await load({name:'半透明与补白验收.png',data:c.toDataURL()});strokes=[{points:[{x:.5,y:.48},{x:.58,y:.52}],radius:.055}];settings.tabCount=2;settings.tabWidth=14;settings.baseWidth=95;await compute();}else await load(await desktop.sample());$('jobName').value=brush?'半透明 / 补白 / 双插脚验收':'Windows 导出验收 · 示例立牌';$('notes').value='独立插脚参考框；白墨 K100；本文件用于 Windows 导出功能验收。';return exportPayload();};
window.runExtendedSmoke=async()=>{
 const checks=[];const assert=(ok,msg)=>{if(!ok)throw Error(msg);checks.push(msg);};
 const wait=async fn=>{const start=Date.now();while(!fn()){if(Date.now()-start>15000)throw Error('后台蒙版等待超时');await new Promise(r=>setTimeout(r,20));}};
 const fixture=document.createElement('canvas');fixture.width=40;fixture.height=60;const fc=fixture.getContext('2d');fc.fillStyle='rgba(255,0,0,1)';fc.fillRect(5,5,30,50);fc.clearRect(15,25,10,10);
 await load({name:'白墨测试.png',data:fixture.toDataURL()});setMode('white');await wait(()=>white);
 assert(white.width===40&&white.height===60,'白墨保持原像素尺寸');
 const alphaAt=(x,y)=>{const c=document.createElement('canvas');c.width=40;c.height=60;const cx=c.getContext('2d');cx.drawImage(white,0,0);return cx.getImageData(x,y,1,1).data[3];};
 assert(alphaAt(20,30)===0,'原始透明孔保持透明');
 saveUndo();strokes.push({points:[{x:.5,y:.5}],radius:.1});await updateWhite();await wait(()=>white);assert(alphaAt(20,30)===255,'单点补白进入原像素蒙版');
 const normalized=JSON.stringify(strokes);settings.height=200;await compute();await wait(()=>white);assert(JSON.stringify(strokes)===normalized&&alphaAt(20,30)===255,'修改毫米尺寸后笔迹定位不变');
 $('jobName').value='保留名称';$('notes').value='保留备注';$('reset').click();await wait(()=>result&&white);assert(strokes.length===1&&$('jobName').value==='保留名称'&&$('notes').value==='保留备注','恢复默认保留名称备注和笔迹');
 undo();await wait(()=>result&&white);assert(settings.height===200,'恢复默认可撤销');
 setTab('base');setMode('cut');startTour();
 for(let i=0;i<8;i++){tourIndex=i;showStep();await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));positionTour();const t=$(steps[i][0]).getBoundingClientRect(),card=$('tourCard').getBoundingClientRect();assert(card.left>=0&&card.top>=0&&card.right<=innerWidth+1&&card.bottom<=innerHeight+1,`教程 ${i+1} 卡片不出界`);assert(card.right<=t.left||card.left>=t.right||card.bottom<=t.top||card.top>=t.bottom,`教程 ${i+1} 卡片不挡目标`);const x=(t.left+t.right)/2,y=(t.top+t.bottom)/2,hit=document.elementFromPoint(x,y);assert(hit===$(steps[i][0])||$(steps[i][0]).contains(hit),`教程 ${i+1} 真实目标可命中`);}
 endTour();assert(tab==='base'&&mode==='cut','退出教程恢复原页面与预览');
 settings=clone(defaults);await load(await desktop.sample());await wait(()=>result&&base);assert(strokes.length===0&&history.length===0,'重新导入清除笔迹与撤销历史');setTab('cut');setMode('art');
 await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));
 return {checks,dpr:devicePixelRatio,theme:matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light',viewport:[innerWidth,innerHeight]};
};
