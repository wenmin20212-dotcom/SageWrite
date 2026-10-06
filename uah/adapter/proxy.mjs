import { spawn } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const adapterRoot = path.dirname(fileURLToPath(import.meta.url));
const packageRoot = path.resolve(adapterRoot, '..');
const installation = JSON.parse(fs.readFileSync(path.join(packageRoot, 'installation.local.json'), 'utf8'));
const modelConfig = path.join(packageRoot, 'model.local.json');
const sageWriteRoot = path.join(packageRoot, 'payload', 'SageWrite');
const workspaceRoot = path.resolve(installation.workspace);
const node = path.join(packageRoot, 'runtime', 'node.exe');
const server = path.join(sageWriteRoot, 'engine', 'mcp-server', 'src', 'index.mjs');
const powershell = path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe');

fs.mkdirSync(workspaceRoot, { recursive: true });

const child = spawn(node, [server], {
  cwd: sageWriteRoot,
  windowsHide: true,
  stdio: ['pipe', 'pipe', 'pipe'],
  env: {
    ...process.env,
    SAGEWRITE_WORKSPACE_ROOT: workspaceRoot,
    SAGEWRITE_POWERSHELL: powershell,
    SAGE_LLM_CONFIG: modelConfig,
    SAGE_LLM_CODEX_WORKDIR: sageWriteRoot,
  },
});

const pending = new Map();
let input = '';
let output = '';

function bookDirectory(args) {
  const parent = path.resolve(args.workspaceRoot || workspaceRoot);
  return path.join(parent, `workspace-${args.bookName}`, 'sagewrite', 'book');
}

function receipt(request, existedBefore) {
  const args = request.params?.arguments || {};
  const directory = bookDirectory(args);
  if (!fs.existsSync(directory) || !fs.existsSync(path.join(directory, '00_brief', 'objective.md'))) return null;
  const normalized = path.resolve(directory);
  return {
    schema: 'uah-work-result/v0.1',
    status: existedBefore ? 'existing' : 'created',
    object: {
      external_id: crypto.createHash('sha256').update(normalized.toLowerCase()).digest('hex').slice(0, 24),
      name: args.title || args.bookName,
      workspace: normalized,
      continue_prompt: `继续 SageWrite 书籍“${args.title || args.bookName}”。书籍标识为 ${args.bookName}，工作目录为 ${normalized}。先检查当前写作进度，再询问本话题要推进什么。`,
    },
  };
}

function forwardInput(line) {
  try {
    const message = JSON.parse(line);
    if (message.id !== undefined && message.method === 'tools/call') {
      const modelTools = new Set(['sagewrite_generate_toc', 'sagewrite_expand_outline', 'sagewrite_write_chapters', 'sagewrite_rewrite_chapters', 'sagewrite_refine_chapters', 'sagewrite_translate_chapters', 'sagewrite_edit_book', 'sagewrite_editorial_action_review', 'sagewrite_editorial_loop', 'sagewrite_accepted_audit_rewrite', 'sagewrite_execute_revision_plan', 'sagewrite_cover_assist', 'sagewrite_cover_base_prompt']);
      if (modelTools.has(message.params?.name)) {
        let config = {};
        try { if (fs.existsSync(modelConfig)) config = JSON.parse(fs.readFileSync(modelConfig, 'utf8')); } catch {}
        const provider = process.env.SAGE_LLM_PROVIDER || config.SAGE_LLM_PROVIDER;
        if (!provider || provider === 'codex_agent') {
          process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id: message.id, result: { isError: true, content: [{ type: 'text', text: '请先配置本包 model.local.json 的独立写作模型。codex_agent 需要当前助手，不能用于独立 UAH 自动运行。' }] } }) + '\n');
          return;
        }
      }
      const args = message.params?.arguments || {};
      pending.set(String(message.id), {
        message,
        existedBefore: message.params?.name === 'sagewrite_initialize_book' && fs.existsSync(bookDirectory(args)),
      });
    }
  } catch {}
  child.stdin.write(line + '\n');
}

function forwardOutput(line) {
  try {
    const message = JSON.parse(line);
    const tracked = pending.get(String(message.id));
    if (tracked) {
      pending.delete(String(message.id));
      if (tracked.message.params?.name === 'sagewrite_initialize_book' && message.result && !message.result.isError) {
        const workResult = receipt(tracked.message, tracked.existedBefore);
        if (workResult) {
          const original = message.result;
          message.result = {
            ...original,
            structuredContent: workResult,
            content: [...(Array.isArray(original.content) ? original.content : []), { type: 'text', text: JSON.stringify(workResult) }],
          };
        }
      }
    }
    process.stdout.write(JSON.stringify(message) + '\n');
  } catch {
    process.stdout.write(line + '\n');
  }
}

process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => {
  input += chunk;
  let index;
  while ((index = input.indexOf('\n')) !== -1) {
    const line = input.slice(0, index).replace(/\r$/, '');
    input = input.slice(index + 1);
    if (line) forwardInput(line);
  }
});

child.stdout.setEncoding('utf8');
child.stdout.on('data', chunk => {
  output += chunk;
  let index;
  while ((index = output.indexOf('\n')) !== -1) {
    const line = output.slice(0, index).replace(/\r$/, '');
    output = output.slice(index + 1);
    if (line) forwardOutput(line);
  }
});

child.stderr.pipe(process.stderr);
child.on('error', error => {
  process.stderr.write(`SageWrite MCP failed to start: ${error.message}\n`);
  process.exitCode = 1;
});
child.on('exit', code => process.exit(code ?? 1));
process.on('SIGTERM', () => child.kill());
process.on('SIGINT', () => child.kill());

