import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ENGINE = Path(__file__).resolve().parents[1]


class ReferenceExecutorTests(unittest.TestCase):
    def test_preview_approval_apply_and_stale_rejection(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for directory in ['00_brief/references', '01_outline', '02_chapters']:
                (root / directory).mkdir(parents=True)
            text = '### 1.1 Test\n\nClaim [1-1].\n'
            chapter = root / '02_chapters/01.md'
            chapter.write_text(text, encoding='utf-8')
            (root / '01_outline/toc.md').write_text('## \u7b2c1\u7ae0 Test\n### 1.1 Test\n', encoding='utf-8')
            source = dict(id='s1', authors=['Author'], title='Title', year=2020,
                          publication='Publisher', url='https://example.org/old',
                          verification_url='https://example.org/check')
            state = dict(schema_version=1, sources=[source],
                         groups=[dict(order=1, title='Chapter 1', entries=[dict(label='1-1', source_id='s1')])],
                         sections=[dict(file='01.md', labels=['1-1'], after_sha256=hashlib.sha256(text.encode()).hexdigest())])
            statepath = root / '00_brief/references/reference_state.json'
            statepath.write_text(json.dumps(state), encoding='utf-8')
            refs = root / '02_chapters/references.md'
            refs.write_text('---\nfile_role: references\ngenerated_by: 04R\n---\n\n# \u53c2\u8003\u6587\u732e\n\n## Chapter 1\n\n[1-1] Author. (2020). Title. Publisher. https://example.org/old\n', encoding='utf-8')
            marker = root / '00_brief/format_preflight.json'
            marker.write_text('{}')

            def run(script, *args, ok=True):
                r = subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                                    '-File', str(ENGINE / script), '-BookName', 'Test', '-BookRoot', str(root),
                                    *args], capture_output=True)
                self.assertEqual(r.returncode == 0, ok, r.stdout + r.stderr)
                return r

            run('04R.ps1', '-Mode', 'Check')
            run('04Reference2.ps1', '-Mode', 'Plan')
            folder = next((root / '04_output/editorial_audits/reference_rechecks').iterdir())
            evidence = dict(task_id='T0001', reviewer='Test', checked_at='2026-01-01T00:00:00Z',
                            access='metadata', verdict='pass', verification_url='https://example.org/new',
                            locator='metadata', evidence='fixture', limitations='fixture', recommendation='update',
                            decision=dict(action='modify', reason='update URL', changes=[dict(
                                field='url', old_value='https://example.org/old',
                                new_value='https://example.org/new', reason='fixture')]))
            ep = root / 'evidence.json'
            ep.write_text(json.dumps(evidence))
            run('04Reference2.ps1', '-Mode', 'Record', '-RunId', folder.name, '-EvidencePath', str(ep))
            latest = folder / 'modification_plan.json'
            plan = json.loads(latest.read_text(encoding='utf-8-sig'))
            approved = folder / 'approved.json'
            approved.write_text(json.dumps(plan))
            before = {p: p.read_bytes() for p in (chapter, statepath, refs, marker)}
            run('04Reference3.ps1', '-PlanPath', str(approved))
            self.assertEqual(before, {p: p.read_bytes() for p in before})
            run('04Reference3.ps1', '-PlanPath', str(approved), '-Mode', 'Apply', ok=False)
            plan['approval'] = dict(approved=True, approved_by='Test user',
                                    approved_at='2026-01-01T00:00:00Z', task_ids=['T0001', 'T0002'])
            approved.write_text(json.dumps(plan))
            run('04Reference3.ps1', '-PlanPath', str(approved), '-Mode', 'Apply', ok=False)
            plan['approval']['task_ids'] = ['T0001']
            plan['actions'][0]['changes'][0]['new_value'] = 'https://example.org/tampered'
            approved.write_text(json.dumps(plan))
            run('04Reference3.ps1', '-PlanPath', str(approved), '-Mode', 'Apply', ok=False)
            plan['actions'][0]['changes'][0]['new_value'] = 'https://example.org/new'
            approved.write_text(json.dumps(plan))
            run('04Reference3.ps1', '-PlanPath', str(approved), '-Mode', 'Apply')
            self.assertEqual(chapter.read_bytes(), before[chapter])
            self.assertFalse(marker.exists())
            self.assertEqual(json.loads(statepath.read_text(encoding='utf-8-sig'))['sources'][0]['url'], 'https://example.org/new')
            self.assertIn('https://example.org/new', refs.read_text(encoding='utf-8-sig'))
            run('04R.ps1', '-Mode', 'Check')
            backups = list((root / 'back').glob('reference3_*'))
            self.assertEqual(len(backups), 1)
            self.assertEqual((backups[0] / 'reference_state.json').read_bytes(), before[statepath])
            run('04Reference3.ps1', '-PlanPath', str(approved), '-Mode', 'Apply', ok=False)
            self.assertFalse((root / '00_brief/references/reference3.lock').exists())
            # Force the post-write check to fail in an isolated executor copy.
            for p, data in before.items():
                p.write_bytes(data)
            isolated = root / 'isolated_engine'
            isolated.mkdir()
            (isolated / '04Reference3.ps1').write_bytes((ENGINE / '04Reference3.ps1').read_bytes())
            (isolated / '04R.ps1').write_text(
                "param($BookName,$BookRoot,$Mode)\n"
                "$p=Join-Path $PSScriptRoot 'called'\n"
                "if(Test-Path $p){exit 1}\n"
                "[IO.File]::WriteAllText($p,'first check passed')\nexit 0\n", encoding='ascii')
            run(str(isolated / '04Reference3.ps1'), '-PlanPath', str(approved), '-Mode', 'Apply', ok=False)
            self.assertEqual(before, {p: p.read_bytes() for p in before})
            reports = [json.loads(p.read_text(encoding='utf-8-sig')) for p in
                       (root / '04_output/editorial_audits/reference_executions').glob('*/execution.json')]
            self.assertTrue(any(r['status'] == 'rolled_back' for r in reports))


if __name__ == '__main__':
    unittest.main()
