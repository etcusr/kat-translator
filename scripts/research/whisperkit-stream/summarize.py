"""Print aggregate metrics only. Never publish personal transcripts or device identifiers."""
import argparse,json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--baseline',type=Path,action='append',default=[]);p.add_argument('--candidate',type=Path,action='append',default=[]);a=p.parse_args();rows=[]
for f in a.baseline:
 r=json.loads(f.read_text())[0];m=r['metric'];rows.append(dict(kind='baseline67',run=f.stem,firstCompletedTranslation=r['previews'][0]['seconds'],afterStop=m['totalSeconds'],asrCompute=m['asrSeconds'],mtCompute=m['mtSeconds'],translationBlocks=m['previewBlocks'],recognitionPasses=len(r['recognitionPasses']),peakFootprint=r['peakFootprint'],thermalStart=m['thermalState'],thermalEnd=r['thermalAtEnd']))
for f in a.candidate:
 r=json.loads(f.read_text());assert r['status']=='complete' and r['fullVerification'] is False
 rows.append(dict(kind='whisperkit',run=f.stem,firstDraft=r['firstDraftSeconds'],firstConfirmedASR=r['firstConfirmedSeconds'],firstCompletedTranslation=r['translations'][0]['finishedSeconds'],afterStop=r['afterStopSeconds'],asrAfterStop=r['asrAfterStopSeconds'],asrCompute=sum(x['seconds'] for x in r['streamPasses'])+r['tailASRSeconds'],mtCompute=sum(x['processingSeconds'] for x in r['translations']),translationBlocks=len(r['translations']),recognitionPasses=len(r['streamPasses'])+1,peakFootprint=r['peakFootprint'],thermalStart=r['thermalStart'],thermalEnd=r['thermalEnd'],thermalMax=r['thermalMax'],tailClipStart=r['tailClipStart'],loadASR=r['asrLoadSeconds']))
print(json.dumps(rows,indent=2))
