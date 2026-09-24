import json
import os
import pathlib
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / '04Reference2.ps1'


class ReferenceRecheckTests(unittest.TestCase):
    def test_workflow_and_guards(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            for folder in ['00_brief/references', '01_outline', '02_chapters']:
                (root / folder).mkdir(parents=True)
            (root / '01_outline/toc.md').write_text('## Chapter\n### Section', encoding='utf-8')
            chapter = root / '02_chapters/01.md'
            chapter.write_text('A claim [1-1].', encoding='utf-8')
            (root / '02_chapters/references.md').write_text('[1-1] Example', encoding='utf-8')
            state = {'sources': [{'id': 's1', 'title': 'Example'}],
                     'groups': [{'entries': [{'source_id': 's1', 'label': '1-1'}]}],
                     'sections': [{'file': '01.md', 'labels': ['1-1']}]}
            (root / '00_brief/references/reference_state.json').write_text(json.dumps(state))

            def run(*args, ok=True):
                result = subprocess.run([os.environ.get('SAGE_TEST_PS', 'powershell.exe'), '-NoProfile', '-ExecutionPolicy', 'Bypass',
                                         '-File', str(SCRIPT), '-BookName', 'Test', '-BookRoot', str(root),
                                         *args], capture_output=True)
                self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
                return result

            run('-Mode', 'Plan')
            runs = root / '04_output/editorial_audits/reference_rechecks'
            folder = next(runs.iterdir())
            plan = json.loads((folder / 'plan.json').read_text(encoding='utf-8-sig'))
            self.assertEqual(len(plan['tasks']), 2)
            def exported():
                return json.loads((folder / 'modification_plan.json').read_text(encoding='utf-8-sig'))
            self.assertEqual(exported()['counts']['pending'], 2)
            self.assertFalse(exported()['approval']['approved'])
            run('-Mode', 'Report', '-RunId', folder.name)
            report = next(folder.glob('report_*.json'))
            self.assertEqual(json.loads(report.read_text(encoding='utf-8-sig'))['pending'], 2)
            evidence = {'task_id': 'T0002', 'reviewer': 'test agent', 'checked_at': '2026-01-01T00:00:00Z',
                        'access': 'metadata', 'verdict': 'pass', 'verification_url': 'https://example.org',
                        'locator': 'abstract', 'evidence': 'test only', 'limitations': 'fixture',
                        'recommendation': 'none'}
            path = root / 'evidence.json'
            path.write_text(json.dumps(evidence))
            run('-Mode', 'Record', '-RunId', folder.name, '-EvidencePath', str(path), ok=False)
            evidence.update(access='abstract', verdict='partial')
            for invalid_date in ['not-a-date', '2999-01-01T00:00:00Z']:
                evidence['checked_at'] = invalid_date
                path.write_text(json.dumps(evidence))
                run('-Mode', 'Record', '-RunId', folder.name, '-EvidencePath', str(path), ok=False)
            evidence['checked_at'] = '2026-01-01T00:00:00Z'
            path.write_text(json.dumps(evidence))
            run('-Mode', 'Record', '-RunId', folder.name, '-EvidencePath', str(path))
            run('-Mode', 'Record', '-RunId', folder.name, '-EvidencePath', str(path), ok=False)
            self.assertEqual(chapter.read_text(), 'A claim [1-1].')
            self.assertEqual(exported()['counts']['pending'], 2)  # Legacy evidence is not no_change.
            evidence.update(task_id='T0001', access='metadata', verdict='pass',
                            decision={'action': 'modify', 'reason': 'Verified title correction',
                                      'changes': [{'field': 'title', 'old_value': 'WRONG',
                                                   'new_value': 'Corrected', 'reason': 'Fixture'}]})
            path.write_text(json.dumps(evidence))
            run('-Mode', 'Record', '-RunId', folder.name, '-EvidencePath', str(path), ok=False)
            evidence['decision']['changes'][0]['old_value'] = 'Example'
            path.write_text(json.dumps(evidence))
            run('-Mode', 'Record', '-RunId', folder.name, '-EvidencePath', str(path))
            changes = exported()
            self.assertEqual(changes['counts']['modify'], 1)
            self.assertEqual(changes['actions'][0]['changes'][0]['old_value'], 'Example')
            self.assertTrue(changes['actions'][0]['evidence_sha256'])
            self.assertFalse(changes['approval']['approved'])
            self.assertGreaterEqual(len(list(folder.glob('modification_plan_*.json'))), 3)
            self.assertEqual(chapter.read_text(), 'A claim [1-1].')
            before = (folder / 'modification_plan.json').read_bytes()
            chapter.write_text('Changed')
            run('-Mode', 'Report', '-RunId', folder.name, ok=False)
            self.assertEqual(before, (folder / 'modification_plan.json').read_bytes())
            run('-Mode', 'Report', '-RunId', '../outside', ok=False)
            chapter.write_text('A claim [1-1].')
            existing = set(runs.iterdir())
            run('-Mode', 'Plan')
            second = next(iter(set(runs.iterdir()) - existing))
            evidence['decision'] = {'action': 'no_change', 'reason': 'Metadata matches', 'changes': []}
            path.write_text(json.dumps(evidence))
            run('-Mode', 'Record', '-RunId', second.name, '-EvidencePath', str(path))
            evidence.update(task_id='T0002', access='unavailable', verdict='unconfirmed',
                            decision={'action': 'defer', 'reason': 'Need full text', 'changes': []})
            path.write_text(json.dumps(evidence))
            run('-Mode', 'Record', '-RunId', second.name, '-EvidencePath', str(path))
            summary = json.loads((second / 'modification_plan.json').read_text(encoding='utf-8-sig'))
            self.assertEqual(summary['counts'], {'total': 2, 'modify': 0, 'no_change': 1, 'defer': 1, 'pending': 0})


if __name__ == '__main__':
    unittest.main()
