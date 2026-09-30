import hashlib
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ENGINE = Path(__file__).resolve().parents[1]


class WorkflowStatus(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.put('00_brief/objective.md', '# Book\nA useful book.')

    def put(self, name, text):
        p = self.root / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding='utf-8')
        return p

    def run_status(self, *args):
        r = subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                            '-File', str(ENGINE / 'Get-SageWriteWorkflowStatus.ps1'),
                            '-BookName', 'Fixture', '-BookRoot', str(self.root), *args],
                           capture_output=True, timeout=45)
        self.assertEqual(r.returncode, 0, r.stderr.decode(errors='replace'))
        return json.loads(r.stdout.decode('utf-8-sig'))

    def stages(self, r):
        return {s['id']: s['state'] for s in r['stages']}

    def fixture(self):
        self.put('01_outline/toc.md', '## Chapter\n### 1.1 First\n### 1.2 Second\n')
        self.put('02_chapters/01.md', '### 1.1 First\n\nActual prose.\n')

    def test_objective_only_read_only(self):
        before = {p: p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        r = self.run_status()
        self.assertEqual(self.stages(r)['outline'], 'missing')
        self.assertEqual(r['counts']['expected'], 0)
        self.assertEqual(before, {p: p.read_bytes() for p in self.root.rglob('*') if p.is_file()})

    def test_partial_and_completion_not_approval(self):
        self.fixture()
        r = self.run_status('-Details')
        self.assertEqual(r['counts']['drafts_present'], 1)
        self.assertEqual(self.stages(r)['drafting'], 'partial')
        self.put('02_chapters/02.md', '### 1.2 Second\n\nMore prose.')
        self.assertEqual(self.stages(self.run_status())['drafting'], 'present_unverified')

    def test_bad_heading_empty_and_extra(self):
        self.fixture()
        self.put('02_chapters/01.md', '### Wrong\n\nText.')
        self.put('02_chapters/02.md', '### 1.2 Second\n')
        self.put('02_chapters/03.md', 'Old leftover')
        r = self.run_status('-Details')
        self.assertEqual(self.stages(r)['drafting'], 'blocked')
        self.assertEqual(r['counts']['extra_files'], 1)
        self.assertTrue(all(u['state'] == 'blocked' for u in r['units']))

    def test_save_unique_full_snapshot_compact_response(self):
        self.fixture()
        a = self.run_status('-SaveReport')
        b = self.run_status('-SaveReport')
        self.assertNotEqual(a['report_path'], b['report_path'])
        self.assertNotIn('inputs', a)
        full = json.loads(Path(a['report_path']).read_text(encoding='utf-8'))
        self.assertEqual(len(full['units']), 2)
        self.assertTrue(full['stable'])

    def test_reference_baseline_stale(self):
        self.fixture()
        text = (self.root / '02_chapters/01.md').read_text(encoding='utf-8')
        self.put('00_brief/references/reference_state.json', json.dumps({'sections': [
            {'file': '01.md', 'after_sha256': hashlib.sha256(text.encode()).hexdigest()}]}))
        self.assertEqual(self.stages(self.run_status())['references'], 'present_unverified')
        self.put('02_chapters/01.md', text + '\nChanged.')
        self.assertEqual(self.stages(self.run_status())['references'], 'stale')

    def test_export_not_approved_and_bad_log(self):
        self.fixture()
        self.put('04_output/zh/book.pdf', 'not a real PDF')
        self.put('logs/status.json', '{bad')
        r = self.run_status()
        self.assertEqual(self.stages(r)['pdf'], 'present_unverified')
        self.assertTrue(r['warnings'])

    def test_native_stamp_preserved_on_staleness(self):
        self.put('01_outline/toc.md', '## Chapter\n### 1.1 First\n')
        md = self.put('02_chapters/01.md', '### 1.1 First\n\nActual prose.\n')
        result = subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                                 '-File', str(ENGINE / '04F.ps1'), '-BookName', 'Fixture',
                                 '-BookRoot', str(self.root), '-Mode', 'Check'], capture_output=True, timeout=45)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
        self.assertEqual(self.stages(self.run_status())['format'], 'current')
        stamp = self.root / '00_brief/format_preflight.json'
        original = stamp.read_bytes()
        md.write_text(md.read_text() + '\nChanged.', encoding='utf-8')
        self.assertEqual(self.stages(self.run_status())['format'], 'stale')
        self.assertEqual(stamp.read_bytes(), original)

    def test_chapter_mode(self):
        self.put('01_outline/toc.md', '## First\n')
        self.put('02_chapters/01.md', '# First\n\nProse.')
        self.assertEqual(self.run_status()['counts']['drafts_present'], 1)


if __name__ == '__main__':
    unittest.main()
