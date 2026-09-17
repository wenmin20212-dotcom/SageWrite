import subprocess
import tempfile
import unittest
from pathlib import Path

ENGINE=Path(__file__).resolve().parents[1]


class FrontmatterLayout(unittest.TestCase):
    def transform(self,text,depth=3,single=False,references=False):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'source.md'
            p.write_text(text,encoding='utf-8-sig')
            cmd=f"[Console]::OutputEncoding=[Text.Encoding]::UTF8; . '{ENGINE / '00-layout.ps1'}'; Convert-SageFrontmatterHeadings -Content ([IO.File]::ReadAllText('{p}')) -MaxDepth {depth}"
            if single:
                cmd=f"[Console]::OutputEncoding=[Text.Encoding]::UTF8; . '{ENGINE / '00-layout.ps1'}'; Convert-SageSingleSubheading -Content ([IO.File]::ReadAllText('{p}'))"
            if references:
                cmd=f"[Console]::OutputEncoding=[Text.Encoding]::UTF8; . '{ENGINE / '00-layout.ps1'}'; Convert-SageReferenceGroupHeadings -Content ([IO.File]::ReadAllText('{p}'))"
            r=subprocess.run(['powershell.exe','-NoProfile','-Command',cmd],capture_output=True)
            self.assertEqual(r.returncode,0,r.stderr.decode(errors='replace'))
            return r.stdout.decode('utf-8-sig').replace('\r\n','\n').strip()

    def test_demotes_only_internal_headings(self):
        src='### Overview\n\n#### 一、Relations\nText.[前-1]\n\n##### 1.2.3 Detail\n![Image](../03_assets/test.png)'
        result=self.transform(src,2)
        self.assertIn('### Overview',result)
        self.assertIn('**Relations**',result)
        self.assertIn('**Detail**',result)
        self.assertNotIn('####',result)
        self.assertIn('Text.[前-1]',result)
        self.assertIn('![Image](../03_assets/test.png)',result)

    def test_default_preserves_existing_books(self):
        src='### Overview\n#### 一、Relations'
        self.assertEqual(self.transform(src,3),src)

    def test_code_is_not_reformatted(self):
        src='### Overview\n```markdown\n#### 一、Literal\n```\n#### Two'
        result=self.transform(src,2)
        self.assertIn('```markdown\n#### 一、Literal\n```',result)
        self.assertIn('**Two**',result)

    def test_all_formal_builders_read_same_rule(self):
        for name in ['05-build.ps1','05b-epub.ps1','05ca-print-docx.ps1']:
            text=(ENGINE/name).read_text(encoding='utf-8-sig')
            self.assertIn('00-layout.ps1',text)
            self.assertIn("-Key 'frontmatter_heading_depth'",text)
            self.assertIn('Convert-SageFrontmatterHeadings -Content $Content -MaxDepth $FrontmatterHeadingDepth',text)
            self.assertIn("-Key 'single_subheading_policy'",text)
            self.assertIn('Convert-SageSingleSubheading -Content $Content',text)
            self.assertIn("-Key 'toc_depth'",text)
            self.assertIn('--toc-depth=$TocDepth',text)
            self.assertIn("-Key 'references_toc_depth'",text)
            self.assertIn('Convert-SageReferenceGroupHeadings -Content $Body',text)

    def test_reference_groups_leave_only_one_heading(self):
        src='# 参考文献\n\n## 前言参考文献\n[前-1] Source. https://example.org\n\n## 第一章参考文献\n[1-1] Source.'
        result=self.transform(src,references=True)
        self.assertEqual([x for x in result.splitlines() if x.startswith('#')],['# 参考文献'])
        self.assertIn('**前言参考文献**',result)
        self.assertIn('**第一章参考文献**',result)
        self.assertIn('[前-1] Source. https://example.org',result)
        self.assertIn('[1-1] Source.',result)

    def test_reference_code_fences_unchanged(self):
        src='# References\n```markdown\n## Literal\n```\n## Group'
        result=self.transform(src,references=True)
        self.assertIn('```markdown\n## Literal\n```',result)
        self.assertIn('**Group**',result)

    def test_single_heading_becomes_body(self):
        src='### 4.1 Section\n\n#### 4.1.1 Context\n\nText.[4-1]'
        result=self.transform(src,single=True)
        self.assertEqual(result,'### 4.1 Section\n\n**Context**\n\nText.[4-1]')

    def test_multiple_headings_unchanged(self):
        src='### 4.2 Section\n#### 4.2.1 One\n#### 4.2.2 Two'
        self.assertEqual(self.transform(src,single=True),src)

    def test_code_heading_not_counted_and_children_not_orphaned(self):
        src='### 4.1 Section\n#### 4.1.1 One\n##### 4.1.1.1 Child\n```markdown\n#### Literal\n```'
        result=self.transform(src,single=True)
        self.assertIn('**One**',result)
        self.assertIn('**Child**',result)
        self.assertIn('```markdown\n#### Literal\n```',result)

    def test_no_headings_unchanged(self):
        src='### 4.1 Section\n\nContinuous prose.'
        self.assertEqual(self.transform(src,single=True),src)


if __name__=='__main__': unittest.main()
