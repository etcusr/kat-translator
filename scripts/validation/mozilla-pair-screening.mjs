// Local-only screening of the exact Mozilla registry models in the manifest.
import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import {BatchTranslator,TranslatorBacking} from '../../.build/pair-mt/bergamot/node_modules/@browsermt/bergamot-translator/translator.js';
const root=new URL('../../',import.meta.url);
const out=new URL('docs/benchmarks/pair-mt-ru-en/',root);
const read=(name)=>fs.readFile(new URL(name,root));
class LocalBacking extends TranslatorBacking {
 async loadModelRegistery(){return [{from:'ru',to:'en'},{from:'en',to:'ru'}];}
 async loadTranslationModel({from,to}) {
  const buffer=async name=>{const b=await read(`.build/pair-mt/mozilla/${from}-${to}/${name}`);return b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength);};
  const vocab=await buffer('vocab');
  return {model:await buffer('model'),shortlist:await buffer('lexicalShortlist'),vocabs:[vocab,vocab]};
 }
}
const corpus=await read('docs/benchmarks/pair-mt-ru-en/corpus.json');
const rows=JSON.parse(corpus);
const translator=new BatchTranslator({workers:1,batchSize:1},new LocalBacking({pivotLanguage:null,cacheSize:0,useNativeIntGemm:false}));
const file=await fs.open(new URL('mozilla-results.jsonl',out),'wx');
try {
 for(const row of rows){
  const t=performance.now();const result=await translator.translate({from:row.source,to:row.target,text:row.text,html:false});
  const answer={id:row.id,text:result.target.text,seconds:(performance.now()-t)/1000};
  await file.write(JSON.stringify(answer)+'\n');console.log(answer);
 }
 await fs.writeFile(new URL('mozilla-run-metadata.json',out),JSON.stringify({node:process.version,platform:process.platform,arch:process.arch,corpus_sha256:crypto.createHash('sha256').update(corpus).digest('hex'),runtime:'@browsermt/bergamot-translator 0.4.9 WASM',workers:1,beam:1,cache:0,note:'Offline Mac WASM quality screen, not native iPhone speed. Runtime performs sentence splitting. First call per model includes loading. No external inference.'},null,2));
} finally {await file.close();translator.delete();}
