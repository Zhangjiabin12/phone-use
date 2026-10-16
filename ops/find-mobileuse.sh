#!/bin/bash
export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890
echo "=== 搜索 mobile-use 相关仓库（按 star 排序）==="
curl -s --max-time 40 "https://api.github.com/search/repositories?q=mobile-use+in:name&sort=stars&order=desc&per_page=8" \
 | python3 -c "
import json,sys
try:
    for r in json.load(sys.stdin).get('items',[]):
        print('  %-45s ★%-6s %s' % (r['full_name'], r['stargazers_count'], (r.get('description') or '')[:80]))
except Exception as e:
    print('  搜索失败:', e)
"
echo
echo "=== 再搜 android agent / phone agent ==="
curl -s --max-time 40 "https://api.github.com/search/repositories?q=android+agent+llm+in:name,description&sort=stars&order=desc&per_page=8" \
 | python3 -c "
import json,sys
try:
    for r in json.load(sys.stdin).get('items',[]):
        print('  %-45s ★%-6s %s' % (r['full_name'], r['stargazers_count'], (r.get('description') or '')[:80]))
except Exception as e:
    print('  搜索失败:', e)
"
