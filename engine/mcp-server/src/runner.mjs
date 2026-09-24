import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const MCP_ROOT = path.resolve(HERE, '..');
export const ENGINE_ROOT = path.resolve(MCP_ROOT, '..');

const BOOK_NAME_PATTERN = /^[^\\/:*?"<>|\r\n]{1,120}$/u;

export function validateBookName(bookName) {
  if (!BOOK_NAME_PATTERN.test(bookName) || bookName === '.' || bookName === '..') {
    throw new Error('bookName contains characters that are not valid in a Windows folder name.');
  }
}

export function buildPowerShellArgs(scriptName, parameters = {}) {
  if (!/^[0-9A-Za-z-]+\.ps1$/u.test(scriptName)) {
    throw new Error(`Invalid SageWrite script name: ${scriptName}`);
  }

  const args = [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    path.join(ENGINE_ROOT, scriptName)
  ];

  for (const [name, value] of Object.entries(parameters)) {
    if (value === undefined || value === null || value === '' || value === false) continue;
    if (!/^[A-Za-z][A-Za-z0-9]*$/u.test(name)) {
      throw new Error(`Invalid PowerShell parameter name: ${name}`);
    }
    args.push(`-${name}`);
    if (value !== true) args.push(String(value));
  }
  return args;
}

function powershellExecutable() {
  return process.env.SAGEWRITE_POWERSHELL || 'powershell.exe';
}

export async function runSageWriteScript(scriptName, parameters, options = {}) {
  validateBookName(parameters.BookName);
  const args = buildPowerShellArgs(scriptName, parameters);
  const timeoutMs = options.timeoutMs ?? Number(process.env.SAGEWRITE_MCP_TIMEOUT_MS || 3_600_000);
  const maxOutput = options.maxOutput ?? 200_000;
  const env = { ...process.env };
  if (options.workspaceRoot) {
    env.SAGEWRITE_WORKSPACE_ROOT = path.resolve(options.workspaceRoot);
  }

  return await new Promise((resolve) => {
    const child = spawn(powershellExecutable(), args, {
      cwd: ENGINE_ROOT,
      env,
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe']
    });
    let stdout = '';
    let stderr = '';
    let truncated = false;

    const append = (current, chunk) => {
      const next = current + chunk.toString('utf8');
      if (next.length <= maxOutput) return next;
      truncated = true;
      return next.slice(0, maxOutput);
    };
    child.stdout.on('data', (chunk) => { stdout = append(stdout, chunk); });
    child.stderr.on('data', (chunk) => { stderr = append(stderr, chunk); });

    const timer = setTimeout(() => child.kill(), timeoutMs);
    child.on('error', (error) => {
      clearTimeout(timer);
      resolve({ exitCode: null, stdout, stderr, error: error.message, timedOut: false, truncated });
    });
    child.on('close', (exitCode, signal) => {
      clearTimeout(timer);
      resolve({
        exitCode,
        stdout: stdout.trim(),
        stderr: stderr.trim(),
        error: null,
        timedOut: signal !== null,
        truncated
      });
    });
  });
}

export function toolResult(scriptName, result) {
  const payload = {
    script: scriptName,
    success: result.exitCode === 0 && !result.error && !result.timedOut,
    exitCode: result.exitCode,
    timedOut: result.timedOut,
    truncated: result.truncated,
    stdout: result.stdout,
    stderr: result.stderr,
    error: result.error
  };
  return {
    content: [{ type: 'text', text: JSON.stringify(payload, null, 2) }],
    structuredContent: payload,
    isError: !payload.success
  };
}

export function resolveBookRoot(bookName, workspaceRoot) {
  validateBookName(bookName);
  const parent = path.resolve(workspaceRoot || process.env.SAGEWRITE_WORKSPACE_ROOT || path.resolve(ENGINE_ROOT, '..', '..'));
  return path.join(parent, `workspace-${bookName}`, 'sagewrite', 'book');
}
