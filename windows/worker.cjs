const {parentPort,workerData}=require('node:worker_threads');
try{parentPort.postMessage({result:require('./geometry.cjs').build(workerData.source,workerData.options)});}
catch(e){parentPort.postMessage({error:e.message});}
