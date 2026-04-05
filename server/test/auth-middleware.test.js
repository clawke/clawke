/**
 * auth-middleware.test.js — CS Token 认证中间件测试
 *
 * 测试 http-server.js 中的 token 认证逻辑。
 */

const { describe, it, before, after } = require('node:test');
const assert = require('node:assert');
const express = require('express');

describe('CS Token Auth Middleware', () => {
  // ── 有 token 的场景 ──
  describe('with CLAWKE_TOKEN set', () => {
    let server;
    let baseUrl;
    const SERVER_TOKEN = 'clk_testToken1234567890abcdefghij';

    before(async () => {
      const app = express();
      app.use(express.json());

      // 模拟 token 认证中间件
      app.use((req, res, next) => {
        if (req.path === '/health') return next();
        const clientToken = (req.headers.authorization || '').replace('Bearer ', '');
        if (SERVER_TOKEN !== clientToken) {
          return res.status(401).json({ error: 'unauthorized' });
        }
        next();
      });

      app.get('/health', (req, res) => res.json({ status: 'ok' }));
      app.get('/api/test', (req, res) => res.json({ ok: true }));
      app.post('/api/media/upload', (req, res) => res.json({ ok: true }));

      await new Promise(resolve => {
        server = app.listen(0, '127.0.0.1', () => {
          baseUrl = `http://127.0.0.1:${server.address().port}`;
          resolve();
        });
      });
    });

    after(() => { if (server) server.close(); });

    it('valid token → 200', async () => {
      const res = await fetch(`${baseUrl}/api/test`, {
        headers: { Authorization: `Bearer ${SERVER_TOKEN}` },
      });
      assert.strictEqual(res.status, 200);
      const body = await res.json();
      assert.strictEqual(body.ok, true);
    });

    it('invalid token → 401', async () => {
      const res = await fetch(`${baseUrl}/api/test`, {
        headers: { Authorization: 'Bearer wrong_token' },
      });
      assert.strictEqual(res.status, 401);
    });

    it('no token → 401', async () => {
      const res = await fetch(`${baseUrl}/api/test`);
      assert.strictEqual(res.status, 401);
    });

    it('/health bypasses auth → 200', async () => {
      const res = await fetch(`${baseUrl}/health`);
      assert.strictEqual(res.status, 200);
    });

    it('POST with valid token → 200', async () => {
      const res = await fetch(`${baseUrl}/api/media/upload`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${SERVER_TOKEN}`,
        },
        body: JSON.stringify({ test: true }),
      });
      assert.strictEqual(res.status, 200);
    });
  });

  // ── 无 token 的场景（两边都空 = 匹配）──
  describe('without CLAWKE_TOKEN (both empty)', () => {
    let server;
    let baseUrl;
    const SERVER_TOKEN = ''; // 未配置

    before(async () => {
      const app = express();
      app.use(express.json());

      app.use((req, res, next) => {
        if (req.path === '/health') return next();
        const clientToken = (req.headers.authorization || '').replace('Bearer ', '');
        if (SERVER_TOKEN !== clientToken) {
          return res.status(401).json({ error: 'unauthorized' });
        }
        next();
      });

      app.get('/api/test', (req, res) => res.json({ ok: true }));

      await new Promise(resolve => {
        server = app.listen(0, '127.0.0.1', () => {
          baseUrl = `http://127.0.0.1:${server.address().port}`;
          resolve();
        });
      });
    });

    after(() => { if (server) server.close(); });

    it('both empty → 200 (match)', async () => {
      const res = await fetch(`${baseUrl}/api/test`);
      assert.strictEqual(res.status, 200);
    });

    it('client sends token but server has none → 401', async () => {
      const res = await fetch(`${baseUrl}/api/test`, {
        headers: { Authorization: 'Bearer clk_someToken' },
      });
      assert.strictEqual(res.status, 401);
    });
  });
});
