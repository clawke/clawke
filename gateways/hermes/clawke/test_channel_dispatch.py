from __future__ import annotations

import asyncio
import unittest

from clawke_channel import ClawkeHermesGateway, GatewayConfig, InboundMessageType


class ChannelDispatchTest(unittest.IsolatedAsyncioTestCase):
    async def test_gateway_system_request_does_not_block_skillhub_install(self):
        gateway = ClawkeHermesGateway(GatewayConfig(account_id="hermes"))
        started = asyncio.Event()
        finish = asyncio.Event()
        skill_calls: list[str] = []

        async def fake_system_request(_msg: dict) -> None:
            started.set()
            await finish.wait()

        async def fake_skill_command(msg: dict) -> None:
            skill_calls.append(str(msg.get("type")))

        gateway._handle_gateway_system_request = fake_system_request
        gateway._handle_skill_command = fake_skill_command

        await gateway._handle_inbound_message({
            "type": InboundMessageType.GatewaySystemRequest,
            "request_id": "system_1",
        })
        await asyncio.wait_for(started.wait(), timeout=1)

        await gateway._handle_inbound_message({
            "type": InboundMessageType.SkillHubInstall,
            "request_id": "install_1",
            "package": {"slug": "weather"},
        })

        self.assertEqual(skill_calls, [InboundMessageType.SkillHubInstall])
        finish.set()
        if gateway._active_dispatches:
            await asyncio.gather(*list(gateway._active_dispatches))


if __name__ == "__main__":
    unittest.main()
