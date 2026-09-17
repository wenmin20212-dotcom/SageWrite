import json
import hashlib
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ENGINE = Path(__file__).resolve().parents[1]


class FormatPreflight(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / '01_outline').mkdir()
        (self.root / '02_chapters').mkdir()
        (self.root / '01_outline/toc.md').write_text('## 第4章：Transfer\n### 4.2 Transfer\n', encoding='utf-8')
        self.md = self.root / '02_chapters/01.md'
        self.md.write_text('---\nfile_role: chapter\n---\n\n### 4.2 Transfer\n\n#### 一、Context\n\nBody unchanged.\n\n#### 第二，Method\n\n1. A list\n2. Another item\n\n#### Summary\n', encoding='utf-8')
        self.stamp = self.root / '00_brief/format_preflight.json'

    def run_mode(self, mode, success=True):
        result = subprocess.run(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(ENGINE/'04F.ps1'),'-BookName','Fixture','-BookRoot',str(self.root),'-Mode',mode],capture_output=True)
        self.assertEqual(result.returncode == 0, success, result.stdout.decode(errors='replace') + result.stderr.decode(errors='replace'))
        return result

    def test_check_does_not_modify_or_approve_bad_format(self):
        before = self.md.read_bytes()
        self.run_mode('Check',False)
        self.assertEqual(before,self.md.read_bytes())
        self.assertFalse(self.stamp.exists())

    def test_normalize_backup_idempotence_and_verify(self):
        before=self.md.read_bytes()
        self.run_mode('Normalize')
        text=self.md.read_text(encoding='utf-8-sig')
        self.assertIn('#### 4.2.1 Context',text)
        self.assertIn('#### 4.2.2 Method',text)
        self.assertIn('#### 4.2.3 Summary',text)
        self.assertIn('1. A list\n2. Another item',text)
        backup=next((self.root/'back').glob('format_*/02_chapters/01.md'))
        self.assertEqual(before,backup.read_bytes())
        self.run_mode('Verify')
        self.run_mode('Normalize')
        self.assertEqual(len(list((self.root/'back').glob('format_*'))),1)

    def test_edit_invalidates_stamp(self):
        self.run_mode('Normalize')
        with self.md.open('a',encoding='utf-8') as f: f.write('\nNew paragraph.\n')
        self.run_mode('Verify',False)
        self.assertFalse(self.stamp.exists())

    def test_toc_and_asset_changes_invalidate(self):
        self.run_mode('Normalize')
        (self.root/'cover.png').write_bytes(b'fixture')
        self.run_mode('Verify',False)
        self.run_mode('Check')
        with (self.root/'01_outline/toc.md').open('a',encoding='utf-8') as f: f.write('\nChanged requirement.\n')
        self.run_mode('Verify',False)

    def test_code_fences_preserved_and_hierarchy_normalized(self):
        text=self.md.read_text(encoding='utf-8')+'\n```markdown\n#### 一、Literal\n```\n\n##### Child\n'
        self.md.write_text(text,encoding='utf-8')
        self.run_mode('Normalize')
        text=self.md.read_text(encoding='utf-8-sig')
        self.assertIn('```markdown\n#### 一、Literal\n```',text)
        self.assertIn('##### 4.2.3.1 Child',text)

    def test_ambiguous_plain_heading_blocks_without_partial_changes(self):
        with self.md.open('a',encoding='utf-8') as f: f.write('\n一、Possible heading\n')
        before=self.md.read_bytes()
        self.run_mode('Normalize',False)
        self.assertEqual(before,self.md.read_bytes())

    def test_missing_image_and_orphan_reference_block(self):
        with self.md.open('a',encoding='utf-8') as f: f.write('\n![Figure](../03_assets/missing.png)\nClaim.[4-1]\n')
        self.run_mode('Normalize',False)

    def test_extra_file_blocks(self):
        (self.root/'02_chapters/old-draft.md').write_text('Old draft',encoding='utf-8')
        self.run_mode('Normalize',False)

    def test_pdf_and_epub_entrypoints_block_before_touching_old_outputs(self):
        book=self.root/'workspace-GateFixture/sagewrite/book'
        out=book/'04_output/zh'
        out.mkdir(parents=True)
        for name in ('full.docx','full.pdf','print.docx','print.pdf','full.epub'):
            (out/('GateFixture_'+name)).write_bytes(b'old output sentinel')
        env=dict(os.environ,SAGEWRITE_WORKSPACE_ROOT=str(self.root))
        for entry in ('05-build.ps1','05b-epub.ps1','05ca-print-docx.ps1','05c-pdf.ps1','05cc-print-pdf.ps1'):
            r=subprocess.run(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(ENGINE/entry),'-BookName','GateFixture'],capture_output=True,env=env)
            self.assertNotEqual(r.returncode,0,entry)
        for p in out.iterdir():
            self.assertEqual(p.read_bytes(),b'old output sentinel',p)

    def test_hierarchy_error_blocks(self):
        self.md.write_text('### 4.2 Transfer\n\n##### Missing parent\n',encoding='utf-8')
        self.run_mode('Normalize',False)

    def test_reference_state_rebaseline_only_for_headings(self):
        from test_04r_references import ReferenceWorkflow
        fixture=ReferenceWorkflow()
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        for section in fixture.plan['sections']:
            path=fixture.root/'02_chapters'/section['file']
            text=path.read_text(encoding='utf-8').replace('Academic note.','#### 一、Review\n\nAcademic note.')
            path.write_text(text,encoding='utf-8')
            section['expected_sha256']=hashlib.sha256(text.encode('utf-8')).hexdigest()
        fixture.apply()
        (fixture.root/'03_assets').mkdir()
        (fixture.root/'03_assets/figure.png').write_bytes(b'fixture')
        self.root=fixture.root
        self.stamp=self.root/'00_brief/format_preflight.json'
        self.run_mode('Normalize')
        fixture.run_script('Check')
        state=json.loads((self.root/'00_brief/references/reference_state.json').read_text(encoding='utf-8-sig'))
        self.assertEqual(len(state['format_history']),1)
        with (self.root/'02_chapters/02.md').open('a',encoding='utf-8') as f: f.write('\nUnreviewed content.\n')
        self.run_mode('Normalize',False)


if __name__=='__main__':
    unittest.main()
