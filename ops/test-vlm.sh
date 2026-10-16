#!/bin/bash
KEY=$(grep -oP '^BU_LLM_API_KEY=\K.*' /opt/webui-mcp/bu/bu.env | tr -d '"' | tr -d "'" | tr -d '\r')
BASE=http://131.255.36.100:30001/v1
python3 - <<'PY'
import struct, zlib
def chunk(t, d):
    c = t + d
    return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
w = h = 8
raw = b''.join(b'\x00' + b'\xff\x00\x00' * w for _ in range(h))
png = (b'\x89PNG\r\n\x1a\n'
       + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
       + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))
open('/tmp/tiny.png', 'wb').write(png)
print('  tiny.png', len(png), '字节')
PY
B64=$(base64 -w0 /tmp/tiny.png)
for M in doubao-seed-2.1-pro doubao-seed-2.0-pro deepseek-flash glm-5.3-flash qwen-3.8-27b; do
  printf "  %-22s " "$M"
  curl -s -m 45 -X POST "$BASE/chat/completions" -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
    -d "{\"model\":\"$M\",\"max_tokens\":12,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"这张图什么颜色？一个字\"},{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/png;base64,$B64\"}}]}]}" \
  > /tmp/vlm_out.json 2>&1
  python3 - <<'PY'
import json
t = open('/tmp/vlm_out.json', encoding='utf-8', errors='ignore').read()
try:
    d = json.loads(t)
    if 'choices' in d:
        print('✓ 接受图像 →', str(d['choices'][0]['message'].get('content'))[:40])
    else:
        print('✗', str(d.get('error', d))[:120])
except Exception:
    print('✗ 非 JSON:', t[:120])
PY
done
