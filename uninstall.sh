#!/usr/bin/env bash
# cf-hosts 卸载：取消 cron 定时 + 清理 hosts 托管区段（保留程序文件，可手动删目录）
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"

# 1) 取消 cron 定时
if command -v crontab >/dev/null 2>&1; then
  ( crontab -l 2>/dev/null | grep -v 'cf-hosts' ) | crontab - 2>/dev/null || true
fi

# 2) 删除全局命令符号链接（符号链接或 ln 失败留下的 0 字节文件；不碰有内容的真文件）
for bindir in ${BIN_DIRS:-/usr/local/bin /usr/bin /bin}; do
  f="$bindir/cf-hosts"
  if [ -L "$f" ] || { [ -f "$f" ] && [ ! -s "$f" ]; }; then rm -f "$f" 2>/dev/null; fi
done

# 3) 清理 hosts 托管区段
bash "$DIR/cf-hosts.sh" clean || true

echo; echo "[cf-hosts] 已取消定时、删除全局命令并清理 hosts 托管区段。"
echo "程序文件保留在: $DIR （确认无误后可手动删除该目录）"
