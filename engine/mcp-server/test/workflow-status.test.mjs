import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { ENGINE_ROOT, runSageWriteScript, toolResult } from '../src/runner.mjs';

test('workflow status registration maps one tool to one script', async () => {
  const source = await fs.readFile(path.join(ENGINE_ROOT, 'mcp-server/src/index.mjs'), 'utf8');
  const start = source.indexOf("scriptTool(server, 'sagewrite_workflow_status'");
  assert.ok(start > 0);
  const registration = source.slice(start, source.indexOf('120_000);', start));
  assert.ok(registration.includes("'Get-SageWriteWorkflowStatus.ps1'"));
  assert.ok(registration.includes('SaveReport: i.saveReport'));
  assert.ok(registration.includes('Details: i.details'));
});

test('runner scans read-only and saves only on request', { skip: process.platform !== 'win32' }, async () => {
  const parent = await fs.mkdtemp(path.join(os.tmpdir(), 'sagewrite-status-'));
  try {
    const book = path.join(parent, 'workspace-Fixture', 'sagewrite', 'book');
    await fs.mkdir(path.join(book, '00_brief'), { recursive: true });
    await fs.writeFile(path.join(book, '00_brief', 'objective.md'), '# Book\nObjective');
    const first = await runSageWriteScript('Get-SageWriteWorkflowStatus.ps1', { BookName: 'Fixture' }, { workspaceRoot: parent, timeoutMs: 30000 });
    assert.equal(toolResult('Get-SageWriteWorkflowStatus.ps1', first).isError, false, first.stderr);
    assert.equal(JSON.parse(first.stdout).report_path, null);
    await assert.rejects(fs.access(path.join(book, 'logs')));
    const saved = await runSageWriteScript('Get-SageWriteWorkflowStatus.ps1', { BookName: 'Fixture', SaveReport: true }, { workspaceRoot: parent, timeoutMs: 30000 });
    assert.equal(saved.exitCode, 0, saved.stderr);
    const report = JSON.parse(saved.stdout);
    assert.ok(JSON.parse(await fs.readFile(report.report_path, 'utf8')).inputs.length);
  } finally {
    const resolved = path.resolve(parent);
    assert.equal(path.dirname(resolved), path.resolve(os.tmpdir()));
    assert.ok(path.basename(resolved).startsWith('sagewrite-status-'));
    await fs.rm(resolved, { recursive: true, force: true });
  }
});
