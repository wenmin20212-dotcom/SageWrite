from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class AgentLauncherTests(unittest.TestCase):
    def test_launcher_files_exist_and_use_relative_entry(self):
        command = (ROOT / 'Start-SageWrite-Agent.cmd').read_text(encoding='utf-8')
        self.assertIn('%~dp0engine\\Start-SageWrite-Agent.ps1', command)
        self.assertIn('%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe', command)
        self.assertNotIn('D:\\SageWrite', command)

    def test_agent_launcher_preserves_handoff_provider(self):
        script = (ROOT / 'engine' / 'Start-SageWrite-Agent.ps1').read_text(encoding='utf-8-sig')
        self.assertIn("$env:SAGE_LLM_PROVIDER = 'codex_agent'", script)
        self.assertIn("'--sandbox', 'workspace-write'", script)
        self.assertIn("'--add-dir', $WorkspaceRoot", script)
        self.assertIn('SAGE_AGENT_PENDING', script)

    def test_installer_does_not_create_shortcut_by_default(self):
        script = (ROOT / 'engine' / 'Install-SageWrite-Agent.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('if (-not $CreateDesktopShortcut)', script)
        self.assertIn("$ValidationArgs = @{ DryRun = $true }", script)


if __name__ == '__main__':
    unittest.main()
