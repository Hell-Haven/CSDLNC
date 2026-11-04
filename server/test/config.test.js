import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { loadEnvironment, serverConfig } from '../src/config.js';

test('.env reads quoted literal Atlas URI and environment overrides file', t => {
  const dir = mkdtempSync(join(tmpdir(), 'library-env-'));
  t.after(() => rmSync(dir, { recursive: true }));
  const file = join(dir, '.env');
  assert.deepEqual(loadEnvironment(file, { PORT: '8081' }), { PORT: '8081' });
  writeFileSync(file, '# comment\nMONGODB_URI="mongodb+srv://user:p%40ss@host/library_db?retryWrites=true&w=majority"\nPORT=8080\nAPI_KEY=\n');
  const env = loadEnvironment(file, { PORT: '8081' });
  assert.equal(env.PORT, '8081');
  assert.equal(env.API_KEY, '');
  assert.equal(env.MONGODB_URI, 'mongodb+srv://user:p%40ss@host/library_db?retryWrites=true&w=majority');
  for (const line of ['SECRET', 'BAD KEY=secret', 'API_KEY="secret']) {
    writeFileSync(file, '# comment\n' + line);
    assert.throws(() => loadEnvironment(file, {}), error => error.message.includes('2') && !error.message.includes('secret'));
  }
});

test('server defaults, port validation and LAN key requirement', () => {
  assert.equal(serverConfig({}).host, '127.0.0.1');
  assert.equal(serverConfig({}).port, 8080);
  for (const PORT of ['', 'abc', '-1', '65536', '1.2']) assert.throws(() => serverConfig({ PORT }), /PORT/);
  assert.throws(() => serverConfig({ HOST: '0.0.0.0' }), /API_KEY/);
  assert.equal(serverConfig({ HOST: '0.0.0.0', API_KEY: 'demo-key' }).token, 'demo-key');
});
