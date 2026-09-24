import assert from 'node:assert/strict';
import test from 'node:test';
import { buildPowerShellArgs, validateBookName } from '../src/runner.mjs';

test('buildPowerShellArgs preserves each value as one process argument', () => {
  const args = buildPowerShellArgs('03-write.ps1', {
    BookName: 'My Book',
    AdditionalInstructions: 'Keep it concise; do not invoke anything.',
    ReferenceGlossary: true,
    Force: false
  });
  assert.deepEqual(args.slice(-5), [
    '-BookName', 'My Book',
    '-AdditionalInstructions', 'Keep it concise; do not invoke anything.',
    '-ReferenceGlossary'
  ]);
});

test('false and empty optional values are omitted', () => {
  const args = buildPowerShellArgs('05-build.ps1', { BookName: 'Demo', AutoNumber: false, Language: '' });
  assert.equal(args.includes('-AutoNumber'), false);
  assert.equal(args.includes('-Language'), false);
});

test('book names cannot escape the workspace folder', () => {
  assert.throws(() => validateBookName('../outside'));
  assert.throws(() => validateBookName('bad\\name'));
  assert.doesNotThrow(() => validateBookName('一本测试书'));
});
