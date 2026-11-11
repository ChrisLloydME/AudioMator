"""Validate the complete app test inventory against xcresult's named leaves.

Summary counts alone cannot establish that provider/editor tests ran. This gate
requires every source-declared XCTest and a frozen set of critical identities.
It accepts no skips, expected failures, duplicate leaves or incomplete results.
"""
import argparse
import json
from pathlib import Path
import re

CRITICAL = {
    'MetadataSaveJourneyTests/testEveryProviderSelectionAcrossAllDatePresenceStates()',
    'MetadataBoundaryMatrixTests/testEveryDedicatedStringAcrossAllDatePresenceStates()',
    'MetadataBoundaryMatrixTests/testEveryCSVFieldPlansWritesAndReloadsThroughRealAdapter()',
    'MetadataBoundaryMatrixTests/testExchangeAndProviderFieldInventoriesCannotGrowWithoutCases()',
    'MetadataSaveJourneyTests/testAllDatePresenceStatesThroughDisplayedSaveJourneys()',
    'MetadataSaveJourneyTests/testiTunesEachCheckedFieldWritesAndUncheckedFieldsSurvive()',
    'MetadataSaveJourneyTests/testMusicBrainzEachCheckedReleaseFieldWritesAndUncheckedFieldsSurvive()',
    'MetadataSaveJourneyTests/testMetadataEditorDraftAddReplaceDeletePersistsArraysAndRefreshes()',
    'MetadataSaveJourneyTests/testInspectorNoOpAndRevertedBatchNeverWriteDiskThenRealSaveBecomesClean()',
    'MappingPackageConformanceTests/testPackageMP4LyricsPreservesAbsentYearWithStandaloneDate()',
    'MappingPackageConformanceTests/testAppMP4CommentPreservesAbsentYearWithStandaloneDate()',
}


def inventory(root):
    result = set()
    for path in sorted(root.rglob('*.swift')):
        source = path.read_text()
        declarations = re.finditer(r'\bclass\s+(\w+)\s*:\s*XCTestCase\b|\bfunc\s+(test\w+)\s*\(', source)
        owner = None
        for declaration in declarations:
            if declaration.group(1):
                owner = declaration.group(1)
            else:
                if owner is None:
                    raise ValueError(f'Cannot attribute XCTest in {path}')
                identity = f'{owner}/{declaration.group(2)}()'
                if identity in result:
                    raise ValueError(f'Duplicate XCTest identity: {identity}')
                result.add(identity)
    return result


def leaves(nodes):
    for node in nodes:
        if node['nodeType'] == 'Test Case':
            yield node
        yield from leaves(node.get('children', []))


def assess_core(log, expected, runner_status):
    passed = re.findall(r"Test Case '-\[([^\]\s]+) (test\w+)\]' passed", log)
    names = [owner.split('.')[-1] + '/' + method + '()' for owner, method in passed]
    summaries = re.findall(r'Executed (\d+) tests, with (\d+) failures', log)
    accepted = (runner_status == 0 and len(expected) >= 62 and set(names) == expected
        and len(names) == len(expected) and bool(summaries)
        and int(summaries[-1][0]) == len(expected)
        and all(int(failures) == 0 for _, failures in summaries)
        and not re.search(r"Test Case '.+' (?:failed|skipped)", log))
    return {'accepted': bool(accepted), 'expected': len(expected), 'executed': len(names),
            'missing': sorted(expected - set(names)), 'unexpected': sorted(set(names) - expected)}


def assess(summary, tree, expected, runner_status):
    nodes = list(leaves(tree['testNodes']))
    names = [node['nodeIdentifier'] for node in nodes]
    actual = set(names)
    reasons = []
    if runner_status != 0:
        reasons.append('Nonzero test runner status')
    if not CRITICAL <= expected:
        reasons.append('Critical tests removed from source inventory')
    if len(expected) < 579:
        reasons.append('Source inventory shrank below reviewed baseline')
    if actual != expected:
        reasons.append('Executed identities do not equal the complete source inventory')
    if len(names) != len(actual):
        reasons.append('Duplicate test execution identities')
    if any(node.get('result') != 'Passed' for node in nodes):
        reasons.append('Named failed, skipped, expected-failure or incomplete test')
    if any('/AudioMatorTests/' not in node.get('nodeIdentifierURL', '') for node in nodes):
        reasons.append('Evidence belongs to a different test target')
    if (summary.get('result') != 'Passed'
            or summary.get('totalTestCount') != len(expected)
            or summary.get('passedTests') != len(expected)
            or any(summary.get(key) != 0 for key in ('failedTests', 'skippedTests', 'expectedFailures'))):
        reasons.append('Summary is incomplete, inconsistent or unsuccessful')
    return {'accepted': not reasons, 'reasons': reasons, 'expected': len(expected),
            'executed': len(nodes), 'missing': sorted(expected - actual),
            'unexpected': sorted(actual - expected)}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('summary', type=Path)
    parser.add_argument('tree', type=Path)
    parser.add_argument('runner_status', type=int)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    try:
        result = assess(json.loads(args.summary.read_text()), json.loads(args.tree.read_text()),
                        inventory(Path(__file__).resolve().parents[1] / 'AudioMatorTests'), args.runner_status)
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        result = {'accepted': False, 'reasons': [str(error)]}
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result['accepted'] else 1)
