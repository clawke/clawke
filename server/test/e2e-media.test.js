#!/usr/bin/env node
/**
 * End-to-end test: send messages with media through CS → OpenClaw → AI
 * Run on the REMOTE server where CS is running.
 *
 * Tests:
 *   1. Text only (no media)
 *   2. Image via HTTP upload + WS message
 *   3. PDF via HTTP upload + WS message
 *   4. TXT via HTTP upload + WS message
 */
const WebSocket = require('ws');
const fs = require('fs');
const path = require('path');
const http = require('http');

const CS_WS = 'ws://127.0.0.1:8765';
const CS_HTTP = 'http://127.0.0.1:8780';
const TIMEOUT_MS = 60000; // 60s timeout for AI response

// --- Helpers ---

function uploadFileHTTP(buffer, fileName, mediaType) {
  return new Promise((resolve, reject) => {
    const boundary = '----Boundary' + Date.now();
    const parts = [
      `--${boundary}\r\n`,
      `Content-Disposition: form-data; name="file"; filename="${fileName}"\r\n`,
      `Content-Type: ${mediaType}\r\n\r\n`,
    ];
    const end = `\r\n--${boundary}--\r\n`;
    
    const bodyParts = [Buffer.from(parts.join('')), buffer, Buffer.from(end)];
    const body = Buffer.concat(bodyParts);

    const url = new URL(`${CS_HTTP}/api/media/upload`);
    const req = http.request({
      hostname: url.hostname,
      port: url.port,
      path: url.pathname,
      method: 'POST',
      headers: {
        'Content-Type': `multipart/form-data; boundary=${boundary}`,
        'Content-Length': body.length,
      },
    }, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        try { resolve({ status: res.statusCode, body: JSON.parse(data) }); }
        catch { resolve({ status: res.statusCode, body: data }); }
      });
    });
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

function sendAndWaitForReply(text, mediaData) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(CS_WS);
    const responses = [];
    let fullText = '';
    let hasThinking = false;
    let timer;

    ws.on('open', () => {
      const msg = {
        type: 'user_message',
        payload_type: 'text',
        from: 'test_user',
        message_id: `test_${Date.now()}`,
        payload: { data: { type: 'text', content: text } },
      };
      // If media, adjust payload
      if (mediaData) {
        msg.payload.data = {
          type: mediaData.fileType || 'image',
          mediaUrl: mediaData.mediaUrl,
          fileName: mediaData.fileName,
          mediaType: mediaData.mediaType,
          content: text,
        };
      }
      ws.send(JSON.stringify(msg));
      console.log(`    📤 Sent: "${text.slice(0, 50)}${text.length > 50 ? '...' : ''}"${mediaData ? ' + ' + mediaData.fileName : ''}`);

      timer = setTimeout(() => {
        ws.close();
        resolve({ fullText, responses, hasThinking, timedOut: true });
      }, TIMEOUT_MS);
    });

    ws.on('message', (raw) => {
      try {
        const msg = JSON.parse(raw.toString());
        responses.push(msg);

        if (msg.payload_type === 'text_delta') {
          fullText += msg.payload?.delta || '';
        } else if (msg.payload_type === 'text_done') {
          fullText = msg.payload?.fullText || fullText;
        } else if (msg.payload_type === 'thinking_delta') {
          hasThinking = true;
        } else if (msg.payload_type === 'text_done' || 
                   (msg.type === 'agent_text' && msg.text)) {
          fullText = msg.text || msg.payload?.text || fullText;
        }

        // Resolve when we get text_done or after receiving substantial text
        if (msg.payload_type === 'text_done') {
          clearTimeout(timer);
          setTimeout(() => { ws.close(); resolve({ fullText, responses, hasThinking, timedOut: false }); }, 500);
        }
      } catch {}
    });

    ws.on('error', (err) => {
      clearTimeout(timer);
      reject(err);
    });
  });
}

// --- Tests ---

