#!/usr/bin/env python3
"""Inspect the pinned Mac ONNX provider after initialization, with network denied.

Uses local symbol offsets in the supplied dylib; changed/stripped symbols fail
rather than guessing. This checks provider state, not full app traffic or ASR.
"""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CI_VARIABLES = ('CI', 'TF_BUILD', 'GITHUB_ACTIONS', 'GITLAB_CI', 'CIRCLECI', 'TRAVIS',
                'JENKINS_URL', 'CODEBUILD_BUILD_ID', 'BUILDKITE', 'TEAMCITY_VERSION',
                'APPVEYOR', 'BITBUCKET_BUILD_NUMBER', 'SYSTEM_TEAMFOUNDATIONCOLLECTIONURI',
                'ORT_RUNNING_UNIT_TESTS')


def check(library):
    symbols = subprocess.check_output(['nm', '-a', str(library)], text=True, errors='replace')
    offsets = []
    for suffix in ('19telemetry_disabled_E', '7logger_E', '12log_manager_E'):
        name = '__ZN11onnxruntime14PosixTelemetry' + suffix
        matches = re.findall(r'^([0-9a-fA-F]+)\s+\S\s+' + re.escape(name) + r'$', symbols, re.M)
        if len(matches) != 1:
            raise RuntimeError('Review changed ONNX telemetry provider: missing/ambiguous ' + name)
        offsets.append(matches[0])
    with tempfile.TemporaryDirectory(prefix='kat-onnx-privacy-') as directory:
        probe = Path(directory) / 'probe'
        subprocess.run(['clang', '-I' + str(ROOT), '-I' + str(ROOT / 'Dependencies/build/macos/headers'),
                        str(ROOT / 'scripts/validation/fixtures/onnx_telemetry_probe.c'),
                        str(ROOT / 'shared/native/app/Privacy/InferencePrivacy.c'), '-o', str(probe)], check=True)
        environment = {k: v for k, v in os.environ.items() if k not in CI_VARIABLES}
        environment['ORT_DISABLE_TELEMETRY'] = '0'  # Kat must override this; no CI-based false pass.
        subprocess.run(['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)',
                        str(probe), str(library.resolve()), *offsets], env=environment, check=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('library', type=Path)
    check(parser.parse_args().library)
