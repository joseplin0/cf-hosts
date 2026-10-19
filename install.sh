#!/usr/bin/env bash
# cf-hosts 安装器（纯 shell，零运行时依赖）——支持本地安装 & 远端一键安装
#
# 远端一键安装（国内移动/电信宽带首选 codeload 官方 tarball；raw/jsdelivr 均被 TLS 重置）：
#   D=$(mktemp -d) && curl -fsSL https://codeload.github.com/joseplin0/cf-hosts/tar.gz/refs/heads/main \
#     | tar -xz -C "$D" && bash "$D"/cf-hosts-*/install.sh
# 或者 git clone（github.com 可达时最快）：
#   git clone --depth 1 https://github.com/joseplin0/cf-hosts.git /share/Container/cf-hosts \
#     && bash /share/Container/cf-hosts/install.sh
# 网络好时也可用 raw / jsdelivr 源（curl|bash）：
#   curl -fsSL https://raw.githubusercontent.com/joseplin0/cf-hosts/main/install.sh | bash
#   curl -fsSL https://cdn.jsdelivr.net/gh/joseplin0/cf-hosts@main/install.sh \
#     | REPO_RAW=https://cdn.jsdelivr.net/gh/joseplin0/cf-hosts@main bash
#
# 本地安装（已 clone/解压到本机）：bash install.sh
set -u
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/joseplin0/cf-hosts/main}"
# 国内网络自动回退镜像（按顺序尝试；失效时可自行更新此列表，或用 MIRRORS=... 覆盖）
MIRRORS="${MIRRORS:-https://cdn.jsdelivr.net/gh/joseplin0/cf-hosts@main https://ghfast.top/https://raw.githubusercontent.com/joseplin0/cf-hosts/main}"
# codeload 官方 tarball：国内移动宽带下 raw/jsdelivr（均 Fastly）常被重置，codeload 通常可达
CODELOAD_URL="${CODELOAD_URL:-https://codeload.github.com/joseplin0/cf-hosts/tar.gz/refs/heads/main}"
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

# ---- 选择安装目录 ----
if [ -n "${CF_INSTALL_DIR:-}" ]; then INSTALL_DIR="$CF_INSTALL_DIR"
elif [ -d /share ]; then INSTALL_DIR="/share/Container/cf-hosts"        # QNAP
elif [ "$(uname -s)" = "Darwin" ]; then INSTALL_DIR="$HOME/.cf-hosts"   # macOS
else INSTALL_DIR="$HOME/.cf-hosts"; fi                                  # Linux/其他

DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"

# ---- 引导模式：把项目文件安置到 INSTALL_DIR ----
# 触发条件：curl|bash 运行（$DIR 为空）/ 旁边没有 cf-hosts.sh / 运行位置不是安装目录
need_boot=0
[ -z "$DIR" ] && need_boot=1
[ -n "$DIR" ] && [ ! -f "$DIR/cf-hosts.sh" ] && need_boot=1
[ -n "$DIR" ] && [ "$DIR" != "$INSTALL_DIR" ] && need_boot=1

if [ "$need_boot" = "1" ]; then
  mkdir -p "$INSTALL_DIR"
  # 方式0：本地已有完整项目（如 curl tarball 解压后运行 / git clone 后运行）→ 直接复制，不走网络
  if [ -n "$DIR" ] && [ -f "$DIR/cf-hosts.sh" ]; then
    say "从 $DIR 复制项目文件到 $INSTALL_DIR ..."
    cp -rf "$DIR/." "$INSTALL_DIR/" 2>/dev/null
  fi
  # 方式1：codeload 官方 tarball（国内可用率最高，一次拿全量文件；--strip-components 直接解压进安装目录）
  if [ ! -f "$INSTALL_DIR/cf-hosts.sh" ] && [ "${SKIP_TARBALL:-0}" != "1" ]; then
    say "通过 codeload 官方 tarball 下载项目（国内宽带推荐路径）..."
    TB="$INSTALL_DIR/.cf-hosts-boot.tgz"
    if curl -fsSL --connect-timeout 10 --max-time 120 "$CODELOAD_URL" -o "$TB" 2>/dev/null && tar -tzf "$TB" >/dev/null 2>&1; then
      tar -xzf "$TB" --strip-components=1 -C "$INSTALL_DIR" 2>/dev/null && say "tarball 解压完成（$(ls "$INSTALL_DIR" | wc -l) 个条目）"
    fi
    rm -f "$TB" 2>/dev/null
  fi
  # 方式2：逐文件镜像（raw / jsdelivr / ghfast）
  if [ ! -f "$INSTALL_DIR/cf-hosts.sh" ]; then
    say "codeload 不可用，改用逐文件镜像下载 ..."
    for f in $FILES; do
      fetch_file "$f" "$INSTALL_DIR/$f" || { echo "请检查网络，或手动下载全部文件放入 $INSTALL_DIR 后执行 bash $INSTALL_DIR/install.sh"; exit 1; }
    done
  fi
  [ -f "$INSTALL_DIR/cf-hosts.sh" ] || { echo "项目文件获取失败（codeload/镜像均不可达）"; exit 1; }
  chmod +x "$INSTALL_DIR/cf-hosts.sh" "$INSTALL_DIR/install.sh" "$INSTALL_DIR/uninstall.sh" 2>/dev/null || true
  say "项目文件就绪，开始本地安装 ..."
  REPO_RAW="$REPO_RAW" MIRRORS="$MIRRORS" CODELOAD_URL="$CODELOAD_URL" exec bash "$INSTALL_DIR/install.sh"
fi

