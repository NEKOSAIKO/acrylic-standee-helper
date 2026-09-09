const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const koffi = require('koffi');
const dll = koffi.load(path.join(__dirname, 'native/acrylic.dll'));
const polygon = dll.func('void* win_polygon(const double*, const int*, int, int, double)');
const release = dll.func('void win_free(void*)');
const coreDir = fs.existsSync(path.join(__dirname,'core')) ? path.join(__dirname,'core') : path.join(__dirname,'../src');
function context() {
  const c = vm.createContext({ NativeCancelled:()=>false, NativePolygon:(json,op,delta)=>{
    const loops=JSON.parse(json), counts=loops.map(p=>p.length), xy=loops.flat(2);
    const ptr=polygon(xy,counts,counts.length,op,delta);
    if(!ptr) throw Error('Clipper2 返回空指针');
    try{return koffi.decode(ptr,'char',-1);}finally{release(ptr);}
  }});
  for(const f of ['curve-fit.js','acrylic-geometry.js']) vm.runInContext(fs.readFileSync(path.join(coreDir,f),'utf8'),c);
  return c;
}
function build(source,options) {
  // A fresh context is essential: upstream trace cache is keyed only by threshold.
  const c=context(); c.source=source; c.options=options;
  return vm.runInContext('AcrylicGeometry.build(source,options)',c);
}
module.exports={build};
