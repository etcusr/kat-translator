"""Pixel 9 Pro benchmark guard. Thresholds are experimental controls, not safety limits."""
import argparse
import datetime
import fcntl
import json
import math
import os
from pathlib import Path
import re
import subprocess
import time

LIMITS = {'G3D': (65., 45.), 'VIRTUAL-SKIN': (38., 36.5), 'battery': (39., 37.)}
MIN_COOLDOWN = 360
COOLING_PREFIXES = ('thermal-gpufreq-', 'thermal-cpufreq-', 'thermal-uclamp-')


def parse_thermal(text):
    status = re.search(r'^Thermal Status: (\d+)', text, re.M)
    result = {'status': int(status[1]) if status else None, 'temperatures': {}, 'cooling': {}}
    # Cached temperatures may remain unchanged for hours. Never use them as a fallback.
    section = text.partition('Current temperatures from HAL:')[2]
    temperatures, _, cooling = section.partition('Current cooling devices from HAL:')
    for value, name, severity in re.findall(r'Temperature\{mValue=([^,]+), mType=[^,]+, mName=([^,]+), mStatus=(\d+)\}', temperatures):
        try:
            value = float(value)
        except ValueError:
            value = None
        result['temperatures'][name] = {'celsius': value, 'status': int(severity)}
    for value, name in re.findall(r'CoolingDevice\{mValue=(\d+), mType=[^,]+, mName=([^}]+)\}', cooling):
        result['cooling'][name] = int(value)
    return result


def reasons(snapshot, resume=False):
    failures = []
    if snapshot.get('status') != 0:
        failures.append('Android thermal status is not NONE')
    for name, limits in LIMITS.items():
        sensor = snapshot.get('temperatures', {}).get(name, {})
        value = sensor.get('celsius')
        if not isinstance(value, (int, float)) or not math.isfinite(value) or not 0 <= value <= 120:
            failures.append(f'{name}: missing/invalid fresh temperature')
        elif (value > limits[1] if resume else value >= limits[0]):
            failures.append(f'{name}: {value:.2f} C')
        if sensor.get('status') != 0:
            failures.append(f'{name}: thermal status is not NONE')
    cooling = snapshot.get('cooling', {})
    if 'thermal-gpufreq-0' not in cooling or 'thermal-cpufreq-0' not in cooling:
        failures.append('GPU/CPU cooling state missing')
    for name, value in cooling.items():
        if name.startswith(COOLING_PREFIXES) and value != 0:
            failures.append(f'{name}: frequency restriction {value}')
    return failures


def ready(snapshot, resume=False):
    return not reasons(snapshot, resume)


def cooldown_complete(elapsed, consecutive_cool):
    return elapsed >= MIN_COOLDOWN and consecutive_cool >= 2


