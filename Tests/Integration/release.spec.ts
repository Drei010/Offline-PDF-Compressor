import { test, expect } from '@playwright/test';
import { execFile, execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { promisify } from 'node:util';

test('release requires explicit valid signing configuration or preview mode', () => {
  const cases = [
    { args: [], identity: '', profile: '', message: 'Set SIGNING_IDENTITY' },
    { args: [], identity: 'Apple Development: Test', profile: 'unused', message: 'Set SIGNING_IDENTITY' },
    { args: [], identity: 'Developer ID Application: Test', profile: '', message: 'Set SIGNING_IDENTITY' },
    { args: ['--unknown'], identity: '', profile: '', message: 'Usage:' },
    { args: ['--unsigned', '--unknown'], identity: '', profile: '', message: 'Usage:' },
  ];
  for (const { args, identity, profile, message } of cases) {
    let failure: any;
    try {
      execFileSync('/bin/bash', ['scripts/release.sh', ...args], {
        encoding: 'utf8', stdio: 'pipe', timeout: 10_000,
        env: { ...process.env, SIGNING_IDENTITY: identity, NOTARY_PROFILE: profile },
      });
    } catch (error) { failure = error; }
    expect(failure?.status).toBe(2);
    expect(failure?.stderr).toContain(message);
  }
});

test('built release archives retain signatures, architectures, and matching checksums', async ({}, testInfo) => {
  const manifests = existsSync('dist') ? readdirSync('dist').filter(name => /^PDF-Compressor-[\d.]+-universal(?:-preview-unnotarized)?\.json$/.test(name)) : [];
  test.skip(manifests.length === 0, 'Build a release package first with npm run release:preview.');
  for (const file of manifests) {
    const manifest = JSON.parse(readFileSync(path.join('dist', file), 'utf8'));
    expect(manifest.archive).toBe(file.replace(/\.json$/, '.zip'));
    const archive = path.resolve('dist', manifest.archive);
    const digest = createHash('sha256').update(readFileSync(archive)).digest('hex');
    expect(manifest.sha256).toBe(digest);
    expect(readFileSync(archive.replace(/\.zip$/, '.sha256'), 'utf8').trim()).toBe(`${digest}  ${manifest.archive}`);
    const destination = testInfo.outputPath(file.replace(/\.json$/, ''));
    execFileSync('/usr/bin/ditto', ['-x', '-k', archive, destination]);
    const app = path.join(destination, 'PDF Compressor.app');
    const info = JSON.parse(execFileSync('/usr/bin/plutil', ['-convert', 'json', '-o', '-', path.join(app, 'Contents/Info.plist')], { encoding: 'utf8' }));
    expect(info.CFBundleShortVersionString).toBe(manifest.version);
    expect(info.CFBundleVersion).toBe(manifest.build);
    execFileSync('/usr/bin/codesign', ['--verify', '--strict', app]);
    const { stderr: signature } = await promisify(execFile)('/usr/bin/codesign', ['-d', '--verbose=4', app]);
    expect(signature).toMatch(/flags=0x[\da-f]+\([^)]*\bruntime\b[^)]*\)/i);
    const architectures = execFileSync('/usr/bin/lipo', ['-archs', path.join(app, 'Contents/MacOS/PDFCompressor')], { encoding: 'utf8' }).trim().split(/\s+/).sort();
    expect(architectures).toEqual(['arm64', 'x86_64']);
    expect(manifest.architectures.slice().sort()).toEqual(architectures);
    const entitlements = execFileSync('/usr/bin/codesign', ['-d', '--entitlements', '-', '--xml', app], { encoding: 'utf8', stdio: 'pipe' });
    expect(entitlements).toMatch(/<key>com\.apple\.security\.app-sandbox<\/key>\s*<true\/>/);
    expect(entitlements).toMatch(/<key>com\.apple\.security\.files\.user-selected\.read-write<\/key>\s*<true\/>/);
    expect(entitlements).not.toContain('com.apple.security.network');
    expect(entitlements).not.toContain('com.apple.security.get-task-allow');
    const entries = execFileSync('/usr/bin/unzip', ['-Z1', archive], { encoding: 'utf8' });
    expect(entries).not.toMatch(/\/Fixtures\/|\.xctest\//);
    expect(manifest.notarized).toBe(!file.includes('-preview-unnotarized'));
    if (manifest.notarized) execFileSync('/usr/bin/xcrun', ['stapler', 'validate', app]);
  }
});
