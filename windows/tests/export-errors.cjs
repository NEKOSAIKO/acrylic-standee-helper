const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const {exportFiles,validate}=require('../export-pdf.cjs');
(async()=>{const dir=path.resolve(process.argv[2]);const record=JSON.parse(fs.readFileSync(path.join(dir,'export-result.json'))),audit=record.pdf.audit;
const payload={geometry:JSON.parse(fs.readFileSync(path.join(dir,'geometry.json'))),settings:audit.sourceSettings,pngData:'data:image/png;base64,'+fs.readFileSync(path.join(dir,'source.png')).toString('base64'),whiteAlpha:fs.readFileSync(path.join(dir,'white-alpha.bin'))};
const checks=[];for(const kind of ['pdf','ai']){const file=record[kind].output;const hash=()=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');const before=hash();await assert.rejects(exportFiles(payload,file,kind),/同名文件已经存在/);assert.equal(hash(),before);checks.push(kind+' rejects overwrite and retains original bytes');}
for(const setting of [{whiteInset:1},{whiteFill:true},{whiteVector:true}]){assert.throws(()=>validate({...payload,settings:{...payload.settings,...setting}}),/尚未支持/);checks.push('unsupported '+Object.keys(setting)[0]+' rejected');}
assert.throws(()=>validate({...payload,geometry:{...payload.geometry,tabReferenceOnly:false}}),/独立主体/);checks.push('merged tab geometry rejected');
const result={ok:true,checks};fs.writeFileSync(path.join(dir,'error-path-audit.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));})().catch(e=>{console.error(e);process.exitCode=1});
