import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('gate', Path(__file__).resolve().parents[1] / 'check-test-evidence.py')
GATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GATE)


class TestEvidencePolicy(unittest.TestCase):
    def setUp(self):
        count = GATE.APP_TEST_FLOOR + 1
        self.expected = GATE.CRITICAL | {f'OtherTests/test{i}()' for i in range(count - len(GATE.CRITICAL))}
        self.summary = dict(result='Passed', totalTestCount=count, passedTests=count,
                            failedTests=0, skippedTests=0, expectedFailures=0)
        self.tree = {'testNodes': [dict(nodeType='Test Case', nodeIdentifier=name, result='Passed',
            nodeIdentifierURL='test://AudioMator/AudioMatorTests/' + name) for name in sorted(self.expected)]}

    def accepted(self, status=0):
        return GATE.assess(self.summary, self.tree, self.expected, status)['accepted']

    def test_complete_inventory_passes(self):
        self.assertTrue(self.accepted())

    def test_count_only_or_filtered_run_fails(self):
        self.tree['testNodes'].pop()
        self.assertFalse(self.accepted())

    def test_disguised_critical_class_fails(self):
        self.tree['testNodes'][0]['nodeIdentifier'] = 'InjectedTests/' + self.tree['testNodes'][0]['nodeIdentifier'].split('/')[1]
        self.assertFalse(self.accepted())

    def test_duplicate_cannot_replace_missing_test(self):
        self.tree['testNodes'][0] = copy.deepcopy(self.tree['testNodes'][1])
        self.assertFalse(self.accepted())

    def test_failure_skip_unknown_and_expected_failure_fail(self):
        for outcome in ('Failed', 'Skipped', 'Expected Failure', 'Running', None):
            with self.subTest(outcome=outcome):
                self.tree['testNodes'][0]['result'] = outcome
                self.assertFalse(self.accepted())

    def test_summary_cannot_hide_named_failure(self):
        self.tree['testNodes'][0]['result'] = 'Failed'
        self.assertFalse(self.accepted())

    def test_nonzero_status_cannot_hide_behind_success(self):
        self.assertFalse(self.accepted(1))

    def test_wrong_target_fails(self):
        self.tree['testNodes'][0]['nodeIdentifierURL'] = 'test://Another/OtherTests/testA'
        self.assertFalse(self.accepted())

    def test_deleted_critical_source_test_fails(self):
        self.expected.remove(next(iter(GATE.CRITICAL)))
        self.assertFalse(self.accepted())

    def test_incomplete_or_inconsistent_summary_fails(self):
        original = self.summary.copy()
        for key in original:
            with self.subTest(missing=key):
                self.summary = {k: v for k, v in original.items() if k != key}
                self.assertFalse(self.accepted())

    def test_current_source_inventory_has_critical_cases(self):
        expected = GATE.inventory(Path(__file__).resolve().parents[2] / 'AudioMatorTests')
        self.assertGreaterEqual(len(expected), GATE.APP_TEST_FLOOR)
        self.assertLessEqual(GATE.CRITICAL, expected)

    def test_current_core_source_inventory_has_critical_cases(self):
        expected = GATE.inventory(Path(__file__).resolve().parents[2] / 'Tests/AudioMatorCoreLogicTests')
        self.assertGreaterEqual(len(expected), GATE.CORE_TEST_FLOOR)
        self.assertLessEqual(GATE.CORE_CRITICAL, expected)

    def test_cli_malformed_or_changed_json_fails_closed_with_record(self):
        for summary, tree in (('{', '{}'), ('[]', '{}'), ('{}', '{"testNodes":[{}]}')):
            with self.subTest(summary=summary, tree=tree), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / 'summary').write_text(summary)
                (root / 'tree').write_text(tree)
                result = subprocess.run(['python3', str(SPEC.origin), str(root / 'summary'),
                    str(root / 'tree'), '0', str(root / 'result')], capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(json.loads((root / 'result').read_text())['accepted'])

    def test_core_inventory_requires_named_complete_execution(self):
        count = GATE.CORE_TEST_FLOOR + 1
        expected = GATE.CORE_CRITICAL | {f'CoreTests/test{i}()' for i in range(count - len(GATE.CORE_CRITICAL))}

        def passing_log(identities):
            lines = [
                f"Test Case '-[AudioMatorCoreLogicTests.{identity[:-2].replace('/', ' ')}]' passed (0.001 seconds)."
                for identity in sorted(identities)
            ]
            return '\n'.join(lines) + f'\nExecuted {len(identities)} tests, with 0 failures\n'

        log = passing_log(expected)
        first_line = log.splitlines()[0]
        self.assertTrue(GATE.assess_core(log, expected, 0)['accepted'])
        for tampered in (log.replace(first_line, ''), log.replace('CoreTests test0', 'OtherTests test0'),
                         log.replace('with 0 failures', 'with 1 failures'), log.split('Executed')[0],
                         log + "Test Case '-[OtherTests testX]' skipped"):
            self.assertFalse(GATE.assess_core(tampered, expected, 0)['accepted'])
        self.assertFalse(GATE.assess_core(log, expected, 1)['accepted'])
        missing_critical = expected - {next(iter(GATE.CORE_CRITICAL))}
        self.assertFalse(GATE.assess_core(passing_log(missing_critical), missing_critical, 0)['accepted'])
        below_floor = expected - {'CoreTests/test0()', 'CoreTests/test1()'}
        self.assertFalse(GATE.assess_core(passing_log(below_floor), below_floor, 0)['accepted'])


if __name__ == '__main__':
    unittest.main()
