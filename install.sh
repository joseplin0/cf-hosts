#!/usr/bin/env bash
# cf-hosts 安装器（纯 shell，零运行时依赖）——支持本地安装 & 远端一键安装
#
# 远端一键安装（国内网络首选 jsdelivr，raw.githubusercontent.com 常被重置）：
#   curl -fsSL https://cdn.jsdelivr.net/gh/joseplin0/cf-hosts@main/install.sh \
#     | REPO_RAW=https://cdn.jsdelivr.net/gh/joseplin0/cf-hosts@main bash
# 官方 raw 源（网络环境好时用）：
#   curl -fsSL https://raw.githubusercontent.com/joseplin0/cf-hosts/main/install.sh | bash
# 显式指定仓库（改了仓库名/分支时用）：
#   curl -fsSL <任意镜像>/install.sh | REPO_RAW=<对应地址> bash
#
# 本地安装（已 git clone 到本机）：bash install.sh
set -u
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/joseplin0/cf-hosts/main}"
# 国内网络自动回退镜像（按顺序尝试；失效时可自行更新此列表，或用 MIRRORS=... 覆盖）
MIRRORS="${MIRRORS:-https://cdn.jsdelivr.net/gh/joseplin0/cf-hosts@main https://ghfast.top/https://raw.githubusercontent.com/joseplin0/cf-hosts/main}"
FILES="cf-hosts.sh cf-hosts.conf.example install.sh uninstall.sh README.md LICENSE"
say(){ echo; echo "[cf-hosts] $*"; }

# 通用下载：依次尝试 $REPO_RAW 和 $MIRRORS，任一成功即返回
fetch_file(){ # $1=文件名 $2=输出路径
  local f="$1" out="$2" base
  for base in "$REPO_RAW" $MIRRORS; do
    if curl -fsSL --connect-timeout 10 --max-time 60 "$base/$f" -o "$out" 2>/dev/null && [ -s "$out" ]; then
      echo "  ✔ $f  <- $base"; return 0
    fi
    rm -f "$out"
  done
  echo "  ✘ $f 所有镜像均下载失败"; return 1
}

DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"

# ---- 引导模式：旁边没有 cf-hosts.sh，说明是 curl|bash 远端运行 → 先把项目拉到安装目录 ----
if [ -z "$DIR" ] || [ ! -f "$DIR/cf-hosts.sh" ]; then
  # 选择安装目录（可用 CF_INSTALL_DIR 覆盖）
  if [ -n "${CF_INSTALL_DIR:-}" ]; then INSTALL_DIR="$CF_INSTALL_DIR"
  elif [ -d /share ]; then INSTALL_DIR="/share/Container/cf-hosts"        # QNAP
  elif [ "$(uname -s)" = "Darwin" ]; then INSTALL_DIR="$HOME/.cf-hosts"   # macOS
  else INSTALL_DIR="$HOME/.cf-hosts"; fi                                  # Linux/其他
  say "下载项目文件到 $INSTALL_DIR ..."
  mkdir -p "$INSTALL_DIR"
  for f in $FILES; do
    fetch_file "$f" "$INSTALL_DIR/$f" || { echo "请检查网络，或手动下载全部文件放入 $INSTALL_DIR 后执行 bash $INSTALL_DIR/install.sh"; exit 1; }
  done
  chmod +x "$INSTALL_DIR/cf-hosts.sh" "$INSTALL_DIR/install.sh" "$INSTALL_DIR/uninstall.sh" 2>/dev/null || true
  say "下载完成，开始在本地安装 ..."
  REPO_RAW="$REPO_RAW" MIRRORS="$MIRRORS" exec bash "$INSTALL_DIR/install.sh"
fi

# ===== 本地安装（$DIR 内含全部文件）=====
arch_ga(){ case "$(uname -m)" in x86_64|amd64) echo amd64;; aarch64|arm64) echo arm64;; *) echo amd64;; esac; }
os_lc(){ echo "$(uname -s | tr 'A-Z' 'a-z')"; }

# 1) 下载 CloudflareSpeedTest（如缺）——GitHub release 直连 + ghproxy 镜像链
CF="$DIR/CloudflareSpeedTest"
if [ ! -x "$CF" ]; then
  GA=$(arch_ga); OS=$(os_lc)
  # 取最新版本号：api.github.com 失败时回退 kkgithub 镜像 API
  VER=$(curl -fsSL --connect-timeout 10 --max-time 20 https://api.github.com/repos/XIU2/CloudflareSpeedTest/releases/latest 2>/dev/null | grep -m1 '"tag_name"' | sed -E 's/.*"v?([0-9][^"]*)".*/\1/')
  if [ -z "${VER:-}" ]; then
    VER=$(curl -fsSL --connect-timeout 10 --max-time 20 https://api.kkgithub.com/repos/XIU2/CloudflareSpeedTest/releases/latest 2>/dev/null | grep -m1 '"tag_name"' | sed -E 's/.*"v?([0-9][^"]*)".*/\1/')
  fi
  if [ -n "${VER:-}" ]; then
    NAME="CloudflareSpeedTest_${VER}_${OS}_${GA}.tar.gz"
    REL="https://github.com/XIU2/CloudflareSpeedTest/releases/download/v${VER}/${NAME}"
    ok=0
    for u in "$REL" "https://ghfast.top/$REL" "https://gh-proxy.com/$REL" "https://ghproxy.net/$REL" "https://mirror.ghproxy.com/$REL"; do
      say "尝试下载: $u"
      rm -f "$DIR/cst.tar.gz"
      if curl -fL --connect-timeout 10 --max-time 300 "$u" -o "$DIR/cst.tar.gz" 2>/dev/null && tar -tzf "$DIR/cst.tar.gz" >/dev/null 2>&1; then
        if tar -xzf "$DIR/cst.tar.gz" -C "$DIR" && [ -f "$CF" ]; then
          chmod +x "$CF"; ok=1; rm -f "$DIR/cst.tar.gz"; break
        fi
      fi
    done
    [ "$ok" = 1 ] || { rm -f "$DIR/cst.tar.gz"; say "所有下载源均失败，请手动下载 ${NAME} 解压后把 CloudflareSpeedTest 放到 $DIR"; }
  else say "取不到版本号（GitHub API 限流?），请手动下载 CloudflareSpeedTest 对应平台版放到 $DIR"; fi
else say "已存在 CloudflareSpeedTest"; fi

# 2) 生成配置（缺失才建）
if [ ! -f "$DIR/cf-hosts.conf" ]; then
  cat > "$DIR/cf-hosts.conf" <<EOF
PORT=9876
INTERVAL=60
AUTO=on
USE_IPV6=off
MAX_MS=200
MAX_LOSS=0
HOSTS="/etc/hosts"
DOMAINS=""
CF_BIN="$CF"
EOF
  say "已生成 cf-hosts.conf"
fi

# 3) 注册 cron 定时（开机 + 每 N 分钟）
bash "$DIR/cf-hosts.sh" refresh || true

# 4) 立即跑一次
say "立即执行一次优选 ..."
bash "$DIR/cf-hosts.sh" update || true

LANIP=$(hostname -I 2>/dev/null | awk '{print $1}')
say "完成 ✅  安装目录: $DIR"
say "加站点 : bash $DIR/cf-hosts.sh domains add tracker.你的域名.com"
say "看状态 : bash $DIR/cf-hosts.sh status"
say "改频率 : bash $DIR/cf-hosts.sh interval 30"
say "日志   : $DIR/cf-hosts.log"
[ -n "${LANIP:-}" ] && say "本机IP: $LANIP（仅供参考）"
