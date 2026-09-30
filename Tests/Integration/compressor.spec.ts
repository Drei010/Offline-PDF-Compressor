import { test, expect } from '@playwright/test';
import { execFileSync, spawnSync } from 'node:child_process';
import { readFileSync, existsSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';

const cli = path.resolve('.build/debug/pdf-compressor');
const fixture = (name: string) => path.resolve('Tests/Fixtures', `${name}.pdf`);
const hash = (file: string) => createHash('sha256').update(readFileSync(file)).digest('hex');
const run = (...args: string[]) => JSON.parse(execFileSync(cli, args, { encoding: 'utf8' }));

test('analyzes a real PDF without changing it', () => {
  const file = fixture('text-only');
  const before = hash(file);
  const result = run('analyze', file);
  expect(result.fileName).toBe('text-only.pdf');
  expect(result.originalBytes).toBeGreaterThan(0);
  expect(result.pageCount).toBeGreaterThan(0);
  expect(hash(file)).toBe(before);
});

for (const preset of ['light', 'balanced', 'strong']) {
  test(`${preset} produces a readable PDF, keeps pages and original bytes intact`, ({}, testInfo) => {
    const file = fixture('image-heavy');
    const before = hash(file);
    const output = testInfo.outputPath(`${preset}.pdf`);
    const result = run('compress', file, output, preset);
    expect(result.compressedBytes).toBeLessThanOrEqual(result.originalBytes);
    expect(result.pageCount).toBe(run('analyze', output).pageCount);
    expect(hash(file)).toBe(before);
    expect(result.outputPath).toBe(output);
  });
}

test('custom returns a valid measured result for a bounded target', ({}, testInfo) => {
  const file = fixture('image-heavy');
  const original = run('analyze', file);
  const target = Math.max(10_240, Math.floor(original.originalBytes / 2));
  const output = testInfo.outputPath('custom.pdf');
  const result = run('compress', file, output, 'custom', String(target));
  expect(result.targetBytes).toBe(target);
  expect(result.targetReached).toBe(result.compressedBytes <= target);
  expect(result.compressedBytes).toBeLessThanOrEqual(original.originalBytes);
  expect(run('analyze', output).pageCount).toBe(original.pageCount);
});

for (const name of ['corrupt', 'encrypted']) {
  test(`rejects ${name} PDFs with a readable error`, () => {
    const result = spawnSync(cli, ['analyze', fixture(name)], { encoding: 'utf8' });
    expect(result.status).toBe(1);
    expect(JSON.parse(result.stdout).error).toBeTruthy();
  });
}

test('rejects invalid targets and protects existing destinations and source', ({}, testInfo) => {
  const file = fixture('image-heavy');
  const before = hash(file);
  const output = testInfo.outputPath('existing.pdf');
  writeFileSync(output, 'Keep this existing file.');
  for (const destination of [output, file]) {
    const result = spawnSync(cli, ['compress', file, destination, 'balanced'], { encoding: 'utf8' });
    expect(result.status).toBe(1);
    expect(JSON.parse(result.stdout).error).toBeTruthy();
  }
  expect(readFileSync(output, 'utf8')).toBe('Keep this existing file.');
  expect(hash(file)).toBe(before);
  const invalidOutput = testInfo.outputPath('invalid-target.pdf');
  for (const target of ['0', '-100', '999999999999']) {
    const result = spawnSync(cli, ['compress', file, invalidOutput, 'custom', target], { encoding: 'utf8' });
    expect(result.status).toBe(1);
    expect(JSON.parse(result.stdout).error).toBeTruthy();
    expect(existsSync(invalidOutput)).toBe(false);
  }
});

test('shipping app is sandboxed without network capabilities', () => {
  const entitlements = readFileSync('Resources/PDFCompressor.entitlements', 'utf8');
  expect(entitlements).toContain('com.apple.security.app-sandbox');
  expect(entitlements).not.toContain('com.apple.security.network');
});
