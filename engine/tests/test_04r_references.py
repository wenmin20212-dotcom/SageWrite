import copy
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / '04R.ps1'


class ReferenceWorkflow(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / '01_outline').mkdir()
        (self.root / '02_chapters').mkdir()
        (self.root / '01_outline/toc.md').write_text(
            '## 前言\n### Opening\n## 第1章：Learning\n### 1.1 Learning\n', encoding='utf-8')
        for name, title in [('01.md', 'Opening'), ('02.md', '1.1 Learning')]:
            (self.root / '02_chapters' / name).write_text(
                f'---\nfile_role: chapter\n---\n\n### {title}\n\nLearning needs evidence.\n\n'
                '![Figure](../03_assets/figure.png)\n\nAcademic note.\n', encoding='utf-8')
        self.run_script('Plan', '-StartChapter', '0', '-EndChapter', '1')
        self.path = self.root / '00_brief/references/plan_0_1.json'
        self.plan = json.loads(self.path.read_text(encoding='utf-8-sig'))
        self.plan['reviewed'] = True
        self.plan['sources'] = [dict(id='s1', authors=['Author'], title='Learning', year=2020,
            publication='Journal', url='https://example.org/source', verified=True,
            verified_at='2026-09-14', verification_url='https://example.org/source',
            evidence_summary='Fixture evidence', limits='Fixture only')]
        self.plan['groups'] = [dict(key='front', title='前言参考文献', prefix='前', order=0),
                               dict(key='ch1', title='第一章参考文献', prefix='1', order=1)]
        for section in self.plan['sections']:
            section.update(reviewed=True, remove_blocks=['Academic note.'], citations=[
                dict(anchor='Learning needs evidence.', source_ids=['s1'], support_note='Fixture claim')])

    def run_script(self, mode, *args, success=True):
        result = subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', str(SCRIPT), '-BookName', 'Fixture', '-BookRoot', str(self.root),
            '-Mode', mode, *map(str, args)], capture_output=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout.decode(errors='replace') + result.stderr.decode(errors='replace'))
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def apply(self, success=True):
        self.path.write_text(json.dumps(self.plan, ensure_ascii=False), encoding='utf-8')
        return self.run_script('Apply', '-PlanPath', self.path, success=success)

    def originals(self):
        return {p.name: p.read_bytes() for p in (self.root / '02_chapters').glob('*.md')}

    def test_plan_does_not_edit(self):
        self.assertFalse((self.root / '02_chapters/references.md').exists())
        self.assertIn('Academic note.', (self.root / '02_chapters/01.md').read_text())

    def test_apply_backup_check_and_idempotence(self):
        original = self.originals()
        self.apply()
        for filename, label in [('01.md', '[前-1]'), ('02.md', '[1-1]')]:
            text = (self.root / '02_chapters' / filename).read_text(encoding='utf-8-sig')
            self.assertIn(label, text)
            self.assertIn('![Figure]', text)
            self.assertNotIn('Academic note.', text)
            backup = next((self.root / 'back').glob('*/02_chapters/' + filename))
            self.assertEqual(backup.read_bytes(), original[filename])
        snapshot = self.originals()
        self.apply()
        self.assertEqual(snapshot, self.originals())
        self.assertEqual(len(list((self.root / 'back').iterdir())), 1)
        self.run_script('Check')

    def test_stale_last_section_does_not_partially_write(self):
        path = self.root / '02_chapters/02.md'
        path.write_text(path.read_text() + 'User edit.', encoding='utf-8')
        original = self.originals()
        self.apply(success=False)
        self.assertEqual(original, self.originals())
        self.assertFalse((self.root / 'back').exists())

    def test_unverified_source_blocks_edit(self):
        self.plan['sources'][0]['verified'] = False
        original = self.originals()
        self.apply(success=False)
        self.assertEqual(original, self.originals())

    def test_nonfinal_removal_blocks_edit(self):
        self.plan['sections'][0]['remove_blocks'] = ['Learning needs evidence.']
        original = self.originals()
        self.apply(success=False)
        self.assertEqual(original, self.originals())

    def test_unknown_source_blocks_edit(self):
        self.plan['sections'][1]['citations'][0]['source_ids'] = ['unknown']
        original = self.originals()
        self.apply(success=False)
        self.assertEqual(original, self.originals())

    def test_changed_heading_blocks_edit(self):
        self.plan['sections'][0]['replacements'] = [dict(find='### Opening', replace='### Other', reason='test')]
        original = self.originals()
        self.apply(success=False)
        self.assertEqual(original, self.originals())

    def test_existing_reference_file_is_protected(self):
        (self.root / '02_chapters/references.md').write_text('User bibliography', encoding='utf-8')
        original = self.originals()
        self.apply(success=False)
        self.assertEqual(original, self.originals())

    def test_check_detects_post_apply_edit(self):
        self.apply()
        path = self.root / '02_chapters/01.md'
        path.write_text(path.read_text(encoding='utf-8-sig') + 'Later edit.', encoding='utf-8')
        self.run_script('Check', success=False)


if __name__ == '__main__':
    unittest.main(verbosity=2)
