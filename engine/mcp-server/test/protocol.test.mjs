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
    assert.equal(tools.length, 39);
    assert.ok(names.includes('sagewrite_import_structure'));
    assert.ok(names.includes('sagewrite_generate_toc'));
    assert.ok(names.includes('sagewrite_rewrite_chapters'));
    assert.ok(names.includes('sagewrite_editorial_action_review'));
    assert.ok(names.includes('sagewrite_editorial_loop'));
    assert.ok(names.includes('sagewrite_execute_revision_plan'));
    assert.ok(names.includes('sagewrite_reference_verification'));
    assert.ok(names.includes('sagewrite_remove_section'));
    assert.ok(names.includes('sagewrite_export_pdf'));
    assert.ok(names.includes('sagewrite_build_simple_docx_toc'));
    assert.ok(names.includes('sagewrite_build_print_docx'));
    assert.ok(names.includes('sagewrite_export_print_pdf'));
    assert.ok(names.includes('sagewrite_cover_base_brief'));
    assert.ok(names.includes('sagewrite_cover_image_edit'));
    assert.ok(names.includes('sagewrite_cover_install'));
    assert.ok(names.includes('sagewrite_project_status'));

    const missingCover = await client.callTool({
      name: 'sagewrite_export_pdf',
      arguments: {
        bookName: 'McpMissingCoverProbe',
        workspaceRoot: root,
        autoPrepareCover: false
      }
    });
    assert.equal(missingCover.isError, true);
    assert.equal(missingCover.structuredContent.coverRequired, true);
    assert.equal(missingCover.structuredContent.nextSkill, 'sagewrite-create-cover');
  } finally {
    await client.close();
  }
});
