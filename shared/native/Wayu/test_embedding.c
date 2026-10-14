#include "../app/Speech/WayuFrontend.h"
#include <assert.h>
#include <stdio.h>
#include <math.h>
int main(int argc,char **argv){
    assert(argc==3);assert(ot_wayu_frontend_init(argv[1]));
    int64_t tokens[502];float style[256];
    int n=ot_wayu_frontend_tokens("สวัสดีค่ะ สบายดีไหมคะ?",tokens,502);
    assert(n>5 && tokens[0]==0 && tokens[n-1]==0);
    assert(ot_wayu_frontend_style(argv[2],"f_mid_clear",n-2,style));
    for(int i=0;i<256;i++)assert(isfinite(style[i]));
    assert(ot_wayu_frontend_tokens("ราคา 250 บาท",tokens,502)>5);
    assert(ot_wayu_frontend_tokens("เรียก Grab",tokens,502)>5);
    assert(ot_wayu_frontend_tokens("xyzqqzz",tokens,502)==-1);
    assert(ot_wayu_frontend_init(argv[1]));
    puts("Embedded frontend initialization, Thai/English/numbers, styles and rejection passed.");
}
