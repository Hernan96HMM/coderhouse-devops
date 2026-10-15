const { test } = require('node:test');
const assert = require('node:assert');
const { createApp } = require('../src/app');

let server;
let base;

test.before(async () => {
  await new Promise((resolve) => {
    server = createApp().listen(0, () => {
      base = `http://127.0.0.1:${server.address().port}`;
      resolve();
    });
  });
});

test.after(() => server.close());

test('GET /health responde ok', async () => {
  const res = await fetch(`${base}/health`);
  assert.strictEqual(res.status, 200);
  assert.deepStrictEqual(await res.json(), { status: 'ok' });
});

test('GET /api/sum suma dos números', async () => {
  const res = await fetch(`${base}/api/sum?a=2&b=3`);
  assert.strictEqual(res.status, 200);
  assert.deepStrictEqual(await res.json(), { result: 5 });
});

test('GET /api/sum valida parámetros', async () => {
  const res = await fetch(`${base}/api/sum?a=x&b=3`);
  assert.strictEqual(res.status, 400);
});

test('GET /metrics expone métricas Prometheus', async () => {
  await fetch(`${base}/health`);
  const res = await fetch(`${base}/metrics`);
  const text = await res.text();
  assert.strictEqual(res.status, 200);
  assert.match(text, /http_requests_total/);
});
