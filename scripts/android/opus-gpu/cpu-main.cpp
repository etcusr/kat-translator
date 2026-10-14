#include "OpusRuntime.h"
#include <iostream>
#include <iomanip>
#include <chrono>
#include <cstdlib>
int main(int argc,char**argv) {
 if(argc<3)return 2;
 void *ctx=ot_opus_load(argv[1]);if(!ctx){std::cerr<<ot_opus_last_error();return 3;}
 const char *source=argc>3?argv[3]:"ru",*target=argc>4?argv[4]:"en";
 auto begin=std::chrono::steady_clock::now();
 if(ot_opus_prepare(ctx,source,target,nullptr)!=0){std::cerr<<ot_opus_last_error();return 4;}
 std::cerr<<"LOAD "<<std::chrono::duration<double>(std::chrono::steady_clock::now()-begin).count()<<"\n";
 char output[65536];std::string line;
 while(std::getline(std::cin,line))for(int i=0;i<atoi(argv[2]);++i){
  begin=std::chrono::steady_clock::now();int code=ot_opus_run(ctx,line.c_str(),source,target,nullptr,output,sizeof(output));
  if(code!=0){std::cerr<<"ERROR "<<code<<" "<<ot_opus_last_error();return 5;}
  std::cout<<"RESULT "<<std::fixed<<std::setprecision(6)<<std::chrono::duration<double>(std::chrono::steady_clock::now()-begin).count()<<" "<<std::quoted(output)<<std::endl;
 }
 ot_opus_free(ctx);
}
