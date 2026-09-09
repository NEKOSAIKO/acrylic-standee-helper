const {app,BrowserWindow,ipcMain,dialog,Menu,nativeTheme}=require('electron');
const fs=require('node:fs/promises'),path=require('node:path');
const {Worker}=require('node:worker_threads');
const {execFile}=require('node:child_process');
let win,active,geometryRequest=0;
app.setName('亚克力立牌助手');
app.setPath('userData',path.join(app.getPath('appData'),'AcrylicStandee-Windows-Preview'));
async function readPNG(file){
 const bytes=await fs.readFile(file);
 if(bytes.length<24||bytes.subarray(0,8).toString('hex')!=='89504e470d0a1a0a')throw Error('请选择有效 PNG 图片。');
 const w=bytes.readUInt32BE(16),h=bytes.readUInt32BE(20);
 if(!w||!h||w*h>60000000)throw Error('PNG 上限为 6000 万像素。');
 return {name:path.basename(file),data:'data:image/png;base64,'+bytes.toString('base64'),width:w,height:h};
}
ipcMain.handle('open-png',async()=>{
 const r=await dialog.showOpenDialog(win,{title:'打开透明 PNG',filters:[{name:'PNG 图片',extensions:['png']}],properties:['openFile']});
 if(r.canceled)return null;return readPNG(r.filePaths[0]);
});
ipcMain.handle('sample',()=>readPNG(path.join(__dirname,'assets/sample.png')));
ipcMain.handle('initial-png',()=>{const file=process.argv.slice(1).find(a=>/\.png$/i.test(a));return file?readPNG(path.resolve(file)):null;});
ipcMain.handle('geometry',async(_e,data)=>{
 const request=++geometryRequest;
 if(active){active.resolve({cancelled:true});await active.worker.terminate();}
 if(request!==geometryRequest)return {cancelled:true};
 return new Promise(resolve=>{
  const worker=new Worker(path.join(__dirname,'worker.cjs'),{workerData:data});
  const job={worker,resolve};active=job;
  const done=r=>{if(active===job)active=null;resolve(r);};
  worker.once('message',done);worker.once('error',e=>done({error:e.message}));
  worker.once('exit',code=>{if(code)done({error:'计算线程已停止'});});
 });
});
function exportWorker(payload,output,kind){return new Promise((resolve,reject)=>{const worker=new Worker(path.join(__dirname,'export-worker.cjs'),{workerData:{payload,output,kind}});worker.once('message',r=>r.error?reject(Error(r.error)):resolve(r.result));worker.once('error',reject);worker.once('exit',code=>{if(code)reject(Error('导出线程退出：'+code));});});}
async function sendIllustrator(prepared){const script=await fs.readFile(path.join(__dirname,'illustrator-connect.ps1'),'utf8');return new Promise((resolve,reject)=>{const ps=path.join(process.env.SystemRoot,'System32/WindowsPowerShell/v1.0/powershell.exe');execFile(ps,['-NoProfile','-NonInteractive','-EncodedCommand',Buffer.from(script,'utf16le').toString('base64')],{windowsHide:true,timeout:240000,maxBuffer:4*1024*1024,env:{...process.env,ACRYLIC_ILLUSTRATOR_LAUNCHER:prepared.launcher}},(e,stdout,stderr)=>e?reject(Error(stderr.trim()||e.message)):resolve(stdout.trim()));});}
ipcMain.handle('export-file',async(_e,{kind,payload})=>{if(!['pdf','ai'].includes(kind))return {error:'不支持的导出格式'};try{const name=(payload.jobName||'亚克力立牌').replace(/[<>:"/\\|?*\x00-\x1f]/g,'_');const choice=await dialog.showSaveDialog(win,{title:kind==='ai'?'生成 .ai 文件':'导出六页 CMYK PDF',defaultPath:name+'.'+kind,filters:[{name:kind==='ai'?'Adobe Illustrator':'CMYK PDF',extensions:[kind]}]});if(choice.canceled)return {cancelled:true};const prepared=await exportWorker(payload,choice.filePath,kind);if(kind==='ai'){try{await sendIllustrator(prepared);await fs.access(prepared.output);}catch(e){return {...prepared,warning:'Illustrator 连接或保存未完成：'+e.message+'。制版数据包已保留在 '+prepared.folder+'；可手动运行其中 JSX。'};}}return prepared;}catch(e){return {error:e.message};}});
app.whenReady().then(()=>{
 if(process.argv.includes('--smoke-light'))nativeTheme.themeSource='light';
 win=new BrowserWindow({width:1440,height:980,minWidth:980,minHeight:700,title:'亚克力立牌助手 · Windows 预览版',icon:path.join(__dirname,'assets/icon.png'),backgroundColor:'#f3f4f7',webPreferences:{preload:path.join(__dirname,'preload.cjs'),contextIsolation:true,nodeIntegration:false,sandbox:true}});
 Menu.setApplicationMenu(Menu.buildFromTemplate([{label:'文件',submenu:[{label:'打开 PNG…',accelerator:'Ctrl+O',click:()=>win.webContents.send('command','open')},{label:'生成 .ai 文件',click:()=>win.webContents.send('command','export')},{type:'separator'},{role:'quit',label:'退出'}]},{label:'编辑',submenu:[{label:'撤销操作',accelerator:'Ctrl+Z',click:()=>win.webContents.send('command','undo')},{role:'copy',label:'复制'},{role:'paste',label:'粘贴'}]},{label:'帮助',submenu:[{label:'使用教程',click:()=>win.webContents.send('command','tutorial')}]}]));
 win.webContents.setWindowOpenHandler(()=>({action:'deny'}));
 win.webContents.on('will-navigate',e=>e.preventDefault());
 win.webContents.session.setPermissionRequestHandler((_w,_p,cb)=>cb(false));
 win.loadFile(path.join(__dirname,'ui/index.html'));
 if(process.argv.includes('--export-smoke')){
  win.webContents.on('did-finish-load',async()=>{try{const payload=await win.webContents.executeJavaScript('window.makeExportSmokePayload('+process.argv.includes('--brush-fixture')+')');const outDir=path.resolve(process.env.ACRYLIC_EXPORT_TEST_DIR||path.join(__dirname,'validation-export'));await fs.mkdir(outDir,{recursive:true});const pdf=await exportWorker(payload,path.join(outDir,'测试立牌.pdf'),'pdf');const ai=await exportWorker(payload,path.join(outDir,'测试立牌.ai'),'ai');if(process.argv.includes('--ai-smoke'))await sendIllustrator(ai);await fs.writeFile(path.join(outDir,'source.png'),Buffer.from(payload.pngData.split(',')[1],'base64'));await fs.writeFile(path.join(outDir,'white-alpha.bin'),Buffer.from(payload.whiteAlpha));await fs.writeFile(path.join(outDir,'geometry.json'),JSON.stringify(payload.geometry));await fs.writeFile(path.join(outDir,'export-result.json'),JSON.stringify({pdf,ai},null,2));}catch(e){await fs.writeFile(path.join(__dirname,'export-smoke-error.json'),JSON.stringify({error:e.message}));}finally{app.quit();}});
 }
 if(process.argv.includes('--smoke')){
  win.webContents.on('did-finish-load',async()=>{
   try{const result=await win.webContents.executeJavaScript('window.runSmoke()');result.extended=await win.webContents.executeJavaScript('window.runExtendedSmoke()');await fs.writeFile(path.join(__dirname,'smoke-result.json'),JSON.stringify(result,null,2));const shot=await win.webContents.capturePage();await fs.writeFile(path.join(__dirname,'smoke.png'),shot.toPNG());}catch(e){await fs.writeFile(path.join(__dirname,'smoke-result.json'),JSON.stringify({error:e.message}));}finally{app.quit();}
  });
 }
});
app.on('window-all-closed',()=>{if(active)active.worker.terminate();app.quit();});
