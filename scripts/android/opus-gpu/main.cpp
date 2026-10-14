#include "backend.h"
#include "sussurro.h"
#include <iostream>
#include <iomanip>
int main(int argc,char**argv) {
 if(argc<4)return 2;
 try {
  auto begin=std::chrono::steady_clock::now();
  sussurro_model model;if(!sussurro_model_load(argv[1],model))return 3;
  auto *tokenizer=sussurro_tokenizer_create(model);
  std::cerr<<"PROBE load="<<std::chrono::duration<double>(std::chrono::steady_clock::now()-begin).count()<<"\n";
  int beam=atoi(argv[2]),repeats=atoi(argv[3]);std::string line;
  while(std::getline(std::cin,line))for(int i=0;i<repeats;++i) {
   auto &p=probe();p.compute=p.transfer=0;p.graphs=p.nodes=0;
   begin=std::chrono::steady_clock::now();
   std::string out=sussurro_translate(model,tokenizer,line,128,beam);
   double elapsed=std::chrono::duration<double>(std::chrono::steady_clock::now()-begin).count();
   std::cout<<"RESULT "<<std::fixed<<std::setprecision(6)<<elapsed<<" "<<p.compute<<" "<<p.transfer<<" "<<p.graphs<<" "<<p.nodes<<" "<<std::quoted(out)<<std::endl;
  }
  sussurro_tokenizer_free(tokenizer);sussurro_model_free(model);
 } catch(const std::exception&e){std::cerr<<"PROBE ERROR "<<e.what()<<"\n";return 4;}
}
