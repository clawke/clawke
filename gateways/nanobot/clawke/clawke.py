"""Clawke channel — connects nanobot to Clawke Server as an AI gateway.

Protocol reference: docs/GATEWAY_INTEGRATION.md

This channel acts as a WebSocket client connecting to Clawke Server's upstream
port (default 8766). It translates between nanobot's InboundMessage/OutboundMessage
and Clawke's gateway protocol (agent_text_delta, agent_text_done, etc.).
"""

from __future__ import annotations

import asyncio
import json
import time
from typing import Any

import websockets
from loguru import logger

from nanobot.bus.events import InboundMessage, OutboundMessage
from nanobot.bus.queue import MessageBus
from nanobot.channels.base import BaseChannel


class ClawkeChannel(BaseChannel):
    """Clawke gateway channel — WebSocket client to Clawke Server."""

    name = "clawke"

    # Exponential backoff parameters
    _BACKOFF_FIRST_S = 0.1
    _BACKOFF_MAX_S = 10.0
    _BACKOFF_BASE = 2

    def __init__(self, config: Any, bus: MessageBus):
        super().__init__(config, bus)
        self._ws: Any = None
        self._reconnect_attempt = 0
        self._tasks: list[asyncio.Task] = []

        # Streaming state: track in-flight message for delta → done logic
        self._stream_msg_id: str | None = None
        self._stream_sent_any = False

    @property
    def _url(self) -> str:
        return getattr(self.config, "url", "ws://127.0.0.1:8766")

    @property
    def _account_id(self) -> str:
        return getattr(self.config, "account_id", "nanobot")

    async def start(self) -> None:
        """Start the Clawke channel: connect and listen."""
        self._running = True
        logger.info("Clawke channel starting → {}", self._url)

        while self._running:
            try:
                await self._connect()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error("Clawke connection error: {}", e)

            if not self._running:
                break

            # Exponential backoff with jitter
            delay = self._backoff_delay()
            self._reconnect_attempt += 1
            logger.info("Reconnecting to Clawke Server in {:.1f}s (attempt {})",
                        delay, self._reconnect_attempt)
            await asyncio.sleep(delay)

    async def _connect(self) -> None:
        """Establish WebSocket connection and handle messages."""
        async with websockets.connect(self._url) as ws:
            self._ws = ws
            self._reconnect_attempt = 0
            logger.info("Connected to Clawke Server")

            # Handshake: identify
            await ws.send(json.dumps({
                "type": "identify",
                "accountId": self._account_id,
            }))
            logger.info("Identified as account={}", self._account_id)

            # Listen for inbound messages
            async for raw in ws:
                try:
                    msg = json.loads(raw)
                except (json.JSONDecodeError, TypeError):
                    continue

                if msg.get("type") == "chat":
                    await self._handle_inbound(msg)
                elif msg.get("type") == "abort":
                    logger.info("Abort request: conversation={}",
                                msg.get("conversation_id"))
                elif msg.get("type") == "query_models":
                    await ws.send(json.dumps({
                        "type": "models_response",
                        "models": [],
                    }))
                elif msg.get("type") == "query_skills":
                    await ws.send(json.dumps({
                        "type": "skills_response",
                        "skills": [],
                    }))

        self._ws = None
        logger.info("Disconnected from Clawke Server")

    async def _handle_inbound(self, msg: dict) -> None:
        """Convert Clawke chat message to nanobot InboundMessage."""
        text = msg.get("text", "")
        client_msg_id = msg.get("client_msg_id", f"clawke_{int(time.time() * 1000)}")
        sender_id = msg.get("conversation_id", "clawke_user")
        chat_id = f"clawke:{sender_id}"

        # 保存 conversation_id 供下行消息使用
        self._current_conversation_id = sender_id

        if not self.is_allowed(sender_id):
            logger.warning("Access denied for clawke_user")
            return

        # Media handling
        media: list[str] = []
        media_block = msg.get("media")
        if media_block:
            # Prefer HTTP URLs for cross-machine compatibility
            http_base = (media_block.get("httpBase") or "").rstrip("/")
            rel_urls = media_block.get("relativeUrls") or []
            paths = media_block.get("paths") or []

            if http_base and rel_urls:
                media = [f"{http_base}{u}" for u in rel_urls]
            elif paths:
                media = paths

        logger.info("📥 Inbound from Clawke: {} (media={})", text[:80], bool(media))

        await self._handle_message(
            sender_id=sender_id,
            chat_id=chat_id,
            content=text,
            media=media if media else None,
            metadata={"message_id": client_msg_id},
        )
        logger.info("📥 Dispatched to nanobot: chat_id={} msg_id={}", chat_id, client_msg_id)

    async def send(self, msg: OutboundMessage) -> None:
        """Send outbound message to Clawke Server via the gateway protocol."""
        if not self._ws:
            logger.warning("Clawke WS not connected, dropping message")
            return

        text = msg.content or ""
        is_progress = msg.metadata.get("_progress", False)
        is_tool_hint = msg.metadata.get("_tool_hint", False)
        to = f"user:clawke_user"

        # 从 OutboundMessage 的 chat_id 解析 conversation_id（格式 "clawke:{conv_id}"）
        conv_id = (msg.chat_id.split(":", 1)[1]
                   if msg.chat_id and ":" in msg.chat_id
                   else getattr(self, '_current_conversation_id', 'clawke_user'))

        try:
            if is_tool_hint:
                # Tool call notification
                tool_call_id = f"tool_{int(time.time() * 1000)}"
                await self._ws.send(json.dumps({
                    "type": "agent_tool_call",
                    "message_id": self._ensure_stream_id(),
                    "toolCallId": tool_call_id,
                    "toolName": text.split("(")[0] if "(" in text else text,
                    "account_id": self._account_id,
                    "conversation_id": conv_id,
                }))
                logger.info("📤 Tool call to Clawke: {} conv={}", text[:60], conv_id)

            elif is_progress:
                # Thinking / intermediate progress → thinking_delta
                if text.strip():
                    await self._ws.send(json.dumps({
                        "type": "agent_thinking_delta",
                        "message_id": f"think_{self._ensure_stream_id()}",
                        "delta": text,
                        "account_id": self._account_id,
                        "conversation_id": conv_id,
                    }))
                    logger.debug("📤 Thinking delta to Clawke: {} conv={}", text[:40], conv_id)

            else:
                # Final reply → close any thinking stream, then send full text
                if self._stream_sent_any:
                    # End thinking stream
                    await self._ws.send(json.dumps({
                        "type": "agent_thinking_done",
                        "message_id": f"think_{self._stream_msg_id}",
                        "account_id": self._account_id,
                        "conversation_id": conv_id,
                    }))

                # Send complete text as non-streaming reply
                msg_id = self._ensure_stream_id()
                await self._ws.send(json.dumps({
                    "type": "agent_text",
                    "message_id": msg_id,
                    "text": text,
                    "to": to,
                    "account_id": self._account_id,
                    "conversation_id": conv_id,
                    "model": "nanobot",
                    "provider": "nanobot",
                }))

                # Reset streaming state
                self._stream_msg_id = None
                self._stream_sent_any = False

                logger.info("📤 Reply to Clawke: {}", text[:80])

        except Exception as e:
            logger.error("Failed to send to Clawke Server: {}", e)

    async def stop(self) -> None:
        """Stop the Clawke channel."""
        self._running = False
        if self._ws:
            await self._ws.close()
            self._ws = None
        for task in self._tasks:
            task.cancel()
        logger.info("Clawke channel stopped")

    def _ensure_stream_id(self) -> str:
        """Get or create the current stream message ID."""
        if not self._stream_msg_id:
            self._stream_msg_id = f"reply_{int(time.time() * 1000)}"
        self._stream_sent_any = True
        return self._stream_msg_id

    def _backoff_delay(self) -> float:
        """Calculate exponential backoff delay with ±25% jitter."""
        import random
        exp = self._BACKOFF_FIRST_S * (self._BACKOFF_BASE ** self._reconnect_attempt)
        capped = min(exp, self._BACKOFF_MAX_S)
        return capped * (0.75 + random.random() * 0.5)
