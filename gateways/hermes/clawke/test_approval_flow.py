#!/usr/bin/env python3
"""Quick diagnostic: test approval_response routing end-to-end.

Connects to Clawke Server client WS, sends an approval_response,
and checks if the Server logs confirm receipt.
"""

import asyncio
import json
import sys
import websockets

SERVER_URL = "ws://127.0.0.1:8780/ws"


async def main():
    print(f"[Test] Connecting to {SERVER_URL} ...")
    try:
        async with websockets.connect(SERVER_URL) as ws:
            print("[Test] ✅ Connected to Clawke Server")

            # Listen for any response in background
            async def listener():
                try:
                    async for msg in ws:
                        data = json.loads(msg)
                        ptype = data.get("payload_type") or data.get("type") or "?"
                        print(f"[Test] 📥 Received: {ptype} → {json.dumps(data)[:200]}")
                except Exception:
                    pass

            listener_task = asyncio.create_task(listener())

            # Wait a moment for connection setup
            await asyncio.sleep(0.5)

            # Send a fake approval_response (same format as Flutter client)
            test_msg = {
                "event_type": "approval_response",
                "context": {
                    "account_id": "hermes",
                    "conversation_id": "test-conv-123",
                },
                "data": {
                    "conversation_id": "test-conv-123",
                    "choice": "once",
                },
            }
            print(f"\n[Test] 📤 Sending approval_response: {json.dumps(test_msg)}")
            await ws.send(json.dumps(test_msg))
            print("[Test] ✅ Sent! Check Server terminal for:")
            print("       [Tunnel] 📥 event_type=approval_response, account=hermes")
            print("       [Tunnel] ✅ approval_response: conv=test-conv-123 choice=once")
            print("       [Gateway] ➡️  sendToOpenClaw(hermes): type=approval_response")
            print()
            print("[Test] If you see 'Unknown event_type: approval_response' → Server not rebuilt")
            print("[Test] If you see NO log at all → message not reaching Server")
            print()

            # Wait a few seconds for any response
            await asyncio.sleep(3)
            listener_task.cancel()
            print("[Test] Done. Check the Server terminal output above.")

    except Exception as e:
        print(f"[Test] ❌ Connection failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
