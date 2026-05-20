const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

const {
  sendSkillGatewayRequestForTest,
  skillGatewayTimeoutMsFor,
  SkillGatewayError,
} = require('../dist/upstream/skill-gateway-client');

function fakeWs(onSend) {
  const listeners = new Map();
  return {
    readyState: 1,
    sent: [],
    on(event, handler) {
      listeners.set(event, handler);
    },
    removeListener(event, handler) {
      if (listeners.get(event) === handler) listeners.delete(event);
    },
    send(raw) {
      this.sent.push(JSON.parse(raw));
      onSend?.(this.sent[this.sent.length - 1], listeners.get('message'));
    },
  };
}

describe('Skill gateway client', () => {
  it('uses short ack timeout for SkillHub install requests', () => {
    assert.equal(skillGatewayTimeoutMsFor('skill_list'), 5000);
    assert.equal(skillGatewayTimeoutMsFor('skillhub_install'), 5000);
  });

  it('routes skill_list with request_id and resolves matching response', async () => {
    const ws = fakeWs((request, onMessage) => {
      assert.equal(request.type, 'skill_list');
      assert.equal(request.account_id, 'hermes-work');
      assert.ok(request.request_id);
      onMessage(Buffer.from(JSON.stringify({
        type: 'skill_list_response',
        request_id: request.request_id,
        ok: true,
        skills: [{ id: 'apple/apple-notes', name: 'apple-notes' }],
      })));
    });

    const response = await sendSkillGatewayRequestForTest(ws, {
      type: 'skill_list',
      account_id: 'hermes-work',
    });

    assert.equal(response.type, 'skill_list_response');
    assert.equal(response.skills[0].id, 'apple/apple-notes');
  });

  it('rejects gateway error responses', async () => {
    const ws = fakeWs((request, onMessage) => {
      onMessage(Buffer.from(JSON.stringify({
        type: 'skill_mutation_response',
        request_id: request.request_id,
        ok: false,
        error: 'skill_error',
        message: 'boom',
      })));
    });

    await assert.rejects(
      () => sendSkillGatewayRequestForTest(ws, {
        type: 'skill_delete',
        account_id: 'hermes-work',
        skill_id: 'apple/apple-notes',
      }),
      (err) => err instanceof SkillGatewayError && err.code === 'skill_error' && err.message === 'boom',
    );
  });

  it('routes skillhub_install to skillhub_install_response', async () => {
    const ws = fakeWs((request, onMessage) => {
      assert.equal(request.type, 'skillhub_install');
      assert.equal(request.account_id, 'openclaw-local');
      assert.equal(request.package.slug, 'github-helper');
      onMessage(Buffer.from(JSON.stringify({
        type: 'skillhub_install_response',
        request_id: request.request_id,
        ok: true,
        installed: true,
      })));
    });

    const response = await sendSkillGatewayRequestForTest(ws, {
      type: 'skillhub_install',
      account_id: 'openclaw-local',
      package: {
        id: '204',
        slug: 'github-helper',
        name: 'GitHub Helper',
        version: '1.2.1',
        packageUrl: 'https://local.clawke.ai/upload/package.zip',
        packageSha256: 'bed752338e7a19db1074e239075c4cd24fd5da73b0d40bfe040a496d73119371',
        packageType: 'bundle',
      },
    });

    assert.equal(response.type, 'skillhub_install_response');
    assert.equal(response.installed, true);
  });
});
