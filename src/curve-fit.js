/* Piecewise least-squares cubic fitting, chord parameterization and recursive
   error subdivision. Shared split tangents give G1 continuous joins. */
(function(root){
const add=(a,b)=>[a[0]+b[0],a[1]+b[1]],sub=(a,b)=>[a[0]-b[0],a[1]-b[1]],mul=(a,s)=>[a[0]*s,a[1]*s],dot=(a,b)=>a[0]*b[0]+a[1]*b[1],norm=a=>{let d=Math.hypot(...a);return d?mul(a,1/d):[1,0]};
function point(c,t){const u=1-t;return add(add(mul(c[0],u*u*u),mul(c[1],3*u*u*t)),add(mul(c[2],3*u*t*t),mul(c[3],t*t*t)));}
function crosses(curves){
 const points=[curves[0][0]],cross=(a,b,c)=>(b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]);
 function flatten(c,depth=0){const d=Math.hypot(...sub(c[3],c[0]))||1;if(depth>14||Math.max(Math.abs(cross(c[0],c[3],c[1])),Math.abs(cross(c[0],c[3],c[2])))/d<.005){points.push(c[3]);return;}let mid=(a,b)=>mul(add(a,b),.5),a=mid(c[0],c[1]),b=mid(c[1],c[2]),d2=mid(c[2],c[3]),e=mid(a,b),f=mid(b,d2),m=mid(e,f);flatten([c[0],a,e,m],depth+1);flatten([m,f,d2,c[3]],depth+1);}
 curves.forEach(c=>flatten(c));points.pop();const n=points.length,grid=new Map(),cell=1;
 for(let i=0;i<n;i++){const a=points[i],b=points[(i+1)%n],seen=new Set();for(let x=Math.floor(Math.min(a[0],b[0])/cell);x<=Math.floor(Math.max(a[0],b[0])/cell);x++)for(let y=Math.floor(Math.min(a[1],b[1])/cell);y<=Math.floor(Math.max(a[1],b[1])/cell);y++){let key=x+','+y,bucket=grid.get(key)||[];for(let j of bucket){if(j===i-1||i===n-1&&j===0||seen.has(j))continue;seen.add(j);let c=points[j],d=points[(j+1)%n];if(cross(a,b,c)*cross(a,b,d)<-1e-15&&cross(c,d,a)*cross(c,d,b)<-1e-15)return true;}bucket.push(i);grid.set(key,bucket);}}
 return false;
}
function handle(p,t,length,bounds){
 let d=length;for(let k=0;k<2;k++){if(t[k]>1e-12)d=Math.min(d,(bounds[k+2]-p[k])/t[k]);else if(t[k]<-1e-12)d=Math.min(d,(bounds[k]-p[k])/t[k]);}
 return add(p,mul(t,Math.max(0,d)));
}
function fit(p,t1,t2,error,bounds,depth=0){
 const n=p.length,last=n-1,dist=Math.hypot(...sub(p[last],p[0]));
 if(n===2||depth>30)return [[p[0],handle(p[0],t1,dist/3,bounds),handle(p[last],t2,dist/3,bounds),p[last]]];
 let u=[0];for(let i=1;i<n;i++)u.push(u[i-1]+Math.hypot(...sub(p[i],p[i-1])));const length=u[last];if(!length)return [];
 u=u.map(x=>x/length);let c00=0,c01=0,c11=0,x0=0,x1=0;
 for(let i=0;i<n;i++){const v=u[i],w=1-v,b0=w*w*w,b1=3*v*w*w,b2=3*v*v*w,b3=v*v*v,a1=mul(t1,b1),a2=mul(t2,b2),r=sub(p[i],add(mul(p[0],b0+b1),mul(p[last],b2+b3)));c00+=dot(a1,a1);c01+=dot(a1,a2);c11+=dot(a2,a2);x0+=dot(a1,r);x1+=dot(a2,r);}
 const det=c00*c11-c01*c01;let a=det?(x0*c11-x1*c01)/det:0,b=det?(c00*x1-c01*x0)/det:0;
 if(a<dist*1e-5||b<dist*1e-5||a>length||b>length)a=b=dist/3;
 let c=[p[0],handle(p[0],t1,a,bounds),handle(p[last],t2,b,bounds),p[last]],max=0,split=Math.floor(n/2);
 for(let i=1;i<last;i++){let d=sub(point(c,u[i]),p[i]),e=dot(d,d);if(e>max){max=e;split=i;}}
 if(max<=error*error)return [c];
 let tan=norm(sub(p[Math.max(0,split-1)],p[Math.min(last,split+1)]));
 return fit(p.slice(0,split+1),t1,tan,error,bounds,depth+1).concat(fit(p.slice(split),mul(tan,-1),t2,error,bounds,depth+1));
}
function path(loops,error){let parts=[],segments=0,fallbacks=0;const f=x=>Number(x.toFixed(5));for(let p of loops){if(p.length<3)continue;
 let ext=[0,0,0,0];for(let i=1;i<p.length;i++){if(p[i][0]<p[ext[0]][0])ext[0]=i;if(p[i][0]>p[ext[1]][0])ext[1]=i;if(p[i][1]<p[ext[2]][1])ext[2]=i;if(p[i][1]>p[ext[3]][1])ext[3]=i;}
 const bounds=[p[ext[0]][0],p[ext[2]][1],p[ext[1]][0],p[ext[3]][1]];
 let cuts=[...new Set(ext)].sort((a,b)=>a-b);if(cuts.length<2)continue;
 function tangent(i){const a=p[(i+p.length-1)%p.length],b=p[(i+1)%p.length];let t=norm(sub(b,a));if(i===ext[0]||i===ext[1])t=[0,Math.sign(t[1])||1];else if(i===ext[2]||i===ext[3])t=[Math.sign(t[0])||1,0];return t;}
 let curves=[];for(let attempt=0;attempt<4;attempt++){curves=[];for(let j=0;j<cuts.length;j++){let a=cuts[j],b=cuts[(j+1)%cuts.length],q=b>a?p.slice(a,b+1):p.slice(a).concat(p.slice(0,b+1));curves.push(...fit(q,tangent(a),mul(tangent(b),-1),error/Math.pow(2,attempt),bounds));}if(!curves.length||!crosses(curves))break;if(attempt===3){curves=p.map((a,i)=>{const b=p[(i+1)%p.length];return[a,add(a,mul(sub(b,a),1/3)),add(a,mul(sub(b,a),2/3)),b]});fallbacks++;}}
 if(!curves.length)continue;parts.push(`M ${curves[0][0].map(f).join(' ')}`);for(let c of curves){parts.push('C '+c.slice(1).flat().map(f).join(' '));segments++;}parts.push('Z');}
 return {path:parts.join(' '),segments,fallbacks};}
root.CurveFit={path,point};
})(globalThis);
