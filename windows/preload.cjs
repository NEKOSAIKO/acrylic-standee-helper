const {contextBridge,ipcRenderer}=require('electron');
contextBridge.exposeInMainWorld('desktop',{
 openPNG:()=>ipcRenderer.invoke('open-png'),sample:()=>ipcRenderer.invoke('sample'),initialPNG:()=>ipcRenderer.invoke('initial-png'),
 geometry:data=>ipcRenderer.invoke('geometry',data),
 exportFile:(kind,payload)=>ipcRenderer.invoke('export-file',{kind,payload}),
 onCommand:callback=>ipcRenderer.on('command',(_e,c)=>callback(c))
});