# ===== 本地安装（$DIR 内含全部文件）=====
arch_ga(){ case "$(uname -m)" in x86_64|amd64) echo amd64;; aarch64|arm64) echo arm64;; *) echo amd64;; esac; }
# 只识别 linux/darwin（QNAP/群晖/Linux/macOS）；Windows(msys/mingw)等返回空 → 跳过二进制下载用内置探针
os_lc(){ case "$(uname -s | tr 'A-Z' 'a-z')" in linux*) echo linux;; darwin*) echo darwin;; *) echo "";; esac; }

# 1) 下载 CloudflareSpeedTest（如缺）——非致命：下不到就用内置探针（curl 测 TTFB）
CF="$DIR/CloudflareSpeedTest"
if [ ! -x "$CF" ]; then
  GA=$(arch_ga); OS=$(os_lc)
  if [ -z "$OS" ]; then
    say "当前系统($(uname -s))无对应 CloudflareSpeedTest 发行版——将启用内置探针（curl 测 TTFB），不影响使用"
  else
  # 取最新版本号：api.github.com 失败时回退 kkgithub 镜像 API
  VER=$(curl -fsSL --connect-timeout 10 --max-time 20 https://api.github.com/repos/XIU2/CloudflareSpeedTest/releases/latest 2>/dev/null | grep -m1 '"tag_name"' | sed -E 's/.*"v?([0-9][^"]*)".*/\1/')
  if [ -z "${VER:-}" ]; then
    VER=$(curl -fsSL --connect-timeout 10 --max-time 20 https://api.kkgithub.com/repos/XIU2/CloudflareSpeedTest/releases/latest 2>/dev/null | grep -m1 '"tag_name"' | sed -E 's/.*"v?([0-9][^"]*)".*/\1/')
  fi
  if [ -n "${VER:-}" ]; then
    REL="https://github.com/XIU2/CloudflareSpeedTest/releases/download/v${VER}"
    ok=0
    # 新版资产名 cfst_*（v2.3+），旧版 CloudflareSpeedTest_*，依次尝试
    for NAME in "cfst_${VER}_${OS}_${GA}.tar.gz" "CloudflareSpeedTest_${VER}_${OS}_${GA}.tar.gz"; do
      for u in "$REL/$NAME" "https://ghfast.top/$REL/$NAME" "https://gh-proxy.com/$REL/$NAME" "https://ghproxy.net/$REL/$NAME"; do
        say "尝试下载: $u"
        rm -f "$DIR/cst.tar.gz"
        if curl -fL --connect-timeout 10 --max-time 300 "$u" -o "$DIR/cst.tar.gz" 2>/dev/null && tar -tzf "$DIR/cst.tar.gz" >/dev/null 2>&1; then
          if tar -xzf "$DIR/cst.tar.gz" -C "$DIR" 2>/dev/null && [ -f "$CF" ]; then
            chmod +x "$CF"; ok=1; rm -f "$DIR/cst.tar.gz"; break 2
          fi
          # 有些版本解压在子目录里，捞一下
          find "$DIR" -maxdepth 2 -type f -name CloudflareSpeedTest 2>/dev/null | head -1 | while read -r bf; do
            [ -n "$bf" ] && mv -f "$bf" "$CF" 2>/dev/null
          done
          if [ -f "$CF" ]; then chmod +x "$CF"; ok=1; rm -f "$DIR/cst.tar.gz"; break 2; fi
        fi
      done
    done
    if [ "$ok" != "1" ]; then
      rm -f "$DIR/cst.tar.gz"
      say "CloudflareSpeedTest 下载失败（GitHub release 在国内常被 502/重置）——不影响使用"
      say "将自动启用内置探针（curl 测 TTFB 选最快 IP，零外部二进制）"
    fi
  else say "取不到 CloudflareSpeedTest 版本号（GitHub API 限流?）——将启用内置探针，不影响使用"; fi
  fi
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

# 5) 注册全局命令（符号链接进 PATH 目录，之后任何目录直接打 cf-hosts）
CMD_OK=""
for bindir in ${BIN_DIRS:-/usr/local/bin /usr/bin /bin}; do
  [ -d "$bindir" ] && [ -w "$bindir" ] || continue
  rm -f "$bindir/cf-hosts" 2>/dev/null
  if ln -sf "$DIR/cf-hosts.sh" "$bindir/cf-hosts" 2>/dev/null && { [ -L "$bindir/cf-hosts" ] || [ -s "$bindir/cf-hosts" ]; }; then
    CMD_OK="$bindir/cf-hosts"; break
  fi
  rm -f "$bindir/cf-hosts" 2>/dev/null   # ln 失败可能留下垃圾文件，清掉再试下一个目录
done
if [ -n "$CMD_OK" ]; then
  say "已注册全局命令: $CMD_OK（任何目录直接: cf-hosts update / cf-hosts domains add ...）"
else
  say "未能写入 /usr/local/bin（需要 root）。手动注册: ln -sf $DIR/cf-hosts.sh /usr/local/bin/cf-hosts"
  say "或加 alias: echo \"alias cf-hosts='bash $DIR/cf-hosts.sh'\" >> ~/.bashrc"
fi

LANIP=$(hostname -I 2>/dev/null | awk '{print $1}')
say "完成 ✅  安装目录: $DIR"
if [ -x "$DIR/CloudflareSpeedTest" ]; then
  say "测速方式: CloudflareSpeedTest 二进制"
else
  say "测速方式: 内置探针（curl 测 TTFB，零外部二进制；想要完整测速可手动放 CloudflareSpeedTest 到 $DIR）"
fi
say "加站点 : cf-hosts domains add tracker.你的域名.com"
say "看状态 : cf-hosts status"
say "改频率 : cf-hosts interval 30"
say "日志   : $DIR/cf-hosts.log"
[ -n "${LANIP:-}" ] && say "本机IP: $LANIP（仅供参考）"
