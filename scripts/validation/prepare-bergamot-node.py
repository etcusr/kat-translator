"""Compatibility shim for the pinned Bergamot0.4.9 npm worker on Node ESM."""
from pathlib import Path
p=Path(__file__).resolve().parents[2]/'.build/pair-mt/bergamot/node_modules/@browsermt/bergamot-translator/worker/translator-worker.js'
s=p.read_text();marker='// Local Node ESM compatibility shim; translation/WASM code unchanged.\n'
if not s.startswith(marker):
 p.write_text(marker+'''import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {dirname} from 'node:path';
const require=createRequire(import.meta.url);
const __filename=fileURLToPath(import.meta.url);
const __dirname=dirname(__filename);
globalThis.require=require;
globalThis.__filename=__filename;
globalThis.__dirname=__dirname;
'''+s)
