/**
 * Mock 文件读取处理器
 */
import fs from 'fs';
import path from 'path';
import type { WebSocket } from 'ws';

export function handleReadFile(ws: WebSocket, payload: any): void {
  const filepath = (payload.data && payload.data.filepath) || '';
  console.log(`[Tunnel] 📂 read_file request: ${filepath}`);

  const resolved = path.resolve(filepath);
  if (filepath.includes('..')) {
    console.error(`[Tunnel] ❌ Path injection blocked: ${filepath}`);
    return;
  }

  if (!resolved.endsWith('.md')) {
    console.warn(`[Tunnel] ⚠️ Non .md file, ignored: ${resolved}`);
    return;
  }

  let content: string;
  try {
    content = fs.readFileSync(resolved, 'utf-8');
  } catch (e: any) {
    console.error(`[Tunnel] ❌ File read failed: ${e.message}`);
    if ((ws as any).readyState === 1) {
      try {
        (ws as any).send(JSON.stringify({
          message_id: `msg_${Date.now()}`,
          payload_type: 'text_delta',
          content: `文件读取失败：${filepath}`,
        }));
      } catch {}
    }
    return;
  }

  const msgId = `msg_${Date.now()}`;
  const filename = path.basename(resolved);
  console.log(`[Tunnel] ⬇️ Sent MarkdownView: ${filename} (${content.length} chars)`);

  if ((ws as any).readyState === 1) {
    try {
      (ws as any).send(JSON.stringify({
        role: 'agent', agent_id: 'mock_agent', message_id: msgId,
        payload_type: 'ui_component',
        component: { widget_name: 'MarkdownView', props: { content }, actions: [] },
      }));
    } catch {}
  }
}
