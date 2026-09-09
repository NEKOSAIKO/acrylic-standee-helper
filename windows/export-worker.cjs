const {parentPort,workerData}=require('node:worker_threads');
require('./export-pdf.cjs').exportFiles(workerData.payload,workerData.output,workerData.kind).then(result=>parentPort.postMessage({result}),e=>parentPort.postMessage({error:e.message}));
