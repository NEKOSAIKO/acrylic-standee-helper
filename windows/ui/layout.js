(function(root){
 function baseLayout(g,s){
  const w=s.baseWidth,h=s.baseShape==='rectangle'?s.baseLength:w,sw=s.tabWidth+s.fit,sh=s.thickness+s.fit,r=Math.min(.4,sh/4);
  if(![w,h,sw,sh].every(v=>Number.isFinite(v)&&v>0))throw Error('底座或插槽尺寸无效。');
  const mean=g.tabs.reduce((a,t)=>a+t.centerX,0)/g.tabs.length;
  const slots=g.tabs.map(t=>({x:w/2+t.centerX-mean-sw/2,y:(h-sh)/2,width:sw,height:sh,radius:r}));
  function inside(x,y){if(s.baseShape==='circle')return ((x-w/2)/(w/2))**2+((y-h/2)/(h/2))**2<1;const cr=Math.min(3,w/2,h/2);return x>0&&x<w&&y>0&&y<h&&Math.hypot(Math.max(cr-x,0,x-(w-cr)),Math.max(cr-y,0,y-(h-cr)))<=cr;}
  for(const [i,t]of slots.entries())for(const x of [t.x-.001,t.x+t.width+.001])for(const y of [t.y-.001,t.y+t.height+.001])if(!inside(x,y))throw Error(`第 ${i+1} 个插槽超出或接触底座边缘，请加大底座或缩小插脚。`);
  if(slots.length===2&&slots[0].x+sw>=slots[1].x)throw Error('两个插槽相交或接触。');
  return {width:w,height:h,slots};
 }
 root.baseLayout=baseLayout;if(typeof module!=='undefined')module.exports={baseLayout};
})(typeof window!=='undefined'?window:globalThis);
