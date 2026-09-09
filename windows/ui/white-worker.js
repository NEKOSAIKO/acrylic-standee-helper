onmessage=async({data:d})=>{try{
 const {bitmap,s,g,strokes}=d,w=bitmap.width,h=bitmap.height;
 const canvas=new OffscreenCanvas(w,h),c=canvas.getContext('2d',{willReadFrequently:true});
 c.drawImage(bitmap,0,0);bitmap.close();const pixels=c.getImageData(0,0,w,h),a=pixels.data,t=Math.max(1,Math.round(s.threshold*2.55));
 for(let i=0;i<a.length;i+=4){a[i]=a[i+1]=a[i+2]=0;if(!s.whiteFollowsAlpha)a[i+3]=a[i+3]>=t?255:Math.floor(a[i+3]*255/t);}
 c.putImageData(pixels,0,0);c.save();const b=g.imageBox;
 c.setTransform(w/b.width,0,0,h/b.height,-b.x*w/b.width,-b.y*h/b.height);c.clip(new Path2D(g.bodyOnlyPath),'evenodd');c.resetTransform();c.fillStyle='#000';c.strokeStyle='#000';c.lineCap='round';c.lineJoin='round';
 for(const stroke of strokes){const p=stroke.points[0],r=stroke.radius*h;c.beginPath();c.arc(p.x*w,p.y*h,r,0,Math.PI*2);c.fill();c.beginPath();c.lineWidth=r*2;c.moveTo(p.x*w,p.y*h);for(const q of stroke.points.slice(1))c.lineTo(q.x*w,q.y*h);c.stroke();}
 c.restore();const painted=c.getImageData(0,0,w,h).data,alpha=new Uint8Array(w*h);for(let i=0;i<alpha.length;i++)alpha[i]=painted[i*4+3];const output=canvas.transferToImageBitmap();postMessage({bitmap:output,alpha,width:w,height:h},[output,alpha.buffer]);
}catch(e){postMessage({error:e.message});}};
