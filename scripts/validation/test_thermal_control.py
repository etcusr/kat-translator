import sys
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'android'))
from thermal_control import parse_thermal, ready, cooldown_complete, wait_until_cool

DUMP = '''Thermal Status: 0
Cached temperatures:
Temperature{mValue=25, mType=1, mName=G3D, mStatus=0}
Temperature{mValue=25, mType=3, mName=VIRTUAL-SKIN, mStatus=0}
Current temperatures from HAL:
Temperature{mValue=60, mType=1, mName=G3D, mStatus=0}
Temperature{mValue=38.5, mType=3, mName=VIRTUAL-SKIN, mStatus=1}
Temperature{mValue=39, mType=2, mName=battery, mStatus=0}
Current cooling devices from HAL:
CoolingDevice{mValue=2, mType=3, mName=thermal-gpufreq-0}
Temperature static thresholds from HAL:
'''

class ThermalControl(unittest.TestCase):
    def cool(self):
        return {'status':0, 'temperatures':{'G3D':{'celsius':40.,'status':0},'VIRTUAL-SKIN':{'celsius':36.,'status':0},'battery':{'celsius':35.,'status':0}}, 'cooling':{'thermal-gpufreq-0':0,'thermal-cpufreq-0':0}}

    def test_uses_fresh_hal_not_cached_values(self):
        self.assertEqual(parse_thermal(DUMP), {'status':0,'temperatures':{'G3D':{'celsius':60.,'status':0},'VIRTUAL-SKIN':{'celsius':38.5,'status':1},'battery':{'celsius':39.,'status':0}},'cooling':{'thermal-gpufreq-0':2}})

    def test_heat_or_active_throttling_prevents_run(self):
        self.assertTrue(ready(self.cool(),resume=True))
        for name,value in [('G3D',65.),('VIRTUAL-SKIN',38.),('battery',39.)]:
            s=self.cool();s['temperatures'][name]['celsius']=value
            self.assertFalse(ready(s),name)
        s=self.cool();s['cooling']['thermal-gpufreq-0']=1
        self.assertFalse(ready(s))
        s=self.cool();s['status']=1
        self.assertFalse(ready(s))

    def test_missing_nan_and_cached_only_are_not_safe(self):
        self.assertFalse(ready({}))
        for value in [float('nan'),-4010.,None]:
            s=self.cool();s['temperatures']['G3D']['celsius']=value
            self.assertFalse(ready(s))
        self.assertFalse(ready(parse_thermal(DUMP.split('Current temperatures from HAL:')[0])))

    def test_resume_has_hysteresis_and_minimum_six_minutes(self):
        s=self.cool();s['temperatures']['VIRTUAL-SKIN']['celsius']=37.
        self.assertTrue(ready(s));self.assertFalse(ready(s,resume=True))
        self.assertFalse(cooldown_complete(359,2))
        self.assertFalse(cooldown_complete(360,1))
        self.assertTrue(cooldown_complete(360,2))

    def test_missing_cpu_frequency_status_blocks_run(self):
        s=self.cool();del s['cooling']['thermal-cpufreq-0']
        self.assertFalse(ready(s))

    def test_real_wait_policy_uses_clock_and_two_consecutive_readings(self):
        elapsed=[0]
        def sleep(seconds): elapsed[0]+=seconds
        def read(phase):
            s=self.cool()
            # Still hot after six minutes; cannot resume based on timer alone.
            if elapsed[0] <= 360:
                s['temperatures']['G3D']['celsius']=66.
            return s
        wait_until_cool(read, clock=lambda:elapsed[0], sleep=sleep)
        self.assertEqual(elapsed[0],390)

    def test_forced_cooldown_cannot_be_shortened_by_early_cooling(self):
        elapsed=[0]
        def sleep(seconds): elapsed[0]+=seconds
        wait_until_cool(lambda phase:self.cool(),force=True,clock=lambda:elapsed[0],sleep=sleep)
        self.assertEqual(elapsed[0],360)

    def test_sensor_loss_times_out_instead_of_starting_test(self):
        elapsed=[0]
        def sleep(seconds): elapsed[0]+=seconds
        with self.assertRaises(TimeoutError):
            wait_until_cool(lambda phase:{},clock=lambda:elapsed[0],sleep=sleep,timeout=60)
        self.assertEqual(elapsed[0],60)

    def test_overheat_stops_benchmark_and_rejects_its_timing(self):
        # Exercise the real CLI/process lifecycle; only ADB sensor/device I/O is fake.
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            cool=DUMP.replace('mValue=60,','mValue=40,').replace('mValue=38.5,','mValue=36,').replace('mValue=39,','mValue=35,').replace('mStatus=1','mStatus=0').replace('mValue=2, mType=3','mValue=0, mType=3')
            cool += '\nCoolingDevice{mValue=0, mType=2, mName=thermal-cpufreq-0}\n'
            hot=cool.replace('mValue=40,','mValue=66,')
            fake=root/'adb'
            fake.write_text(f'''#!{sys.executable}
import sys
from pathlib import Path
root=Path({str(root)!r})
if sys.argv[-2:]==['dumpsys','thermalservice']:
    count=root/'count'
    n=int(count.read_text()) if count.exists() else 0
    count.write_text(str(n+1))
    print({cool!r} if n==0 else {hot!r})
else:
    (root/'stopped').write_text(' '.join(sys.argv[1:]))
''')
            fake.chmod(0o755)
            script=Path(__file__).resolve().parents[1]/'android'/'thermal_control.py'
            completed=subprocess.run([sys.executable,str(script),'--out',str(root/'result'),'--attempts','1',
                '--state-dir',str(root/'state'),
                '--stop-executable','kat_gpu_probe','--',sys.executable,'-c','import time; time.sleep(30)'],
                env={**os.environ,'PATH':str(root)+os.pathsep+os.environ['PATH']},capture_output=True,text=True,timeout=10)
            self.assertEqual(completed.returncode,3,completed.stderr)
            report=json.loads((root/'result'/'result.json').read_text())
            self.assertIsNone(report['acceptedAttempt'])
            self.assertFalse(report['attempts'][0]['thermalValid'])
            self.assertIn('pkill -x kat_gpu_probe',(root/'stopped').read_text())
            self.assertEqual(len(list((root/'state').glob('*.cooldown'))),1)
