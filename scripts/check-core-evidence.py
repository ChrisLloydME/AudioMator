"""Require every Foundation-only core test, not merely a zero runner status."""
import importlib.util
import json
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location('test_evidence', Path(__file__).with_name('check-test-evidence.py'))
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)
try:
    result = gate.assess_core(Path(sys.argv[1]).read_text(),
        gate.inventory(Path(__file__).resolve().parents[1] / 'Tests/AudioMatorCoreLogicTests'), int(sys.argv[2]))
except (OSError, ValueError, KeyError, TypeError) as error:
    result = {'accepted': False, 'reasons': [str(error)]}
Path(sys.argv[3]).write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
raise SystemExit(0 if result['accepted'] else 1)
