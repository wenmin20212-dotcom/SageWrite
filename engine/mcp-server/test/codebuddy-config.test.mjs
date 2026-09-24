import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/client';
import { StdioClientTransport } from '@modelcontextprotocol/client/stdio';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');

test('CodeBuddy project configuration connects to SageWrite', async () => {
  const config = JSON.parse(await fs.readFile(path.join(repositoryRoot, '.mcp.json'), 'utf8'));
  const definition = config.mcpServers.sagewrite;
  assert.equal(definition.type, 'stdio');
  assert.equal(definition.alwaysLoad, true);

  const transport = new StdioClientTransport({
    command: definition.command,
    args: definition.args,
    env: { ...process.env, ...definition.env },
    stderr: 'pipe'
  });
  const client = new Client({ name: 'codebuddy-config-test', version: '1.0.0' });
  try {
    await client.connect(transport);
    const { tools } = await client.listTools();
    assert.equal(tools.length, 14);
  } finally {
    await client.close();
  }
});
