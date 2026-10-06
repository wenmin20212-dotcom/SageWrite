const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');
const source = path.resolve(__dirname, '..');
const output = path.resolve(process.argv[2] || path.join(source, 'dist', 'SageWrite-UAH'));
const node = path.resolve(process.argv[3] || process.execPath);
if (output === source || source.startsWith(output + path.sep) || fs.existsSync(output)) throw new Error('Use a new output directory');
if (path.basename(node).toLowerCase() !== 'node.exe') throw new Error('Windows node.exe required');
fs.mkdirSync(output, { recursive: true });
const copy = (from, to) => fs.cpSync(from, to, { recursive: true, dereference: true });
for (const name of ['skills', 'templates', 'docs', 'LICENSE']) copy(path.join(source, name), path.join(output, 'payload', 'SageWrite', name));
const engineOut = path.join(output, 'payload', 'SageWrite', 'engine');
fs.mkdirSync(engineOut, { recursive: true });
for (const item of fs.readdirSync(path.join(source, 'engine'), { withFileTypes: true })) {
  if (item.isFile() && item.name !== 'llm-config.json') copy(path.join(source, 'engine', item.name), path.join(engineOut, item.name));
}
const mcpOut = path.join(engineOut, 'mcp-server');
for (const name of ['src', 'package.json', 'pnpm-lock.yaml', 'test']) copy(path.join(source, 'engine', 'mcp-server', name), path.join(mcpOut, name));
// Materialize the locked pnpm graph. No junctions to the developer machine are distributed.
const store = path.join(source, 'engine', 'mcp-server', 'node_modules', '.pnpm');
const versions = new Map();
for (const entry of fs.readdirSync(store, { withFileTypes: true })) {
  if (!entry.isDirectory() || !entry.name.includes('@')) continue;
  const modules = path.join(store, entry.name, 'node_modules');
  if (!fs.existsSync(modules)) continue;
  function materialize(directory, prefix = '') {
    for (const item of fs.readdirSync(directory, { withFileTypes: true })) {
      if (item.isSymbolicLink() || item.name.startsWith('.')) continue;
      if (item.name.startsWith('@')) { materialize(path.join(directory, item.name), item.name + '/'); continue; }
      const location = path.join(directory, item.name);
      const metadata = path.join(location, 'package.json');
      if (!fs.existsSync(metadata)) continue;
      const pkg = JSON.parse(fs.readFileSync(metadata, 'utf8'));
      if (versions.has(pkg.name) && versions.get(pkg.name) !== pkg.version) throw new Error('Conflicting flattened dependency: ' + pkg.name);
      versions.set(pkg.name, pkg.version);
      copy(location, path.join(mcpOut, 'node_modules', prefix, item.name));
    }
  }
  materialize(modules);
}
fs.mkdirSync(path.join(output, 'runtime'), { recursive: true });
copy(node, path.join(output, 'runtime', 'node.exe'));
for (const name of ['adapter', 'prompts', 'prepare.cjs', 'agent.template.json', 'README.md', '启动安装.cmd', '模型配置.example.json', 'Configure-Model.ps1']) copy(path.join(source, 'uah', name), path.join(output, name));
fs.mkdirSync(path.join(output, 'uah'), { recursive: true });
function walk(directory, callback) {
  for (const item of fs.readdirSync(directory, { withFileTypes: true })) {
    const file = path.join(directory, item.name);
    if (item.isSymbolicLink()) throw new Error('Package link rejected: ' + file);
    if (item.isDirectory()) walk(file, callback); else callback(file);
  }
}
walk(output, file => {
  if (/\.(ps1|psm1|psd1)$/i.test(file)) fs.writeFileSync(file, '\ufeff' + fs.readFileSync(file, 'utf8').replace(/^\ufeff/, ''));
});
execFileSync(node, [path.join(output, 'prepare.cjs')]);
const files = [];
walk(output, file => {
  const bytes = fs.readFileSync(file);
  files.push({ path: path.relative(output, file).replaceAll('\\', '/'), size: bytes.length, sha256: crypto.createHash('sha256').update(bytes).digest('hex') });
});
fs.writeFileSync(path.join(output, 'uah', 'bom.yaml'), JSON.stringify({ schema: 'uah-agent-bom/v0.1', package: { id: 'sagewrite', version: '1.1.0', agent_manifest: 'uah/agent.yaml' }, files, components: [...versions].map(([name, version]) => ({ name, version, type: 'library' })), install: { scripts: ['prepare.cjs'], network_required: false }, provenance: { note: 'Generated from independent SageWrite checkout; runtime supplied to build command.' } }, null, 2));
console.log(JSON.stringify({ output, files: files.length, dependencies: versions.size }));
