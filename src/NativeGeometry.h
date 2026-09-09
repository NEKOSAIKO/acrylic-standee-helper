#pragma once
#ifdef __cplusplus
extern "C" {
#endif
char *acrylic_polygon(const double *xy,const int *counts,int n,int operation,double delta);
void acrylic_fill_holes(unsigned char *mask,int width,int height,int threshold);
char *acrylic_trace(const unsigned char *mask,int width,int height,int threshold);
void acrylic_free(char *text);
#ifdef __cplusplus
}
#endif
