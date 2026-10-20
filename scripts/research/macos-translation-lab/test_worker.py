"""Opt-in real Metal regression: resident worker preserves baseline translations."""
import json
from pathlib import Path
import subprocess
import select
import time
import unittest

ROOT = Path(__file__).resolve().parents[3]
PYTHON = ROOT / '.build/mac-index-mlx-mtp/venv/bin/python'
RUNNER = Path(__file__).with_name('kat_runner.py')

class ResidentWorkerTests(unittest.TestCase):
    def test_reuse_and_identical_outputs(self):
        cases = json.loads((ROOT/'tests/fixtures/mac-system-translation.json').read_text())
        baseline = json.loads((ROOT/'docs/benchmarks/mac-system-translation-2026-10-20/index9b.json').read_text())
        expected = {x['id']: x['output'] for x in baseline['results']}
        child = subprocess.Popen([str(PYTHON),str(RUNNER),'index9b','--serve'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        def response():
            self.assertTrue(select.select([child.stdout], [], [], 90)[0], "Worker response timeout")
            line = child.stdout.readline()
            self.assertTrue(line, 'Worker exited: '+(child.stderr.read() if child.poll() is not None else 'no response'))
            return json.loads(line)
        try:
            results = []
            for repeat in range(2):
                for case in cases:
                    started = time.perf_counter()
                    child.stdin.write(json.dumps(case,ensure_ascii=False)+'\n');child.stdin.flush()
                    result = response()
                    self.assertEqual(result['code'],0)
                    self.assertEqual(result['output'],expected[case['id']])
                    self.assertEqual(result['model_reused'],bool(results))
                    self.assertEqual(result['idle_timeout_seconds'],300)
                    if results: self.assertEqual(result['load_seconds'],0)
                    else: self.assertGreater(result['load_seconds'],0)
                    result['end_to_end_seconds'] = time.perf_counter()-started
                    results.append(result)
            child.stdin.write('{}\n');child.stdin.flush()
            self.assertIn('error',response())
            child.stdin.write(json.dumps(cases[0])+'\n');child.stdin.flush()
            self.assertEqual(response()['output'],expected[cases[0]['id']])
            def configure(seconds):
                child.stdin.write(json.dumps(dict(command='configure',idle_timeout_seconds=seconds))+'\n')
                child.stdin.flush()
                return response()
            for invalid in (0, 3601, True, '600'):
                self.assertIn('error',configure(invalid))
            self.assertEqual(configure(600),{'idle_timeout_seconds':600})
            child.stdin.write(json.dumps(cases[0])+'\n');child.stdin.flush()
            configured = response()
            self.assertEqual(configured['idle_timeout_seconds'],600)
            self.assertTrue(configured['model_reused'])
            self.assertEqual(configured['load_seconds'],0)
            self.assertEqual(configured['output'],expected[cases[0]['id']])
            self.assertEqual(configure(2),{'idle_timeout_seconds':2})
            started = time.perf_counter()
            child.wait(timeout=10)
            idle_elapsed = time.perf_counter()-started
            self.assertGreaterEqual(idle_elapsed,1.8)
            self.assertLess(idle_elapsed,8)
            child.stdin.close()
            self.assertEqual(child.returncode,0)
            path=ROOT/'.build/mac-mlx-latency-2026-10-20/resident-regression.json'
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n')
            path.with_name('idle-settings.json').write_text(json.dumps(dict(
                default_seconds=300,configured_result=configured,
                rejected_timeouts=[0,3601,True,'600'],test_idle_seconds=2,
                observed_exit_seconds=idle_elapsed,exit_code=child.returncode),
                ensure_ascii=False,indent=2)+'\n')
        finally:
            if child.poll() is None: child.terminate();child.wait(timeout=20)
            if not child.stdin.closed:child.stdin.close()
            child.stdout.close();child.stderr.close()

if __name__=='__main__':unittest.main()
