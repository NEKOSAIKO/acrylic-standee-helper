#include "../../src/NativeGeometry.h"
extern "C" __declspec(dllexport) char* win_polygon(const double* xy,const int* counts,int n,int op,double delta) {
    return acrylic_polygon(xy,counts,n,op,delta);
}
extern "C" __declspec(dllexport) void win_free(char* value) { acrylic_free(value); }
extern "C" __declspec(dllexport) void win_fill(unsigned char* a,int w,int h,int t) { acrylic_fill_holes(a,w,h,t); }
