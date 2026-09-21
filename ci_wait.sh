#!/bin/bash
# 轮询 GitHub Actions run 直到进入终态，输出结论后退出
TOKEN=$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null | sed -n 's/^password=//p')
RUN=35631692582
while true; do
  STATUS=$(curl -s -H "Authorization: Bearer $TOKEN" "https://api.github.com/repos/JackEric6/CongcongTV-iOS/actions/runs/$RUN" | python -X utf8 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('status','?'),'|',d.get('conclusion','?'))
")
  S=$(echo "$STATUS" | cut -d'|' -f1 | xargs)
  if [ "$S" = "completed" ]; then
    echo "CI FINISHED: $STATUS"
    exit 0
  fi
  sleep 30
done