def wait_until_cool(read, *, force=False, clock=time.monotonic, sleep=time.sleep, timeout=1200):
    start = clock()
    snapshot = read('preflight')
    if not force and ready(snapshot, resume=True):
        return
    print('Cooling: minimum 6 minutes, then two cool readings 15 seconds apart.', flush=True)
    consecutive = 0
    while True:
        if clock() - start >= timeout:
            raise TimeoutError('Pixel did not cool within 20 minutes; no benchmark started')
        sleep(15)
        snapshot = read('cooldown')
        consecutive = consecutive + 1 if ready(snapshot, resume=True) else 0
        if cooldown_complete(clock() - start, consecutive):
            return


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True, help='New directory; contains raw sensors and per-attempt logs')
    parser.add_argument('--serial', default=os.environ.get('ANDROID_SERIAL'))
    parser.add_argument('--state-dir', type=Path, default=Path(__file__).resolve().parents[2] / '.build' / 'thermal-state')
    stop = parser.add_mutually_exclusive_group(required=True)
    stop.add_argument('--stop-app', choices=['org.openoffline.translator.android'])
    stop.add_argument('--stop-executable', choices=['kat_gpu_probe', 'kat_mtp_probe'])
    parser.add_argument('--attempts', type=int, choices=range(1, 4), default=2)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('command required after --')
    # Share the cooldown obligation across separate A/B invocations, including an
    # interrupted/failed run. The lock also prevents two guards loading the phone.
    args.state_dir.mkdir(parents=True, exist_ok=True)
    key = re.sub(r'[^a-zA-Z0-9_-]', '_', args.serial or 'default')
    lock = (args.state_dir / f'{key}.lock').open('a')
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        parser.error('Another thermal-controlled benchmark is already using this device')
    needs_cooldown = args.state_dir / f'{key}.cooldown'
    args.out.mkdir(parents=True, exist_ok=False)
    (args.out / 'policy.json').write_text(json.dumps({
        'devicePolicy': 'Pixel 9 Pro', 'stopAtCelsius': {k:v[0] for k,v in LIMITS.items()},
        'resumeAtOrBelowCelsius': {k:v[1] for k,v in LIMITS.items()},
        'minimumCooldownSeconds': MIN_COOLDOWN, 'coolReadingsRequired': 2,
        'cooldownPollSeconds': 15, 'loadPollSeconds': 5, 'serial': args.serial,
        'command': command, 'attemptLimit': args.attempts,
    }, indent=2) + '\n')
    adb = ['adb'] + (['-s', args.serial] if args.serial else [])
    sequence = 0

    def read(phase):
        nonlocal sequence
        sequence += 1
        try:
            raw = subprocess.run(adb + ['shell', 'dumpsys', 'thermalservice'], check=True, capture_output=True, text=True, timeout=10).stdout
        except (subprocess.SubprocessError, OSError) as error:
            raw = f'SENSOR READ FAILED: {error}'
        (args.out / f'thermal-{sequence:04d}.txt').write_text(raw)
        snapshot = parse_thermal(raw)
        if not ready(snapshot) or (phase == 'preflight' and not ready(snapshot, resume=True)):
            needs_cooldown.write_text(datetime.datetime.now(datetime.timezone.utc).isoformat() + '\n')
        # JSON forbids NaN: preserve it in raw evidence, represent as null here.
        for sensor in snapshot['temperatures'].values():
            value = sensor['celsius']
            if value is not None and not math.isfinite(value):
                sensor['celsius'] = None
        record = {'utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'phase': phase, **snapshot,
                  'blockedBy': reasons(snapshot), 'readyToResume': ready(snapshot, resume=True)}
        with (args.out / 'thermal.jsonl').open('a') as handle:
            handle.write(json.dumps(record, allow_nan=False) + '\n')
        return snapshot

    def stop_load(process):
        remote = ['am', 'force-stop', args.stop_app] if args.stop_app else ['pkill', '-x', args.stop_executable]
        try:
            subprocess.run(adb + ['shell'] + remote, timeout=15, check=False)
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()

    results = []
    for attempt in range(1, args.attempts + 1):
        wait_until_cool(read, force=attempt > 1 or needs_cooldown.exists())
        needs_cooldown.unlink(missing_ok=True)
        invalid = []
        with (args.out / f'attempt-{attempt}.log').open('w') as log:
            process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
            started = time.monotonic()
            try:
                while process.poll() is None:
                    invalid = reasons(read(f'run-{attempt}'))
                    if invalid or time.monotonic() - started > 900:
                        invalid = invalid or ['benchmark exceeded 15 minutes']
                        stop_load(process)
                        break
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        pass
                invalid = invalid or reasons(read(f'after-{attempt}'))
            except BaseException:
                stop_load(process)
                raise
        result = {'attempt': attempt, 'returncode': process.returncode, 'thermalValid': not invalid,
                  'invalidReasons': invalid, 'seconds': time.monotonic() - started}
        results.append(result)
        (args.out / 'result.json').write_text(json.dumps({'attempts': results, 'acceptedAttempt': attempt if not invalid and process.returncode == 0 else None}, indent=2) + '\n')
        print(json.dumps(result), flush=True)
        if not invalid:
            return process.returncode
        print('Discarding timing from this attempt.', flush=True)
    return 3


if __name__ == '__main__':
    raise SystemExit(main())
