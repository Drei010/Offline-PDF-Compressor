import { test, expect } from '@playwright/test';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';

const menuIcon = 'Sources/PDFCompressor/Resources/MenuBarIconTemplate.png';
const info = (file: string) => JSON.parse(execFileSync('/usr/bin/plutil', ['-convert', 'json', '-o', '-', file], { encoding: 'utf8' }));

test('icon assets decode as a macOS icon and transparent Retina menu glyph', ({}, testInfo) => {
  expect(info('Resources/Info.plist').CFBundleIconFile).toMatch(/^AppIcon(?:\.icns)?$/);
  const iconset = testInfo.outputPath('AppIcon.iconset');
  execFileSync('/usr/bin/iconutil', ['--convert', 'iconset', '--output', iconset, 'Resources/AppIcon.icns']);
  expect(existsSync(path.join(iconset, 'icon_512x512@2x.png'))).toBe(true);
  const properties = execFileSync('/usr/bin/sips', ['-g', 'pixelWidth', '-g', 'pixelHeight', '-g', 'hasAlpha', menuIcon], { encoding: 'utf8' });
  expect(properties).toMatch(/pixelWidth: 36\b/);
  expect(properties).toMatch(/pixelHeight: 36\b/);
  expect(properties).toMatch(/hasAlpha: yes/);
});

for (const [route, app] of [
  ['SwiftPM', 'build/PDF Compressor.app'],
  ['Xcode release', 'build/Distribution/Build/Products/Release/PDFCompressor.app'],
]) {
  test(`${route} app contains current icon resources`, () => {
    test.skip(!existsSync(app), `Build the ${route} app first.`);
    expect(info(path.join(app, 'Contents/Info.plist')).CFBundleIconFile).toMatch(/^AppIcon(?:\.icns)?$/);
    for (const [source, filename] of [
      ['Resources/AppIcon.icns', 'AppIcon.icns'],
      [menuIcon, 'MenuBarIconTemplate.png'],
      ['Sources/PDFCompressor/Resources/AppIconPreview.png', 'AppIconPreview.png'],
    ]) {
      expect(readFileSync(path.join(app, 'Contents/Resources', filename))).toEqual(readFileSync(source));
    }
  });
}
