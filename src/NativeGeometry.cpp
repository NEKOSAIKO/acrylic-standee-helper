#include "NativeGeometry.h"
#include "clipper2/clipper.h"
#include <string>
#include <cstdlib>
#include <cstring>
#include <algorithm>
using namespace Clipper2Lib;
extern "C" char *acrylic_polygon(const double *xy,const int *counts,int n,int op,double delta){
 try {PathsD paths;int k=0;for(int i=0;i<n;i++){PathD p;for(int j=0;j<counts[i];j++){p.emplace_back(xy[k],xy[k+1]);k+=2;}if(op!=4&&!IsPositive(p))std::reverse(p.begin(),p.end());if(p.size()>2)paths.push_back(p);}
 PathsD out;
 if(op==1)out=InflatePaths(Union(paths,FillRule::NonZero,5),delta,JoinType::Round,EndType::Polygon,2,5,0.008);
 else if(op==3){auto original=Union(paths,FillRule::NonZero,5);out=InflatePaths(InflatePaths(original,delta,JoinType::Round,EndType::Polygon,2,5,0.008),-delta,JoinType::Round,EndType::Polygon,2,5,0.008);out.insert(out.end(),original.begin(),original.end());out=Union(out,FillRule::NonZero,5);}
 else out=Union(paths,op==4?FillRule::EvenOdd:FillRule::NonZero,5);
 std::string s="[";bool first=true;for(auto &p:out){if(p.size()<3||std::abs(Area(p))<0.0001)continue;if(op!=4&&!IsPositive(p))continue;if(!first)s+=",";first=false;s+="[";bool f=true;for(auto &v:p){if(!f)s+=",";f=false;s+="["+std::to_string(v.x)+","+std::to_string(v.y)+"]";}s+="]";}s+="]";return strdup(s.c_str());
 }catch(...){return strdup("[]");}
}
extern "C" void acrylic_free(char *text){free(text);}
#include <vector>
#include <unordered_map>
extern "C" void acrylic_fill_holes(unsigned char *a,int w,int h,int threshold){std::vector<unsigned char> seen(w*h);std::vector<int> q;q.reserve(w*h/2);auto add=[&](int i){if(!seen[i]&&a[i]<threshold){seen[i]=1;q.push_back(i);}};for(int x=0;x<w;x++){add(x);add((h-1)*w+x);}for(int y=0;y<h;y++){add(y*w);add(y*w+w-1);}for(size_t k=0;k<q.size();k++){int i=q[k],x=i%w;if(x)add(i-1);if(x+1<w)add(i+1);if(i>=w)add(i-w);if(i+w<w*h)add(i+w);}for(int i=0;i<w*h;i++)if(!seen[i]&&a[i]<threshold)a[i]=255;}
extern "C" char *acrylic_trace(const unsigned char *a,int w,int h,int t){try{
 using K=uint64_t;std::unordered_map<K,std::vector<K>> edges;int total=0;auto key=[&](int x,int y){return K(y)*K(w+1)+x;};auto add=[&](int x,int y,int x2,int y2){edges[key(x,y)].push_back(key(x2,y2));++total;};
 for(int y=0;y<h;y++)for(int x=0;x<w;x++){int i=y*w+x;if(a[i]<t)continue;if(!y||a[i-w]<t)add(x,y,x+1,y);if(x==w-1||a[i+1]<t)add(x+1,y,x+1,y+1);if(y==h-1||a[i+w]<t)add(x+1,y+1,x,y+1);if(!x||a[i-1]<t)add(x,y+1,x,y);if(total>2000000)return strdup("[]");}
 PathsD paths;auto point=[&](K k){return PointD(double(k%(w+1)),double(k/(w+1)));};
 while(!edges.empty()){K start=edges.begin()->first,cur=start;PathD p;int prior=-1;for(int guard=0;guard<=total;guard++){auto it=edges.find(cur);if(it==edges.end())break;auto pos=point(cur);p.push_back(pos);int selected=0,best=99;for(int j=0;j<(int)it->second.size();j++){auto next=point(it->second[j]);int d=next.x>pos.x?0:next.y>pos.y?1:next.x<pos.x?2:3;int turn=prior<0?0:(d-prior+4)%4,score=turn==1?0:turn==0?1:turn==3?2:3;if(score<best){best=score;selected=j;}}K next=it->second[selected];auto np=point(next);prior=np.x>pos.x?0:np.y>pos.y?1:np.x<pos.x?2:3;it->second.erase(it->second.begin()+selected);if(it->second.empty())edges.erase(it);cur=next;if(cur==start)break;}
 if(cur==start&&p.size()>2){PathD simple;for(size_t i=0;i<p.size();i++){auto &a=p[(i+p.size()-1)%p.size()],&b=p[i],&c=p[(i+1)%p.size()];if((b.x-a.x)*(c.y-b.y)!=(b.y-a.y)*(c.x-b.x))simple.push_back(b);}if(simple.size()>2)paths.push_back(simple);}}
 std::string s="[";bool first=true;for(auto &p:paths){if(!first)s+=",";first=false;s+="[";bool f=true;for(auto &v:p){if(!f)s+=",";f=false;s+="["+std::to_string(v.x)+","+std::to_string(v.y)+"]";}s+="]";}s+="]";return strdup(s.c_str());
}catch(...){return strdup("[]");}}
