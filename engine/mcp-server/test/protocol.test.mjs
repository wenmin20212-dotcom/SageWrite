import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/client';
import { StdioClientTransport } from '@modelcontextprotocol/client/stdio';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

test('MCP client can initialize and discover SageWrite tools', async () => {
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [path.join(root, 'src', 'index.mjs')],
    stderr: 'pipe'
  });
  const client = new Client({ name: 'sagewrite-test-client', version: '1.0.0' });
  try {
    await client.connect(transport);
    const { tools } = await client.listTools();
    const names = tools.map((tool) => tool.name);
    assert.equal(tools.length, 13);
    assert.ok(names.includes('sagewrite_generate_toc'));
    assert.ok(names.includes('sagewrite_export_pdf'));
    assert.ok(names.includes('sagewrite_project_status'));
  } finally {
    await client.close();
  }
});
