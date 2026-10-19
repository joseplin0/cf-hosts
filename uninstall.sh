#!/usr/bin/env bash
# cf-hosts 卸载：取消 cron 定时 + 清理 hosts 托管区段（保留程序文件，可手动删目录）
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"

# 1) 取消 cron 定时
if command -v crontab >/dev/null 2>&1; then
  ( crontab -l 2>/dev/null | grep -v 'cf-hosts' ) | crontab - 2>/dev/null || true
fi

# 2) 注销全局命令（含 ~/.local/bin、~/bin、sudo 安装的；同步清掉 shell 配置里的 PATH/alias 行）
bash "$DIR/cf-hosts.sh" unlink || true

# 3) 清理 hosts 托管区段
bash "$DIR/cf-hosts.sh" clean || true

echo; echo "[cf-hosts] 已取消定时、删除全局命令并清理 hosts 托管区段。"
echo "程序文件保留在: $DIR （确认无误后可手动删除该目录）"
