const fs=require('node:fs'),path=require('node:path');
const root=__dirname,out=path.join(root,'dist/AcrylicStandee-'+require('./package.json').version+'-Windows-x64');
if(fs.existsSync(out))throw Error('输出目录已存在，请使用新的输出目录或手动归档旧包后重试。');
fs.mkdirSync(out,{recursive:true});
fs.cpSync(path.join(path.dirname(require.resolve('electron')),'dist'),out,{recursive:true});
fs.renameSync(path.join(out,'electron.exe'),path.join(out,'亚克力立牌助手.exe'));
const app=path.join(out,'resources/app');fs.mkdirSync(app,{recursive:true});
for(const f of ['main.cjs','preload.cjs','worker.cjs','geometry.cjs','export-worker.cjs','export-layout.cjs','export-pdf.cjs','illustrator-connect.ps1','package.json','ui','assets','native/acrylic.dll'])fs.cpSync(path.join(root,f),path.join(app,f),{recursive:true});
fs.mkdirSync(path.join(app,'core'),{recursive:true});
for(const f of ['curve-fit.js','acrylic-geometry.js','illustrator-helper.jsx'])fs.copyFileSync(path.join(root,'../src',f),path.join(app,'core',f));
const koffiDir=path.dirname(require.resolve('koffi')),dest=path.join(app,'node_modules/koffi');
for(const f of ['index.js','package.json','LICENSE.txt','build/koffi/win32_x64']){const src=path.join(koffiDir,f);if(fs.existsSync(src)){fs.mkdirSync(path.dirname(path.join(dest,f)),{recursive:true});fs.cpSync(src,path.join(dest,f),{recursive:true});}}
function copyPackage(name,from,destination,ancestors=[]){
 const loader=require('node:module').createRequire(path.join(from,'package.json'));
 let source;try{source=path.dirname(loader.resolve(name+'/package.json'));}catch{let entry;try{entry=loader.resolve(name+'/package');}catch{entry=loader.resolve(name);}source=path.dirname(entry);while(!fs.existsSync(path.join(source,'package.json'))||JSON.parse(fs.readFileSync(path.join(source,'package.json'),'utf8')).name!==name){const parent=path.dirname(source);if(parent===source)throw Error('无法定位依赖 '+name);source=parent;}}
 const metadata=JSON.parse(fs.readFileSync(path.join(source,'package.json'),'utf8'));
 const identity=name+'@'+metadata.version;if(ancestors.includes(identity))return;
 const target=path.join(destination,name);fs.mkdirSync(target,{recursive:true});
 for(const entry of fs.readdirSync(source)){if(entry==='node_modules')continue;fs.cpSync(path.join(source,entry),path.join(target,entry),{recursive:true,dereference:true});}
 for(const dep of Object.keys(metadata.dependencies||{}))copyPackage(dep,source,path.join(target,'node_modules'),[...ancestors,identity]);
 for(const dep of Object.keys(metadata.optionalDependencies||{})){try{copyPackage(dep,source,path.join(target,'node_modules'),[...ancestors,identity]);}catch(e){if(e.code!=='MODULE_NOT_FOUND'&&e.code!=='ERR_PACKAGE_PATH_NOT_EXPORTED')throw e;}}
}
for(const dep of ['pdfkit','sharp'])copyPackage(dep,root,path.join(app,'node_modules'));
require(path.join(app,'node_modules/sharp'));
fs.mkdirSync(path.join(out,'licenses'),{recursive:true});
fs.copyFileSync(path.join(root,'../vendor/Clipper2/LICENSE'),path.join(out,'licenses/Clipper2.txt'));
fs.copyFileSync(path.join(koffiDir,'LICENSE.txt'),path.join(out,'licenses/Koffi.txt'));
fs.copyFileSync(path.join(root,'README.md'),path.join(out,'使用说明.md'));
fs.copyFileSync(path.join(root,'VALIDATION.md'),path.join(out,'验证记录.md'));
console.log(out);