async function main() {
  console.log('=== E2E Media Test: CS → OpenClaw → AI ===\n');

  // Test 1: Text only
  console.log('📝 Test 1: Text only (no media)');
  try {
    const r = await sendAndWaitForReply('Say "hello" in one word.');
    console.log(`    ✅ AI responded: "${r.fullText.slice(0, 100)}..." (${r.responses.length} messages)`);
    console.log(`    Thinking: ${r.hasThinking ? 'yes' : 'no'}, Timed out: ${r.timedOut}`);
  } catch (e) {
    console.log(`    ❌ Error: ${e.message}`);
  }

  // Test 2: Image
  console.log('\n📸 Test 2: Image upload → AI');
  try {
    // Create a small PNG (1x1 red pixel)
    const pngData = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==', 'base64');
    const upload = await uploadFileHTTP(pngData, 'test_red.png', 'image/png');
    console.log(`    Upload: ${upload.status} → ${JSON.stringify(upload.body).slice(0, 100)}`);

    if (upload.status === 200 && upload.body.mediaUrl) {
      const r = await sendAndWaitForReply('Describe this image in 10 words or less.', {
        fileType: 'image',
        mediaUrl: upload.body.mediaUrl,
        fileName: 'test_red.png',
        mediaType: 'image/png',
      });
      console.log(`    ✅ AI responded: "${r.fullText.slice(0, 150)}..." (${r.responses.length} messages)`);
    } else {
      console.log(`    ⚠️ Upload failed, skipping AI test`);
    }
  } catch (e) {
    console.log(`    ❌ Error: ${e.message}`);
  }

  // Test 3: PDF
  console.log('\n📄 Test 3: PDF upload → AI');
  try {
    const pdfContent = `%PDF-1.4
1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj
2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj
3 0 obj<</Type/Page/MediaBox[0 0 612 792]/Parent 2 0 R/Resources<<>>>>endobj
xref
0 4
trailer<</Size 4/Root 1 0 R>>
startxref
0
%%EOF`;
    const pdfBuf = Buffer.from(pdfContent);
    const upload = await uploadFileHTTP(pdfBuf, 'test_doc.pdf', 'application/pdf');
    console.log(`    Upload: ${upload.status} → ${JSON.stringify(upload.body).slice(0, 100)}`);

    if (upload.status === 200 && upload.body.mediaUrl) {
      const r = await sendAndWaitForReply('What type of file is this? Reply in 10 words or less.', {
        fileType: 'file',
        mediaUrl: upload.body.mediaUrl,
        fileName: 'test_doc.pdf',
        mediaType: 'application/pdf',
      });
      console.log(`    ✅ AI responded: "${r.fullText.slice(0, 150)}..." (${r.responses.length} messages)`);
    }
  } catch (e) {
    console.log(`    ❌ Error: ${e.message}`);
  }

  // Test 4: TXT
  console.log('\n📃 Test 4: TXT upload → AI');
  try {
    const txtBuf = Buffer.from('The quick brown fox jumps over the lazy dog.\nThis is a test file for Clawke media upload.');
    const upload = await uploadFileHTTP(txtBuf, 'test_note.txt', 'text/plain');
    console.log(`    Upload: ${upload.status} → ${JSON.stringify(upload.body).slice(0, 100)}`);

    if (upload.status === 200 && upload.body.mediaUrl) {
      const r = await sendAndWaitForReply('Summarize this text file in one sentence.', {
        fileType: 'file',
        mediaUrl: upload.body.mediaUrl,
        fileName: 'test_note.txt',
        mediaType: 'text/plain',
      });
      console.log(`    ✅ AI responded: "${r.fullText.slice(0, 150)}..." (${r.responses.length} messages)`);
    }
  } catch (e) {
    console.log(`    ❌ Error: ${e.message}`);
  }

  console.log('\n=== Done ===');
  process.exit(0);
}

main().catch(e => { console.error('Fatal:', e); process.exit(1); });
