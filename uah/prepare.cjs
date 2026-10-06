const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname);
const template = JSON.parse(fs.readFileSync(path.join(root, 'agent.template.json'), 'utf8'));
const workspace = path.resolve(process.argv[2] || path.join(root, 'books'));
fs.mkdirSync(workspace, { recursive: true });
template.mcp[0].args = [path.join(root, 'adapter', 'proxy.mjs')];
template.mcp[0].sha256 = crypto.createHash('sha256').update(fs.readFileSync(path.join(root, 'runtime', 'node.exe'))).digest('hex');
template.work.create.instruction = `先确认书籍需求，再调用 sagewrite_initialize_book；workspaceRoot 必须使用 ${workspace}。成功后依据工具回执登记书籍。`;
fs.writeFileSync(path.join(root, 'uah', 'agent.yaml'), JSON.stringify(template, null, 2));
fs.writeFileSync(path.join(root, 'installation.local.json'), JSON.stringify({ workspace }, null, 2));
const bomTemplate = path.join(root, 'bom.template.json');
if (fs.existsSync(bomTemplate)) {
  const bom = JSON.parse(fs.readFileSync(bomTemplate, 'utf8'));
  bom.files = [];
  function walk(directory) {
    for (const item of fs.readdirSync(directory, { withFileTypes: true })) {
      const file = path.join(directory, item.name);
      if (item.isSymbolicLink()) throw new Error('Package links are not allowed');
      if (item.isDirectory()) { if (file !== path.join(root, 'books')) walk(file); continue; }
      const relative = path.relative(root, file).replaceAll('\\', '/');
      if (relative === 'uah/bom.yaml' || relative === 'model.local.json') continue;
      const bytes = fs.readFileSync(file);
      const role = relative === 'uah/agent.yaml' ? 'agent-manifest' : relative.startsWith('prompts/') ? 'prompt' : relative.includes('/skills/') ? 'skill' : relative === 'runtime/node.exe' ? 'runtime' : relative.includes('/node_modules/') ? 'library' : /LICENSE/i.test(relative) ? 'license' : relative.endsWith('.md') ? 'documentation' : relative.endsWith('.json') ? 'configuration' : 'asset';
      bom.files.push({ path: relative, role, size: bytes.length, sha256: crypto.createHash('sha256').update(bytes).digest('hex'), ...(relative === 'runtime/node.exe' ? { component: 'runtime:node' } : {}) });
    }
  }
  walk(root);
  fs.writeFileSync(path.join(root, 'uah', 'bom.yaml'), JSON.stringify(bom, null, 2));
}
console.log('SageWrite prepared. Select this directory in UAH: ' + root);
