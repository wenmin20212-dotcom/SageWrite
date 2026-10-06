const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');
const { spawn, execFileSync } = require('node:child_process');
const root = path.resolve(process.argv[2]);
const books = fs.mkdtempSync(path.join(os.tmpdir(), 'sagewrite-uah-'));
execFileSync(path.join(root, 'runtime', 'node.exe'), [path.join(root, 'prepare.cjs'), books]);
const child = spawn(path.join(root, 'runtime', 'node.exe'), [path.join(root, 'adapter', 'proxy.mjs')], { windowsHide: true });
let sequence = 0, buffer = '', stderr = '';
const pending = new Map();
child.stderr.on('data', data => { stderr += data; });
child.stdout.on('data', data => {
  buffer += data;
  let end;
  while ((end = buffer.indexOf('\n')) >= 0) {
    const line = buffer.slice(0, end); buffer = buffer.slice(end + 1);
    const message = JSON.parse(line); const entry = pending.get(message.id);
    if (entry) { clearTimeout(entry.timer); pending.delete(message.id); message.error ? entry.reject(new Error(JSON.stringify(message.error))) : entry.resolve(message.result); }
  }
});
function request(method, params) {
  return new Promise((resolve, reject) => {
    const id = ++sequence;
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(stderr || 'MCP timeout')); }, 30000);
    pending.set(id, { resolve, reject, timer });
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
  });
}
(async () => {
  await request('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'release-test', version: '1' } });
  child.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n');
  const tools = (await request('tools/list', {})).tools;
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'uah', 'agent.yaml')));
  assert.deepEqual(tools.map(x => x.name).sort(), [...manifest.mcp[0].tools].sort());
  const created = await request('tools/call', { name: 'sagewrite_initialize_book', arguments: { bookName: 'portable-test', title: '独立安装测试', audience: '测试用户', type: '非虚构', coreThesis: '验证安装接口', scope: '测试', style: '简洁' } });
  assert.notEqual(created.isError, true);
  assert.equal(created.structuredContent.schema, 'uah-work-result/v0.1');
  const objective = fs.readFileSync(path.join(created.structuredContent.object.workspace, '00_brief', 'objective.md'), 'utf8');
  assert.ok(objective.includes('# 书籍定义'));
  const blocked = await request('tools/call', { name: 'sagewrite_generate_toc', arguments: { bookName: 'portable-test' } });
  assert.equal(blocked.isError, true);
  console.log(JSON.stringify({ passed: true, tools: tools.length, chinese: true, relocatedWorkspace: true, missingModelReported: true, liveModelGeneration: false }));
})().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
  child.stdin.end(); child.kill();
  for (const entry of pending.values()) clearTimeout(entry.timer);
  execFileSync(path.join(root, 'runtime', 'node.exe'), [path.join(root, 'prepare.cjs')]);
  fs.rmSync(books, { recursive: true, force: true });
});
