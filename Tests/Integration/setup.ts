import { execFileSync } from 'node:child_process';
import path from 'node:path';

export default function setup() {
  execFileSync('swift', ['build', '--product', 'pdf-compressor'], { stdio: 'inherit' });
  execFileSync('swift', ['test', '--filter', 'exportFixtureCorpus'], {
    stdio: 'inherit',
    env: { ...process.env, PDF_TEST_FIXTURES_PATH: path.resolve('Tests/Fixtures') },
  });
}
