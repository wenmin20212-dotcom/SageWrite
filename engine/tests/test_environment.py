import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ENGINE = Path(__file__).resolve().parents[1]


class EnvironmentDoctor(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.engine = self.root / 'engine'
        self.engine.mkdir()
        for name in ('Test-SageWriteEnvironment.ps1', '00-llm.ps1'):
            shutil.copy2(ENGINE / name, self.engine / name)
        self.config = self.engine / 'llm-config.json'
        self.config.write_text('{"SAGE_LLM_PROVIDER":"codex_agent"}')
        self.env = {k: v for k, v in os.environ.items()
                    if not k.upper().startswith(('SAGE_LLM_', 'OPENAI_', 'SAGEWRITE_'))}

    def run_check(self, profile='Writing', extra=()):
        p = subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                            '-File', str(self.engine / 'Test-SageWriteEnvironment.ps1'),
                            '-Profile', profile, '-WorkspaceRoot', str(self.root), '-Json', *extra],
                           env=self.env, capture_output=True, timeout=30)
        self.assertIn(p.returncode, (0, 1), p.stderr)
        return p.returncode, json.loads(p.stdout.decode('utf-8-sig')), p.stdout + p.stderr

    def test_agent_readonly_and_scope(self):
        before = {str(p): p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        code, r, _ = self.run_check()
        self.assertEqual(code, 0)
        self.assertEqual({c['area'] for c in r['checks']}, {'Core', 'Writing'})
        self.assertTrue(all(c['state'] == 'requires_validation' for c in r['capabilities']))
        self.assertEqual(before, {str(p): p.read_bytes() for p in self.root.rglob('*') if p.is_file()})

    def test_missing_secret_blocks(self):
        self.config.write_text('{"SAGE_LLM_PROVIDER":"openai"}')
        code, r, _ = self.run_check()
        self.assertEqual(code, 1)
        self.assertTrue(any(c['id'] == 'llm.config' and c['status'] == 'fail' for c in r['checks']))

    def test_secret_never_serialized(self):
        secret = 'DO_NOT_PRINT_SECRET_123456789'
        self.config.write_text(json.dumps({'SAGE_LLM_PROVIDER': 'openai',
                                          'SAGE_LLM_API_KEY': secret,
                                          'SAGE_LLM_ENDPOINT': 'https://example.org/v1?key=' + secret}))
        code, r, output = self.run_check()
        self.assertEqual(code, 0)
        self.assertNotIn(secret.encode(), output)
        self.assertTrue(any(c['id'] == 'llm.endpoint' and c['status'] == 'warn' for c in r['checks']))

    def test_bad_json_error_redacted(self):
        self.config.write_text('{BAD_PRIVATE_VALUE')
        code, _, output = self.run_check()
        self.assertEqual(code, 1)
        self.assertNotIn(b'BAD_PRIVATE_VALUE', output)

    def test_environment_override(self):
        self.config.write_text('{"SAGE_LLM_PROVIDER":"openai"}')
        self.env['SAGE_LLM_PROVIDER'] = 'codex_agent'
        self.assertEqual(self.run_check()[0], 0)

    def test_reports_unique_and_valid(self):
        dest = self.root / 'reports'
        for _ in range(2):
            self.run_check(extra=('-ReportDirectory', str(dest)))
        files = list(dest.glob('*.json'))
        self.assertEqual(len(files), 2)
        self.assertTrue(all(json.loads(p.read_text())['schema_version'] == 1 for p in files))

    def test_other_machine_mcp(self):
        (self.root / '.mcp.json').write_text(json.dumps({'mcpServers': {'sagewrite': {
            'command': 'Z:/absent-sagewrite-test/node.exe', 'args': ['Z:/absent-sagewrite-test/index.mjs']}}}))
        code, r, _ = self.run_check('Mcp')
        self.assertEqual(code, 1)
        self.assertTrue(any(c['id'] == 'mcp.command' and c['status'] == 'fail' for c in r['checks']))
        self.assertTrue(any(c['id'] == 'mcp.paths' and c['status'] == 'fail' for c in r['checks']))

    def test_insecure_web(self):
        (self.engine / 'sagewrite-web.config.psd1').write_text("@{HostName='0.0.0.0';AuthMode='off'}")
        code, r, _ = self.run_check('Web')
        self.assertEqual(code, 1)
        self.assertTrue(any(c['id'] == 'web.exposure' and c['status'] == 'fail' for c in r['checks']))

    def test_psd1_code_is_never_executed(self):
        marker = self.root / 'must-not-exist.txt'
        (self.engine / 'sagewrite-web.config.psd1').write_text(
            "@{HostName=$(New-Item -ItemType File -Path '" + str(marker) + "')}"
        )
        code, _, _ = self.run_check('Web')
        self.assertEqual(code, 1)
        self.assertFalse(marker.exists())

    def test_bad_mcp_does_not_block_writing(self):
        (self.root / '.mcp.json').write_text('{invalid')
        self.assertEqual(self.run_check('Writing')[0], 0)


if __name__ == '__main__':
    unittest.main()
