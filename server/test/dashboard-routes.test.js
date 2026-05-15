import test from 'node:test';
import assert from 'node:assert/strict';

test('getDashboardUsage returns selected gateway usage snapshot', async () => {
  const routes = await import('../dist/routes/dashboard-routes.js');
  routes.initDashboardRoutes({
    getUsageDashboard: (gatewayId) => ({
      gateway_id: gatewayId,
      summary: { input: 1, output: 2, cacheRead: 0, cacheWrite: 0, reasoning: 0, total: 3 },
    }),
  });

  const res = fakeRes();
  routes.getDashboardUsage(fakeReq({ query: { gateway_id: 'hermes' } }), res);

  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body, {
    gateway_id: 'hermes',
    summary: { input: 1, output: 2, cacheRead: 0, cacheWrite: 0, reasoning: 0, total: 3 },
  });
});

function fakeReq({ query = {} } = {}) {
  return { query };
}

function fakeRes() {
  return {
    statusCode: 200,
    body: undefined,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };
}
