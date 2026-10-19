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
say "环境: $(uname -s 2>/dev/null) / shell: $(bash --version 2>/dev/null | head -n 1)"
arch_ga(){ case "$(uname -m)" in x86_64|amd64) echo amd64;; aarch64|arm64) echo arm64;; *) echo amd64;; esac; }
# 只识别 linux/darwin（QNAP/群晖/Linux/macOS）；Windows(msys/mingw)等返回空 → 跳过二进制下载
os_lc(){ case "$(uname -s | tr 'A-Z' 'a-z')" in linux*) echo linux;; darwin*) echo darwin;; *) echo "";; esac; }

# 1) 下载 CloudflareSpeedTest（如缺）——优选的核心依赖
#    注意：资产文件名一律从 releases API 读取，绝不手拼（作者改过命名规则，
#    旧教程里的 CloudflareSpeedTest_<版本>_linux_amd64.tar.gz 早已是 404）
#    解压后 ip.txt / ipv6.txt 要保留在目录里：cfst 靠 -f 读取 IP 段，删了会报 open ip.txt
CFST=""
if   [ -f "$DIR/cfst" ];                then CFST="$DIR/cfst"
elif [ -f "$DIR/CloudflareSpeedTest" ]; then CFST="$DIR/CloudflareSpeedTest"
elif [ -f "$DIR/cf-hosts.conf" ]; then
  # 已装过但二进制在别处：沿用配置里的路径
  _cb=$(sed -n 's/^CF_BIN="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$DIR/cf-hosts.conf" | head -1)
  [ -n "${_cb:-}" ] && CFST="$_cb"
fi

if [ -n "$CFST" ]; then
  say "已存在测速二进制: $CFST"
else
  OS=$(os_lc); GA=$(arch_ga)
  if [ -z "$OS" ]; then
    say "当前系统($(uname -s))无对应 CloudflareSpeedTest 发行版 —— 需手动放 cfst 进去，否则无法优选"
  else
    API_URL="https://api.github.com/repos/XIU2/CloudflareSpeedTest/releases/latest"
    [ -n "${CFST_VERSION:-}" ] && API_URL="https://api.github.com/repos/XIU2/CloudflareSpeedTest/releases/tags/v${CFST_VERSION#v}"
    JSON=$(curl -fsSL --connect-timeout 10 --max-time 30 "$API_URL" 2>/dev/null)
    [ -z "${JSON:-}" ] && JSON=$(curl -fsSL --connect-timeout 10 --max-time 30 "https://api.kkgithub.com/repos/XIU2/CloudflareSpeedTest/releases/latest" 2>/dev/null)
    VER=$(printf '%s\n' "$JSON" | grep -m1 '"tag_name"' | sed -E 's/.*"v?([0-9][^"]*)".*/\1/')
    # 按平台挑资产：过滤 *_old 兼容包 / 扩展名 / 系统 / 架构。
    # 写成单行管道（不用 while+case 复合结构），保证老版本 bash 也能解析
    ASSET=$(printf '%s\n' "$JSON" | grep -o '"browser_download_url": *"[^"]*"' | sed -E 's/.*"browser_download_url": *"([^"]*)".*/\1/' | grep -v '_old\.' | grep -E '\.(tar\.gz|tgz|zip)$' | grep -F "$OS" | grep -F "$GA" | head -n 1)
    if [ -z "${ASSET:-}" ]; then
      say "取不到匹配的资产（GitHub API 不可达或限流）—— 需稍后重试或手动放 cfst 进去"
    else
      say "CloudflareSpeedTest v${VER}，资产 ${ASSET##*/}（文件名取自 releases API）"
      DL="$DIR/.cfst_dl"; ok=0; SRC_OK=""
      # 直连在国内常被 reset/空回复，优先走实测可用的镜像
      for u in "$ASSET" "https://gh-proxy.com/$ASSET" "https://ghfast.top/$ASSET" "https://ghproxy.net/$ASSET" "https://mirror.ghproxy.com/$ASSET"; do
        [ "$ok" = "1" ] && break
        say "尝试: $(printf '%s' "$u" | cut -c1-76)..."
        rm -f "$DL" 2>/dev/null
        curl -fL --connect-timeout 10 --max-time 300 "$u" -o "$DL" 2>/dev/null
        [ -s "$DL" ] || { say "  ✘ 下载失败"; continue; }
        case "$u" in
          *.zip)
            command -v unzip >/dev/null 2>&1 || { say "  ✘ 需要 unzip，系统没有"; continue; }
            unzip -o -q "$DL" -d "$DIR" 2>/dev/null || { say "  ✘ 解压失败"; continue; } ;;
          *)
            tar -xzf "$DL" --strip-components=1 -C "$DIR" 2>/dev/null \
              || tar -xzf "$DL" -C "$DIR" 2>/dev/null \
              || { say "  ✘ 解压失败"; continue; } ;;
        esac
        # 二进制可能在解压出的子目录里，统一提到安装目录根
        _b=$(find "$DIR" -maxdepth 2 -type f \( -name cfst -o -name CloudflareSpeedTest \) 2>/dev/null | head -1)
        if [ -n "${_b:-}" ]; then
          _base="${_b##*/}"
          [ "$_b" != "$DIR/$_base" ] && mv -f "$_b" "$DIR/$_base" 2>/dev/null
          chmod +x "$DIR/$_base" 2>/dev/null
        fi
        # 是否真的可执行由运行时判定（有些 NAS/共享目录 chmod 不生效，
        # 这里不因 -x 失败就丢弃已下载好的二进制，运行时会提示 chmod 后再用）
        if   [ -f "$DIR/cfst" ];                then CFST="$DIR/cfst"; ok=1
        elif [ -f "$DIR/CloudflareSpeedTest" ]; then CFST="$DIR/CloudflareSpeedTest"; ok=1
        else say "  ✘ 包内没找到可执行文件"; fi
        rm -f "$DL" 2>/dev/null
      done
      if [ "$ok" = "1" ]; then
        if [ -x "$CFST" ]; then
          say "✔ 测速二进制就位: $CFST"
        else
          say "⚠ 已放置 $CFST，但该目录无法设置执行位（只读/受限），请手动 chmod +x 后使用"
        fi
      else
        say "所有下载源均失败（GitHub release 在国内常被重置/502）—— 需稍后重跑，或手动下载 cfst 放进本目录"
      fi
    fi
  fi
fi

# 2) 生成配置（缺失才建）；已存在则把 CF_BIN 同步到真实二进制路径
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
CF_BIN="${CFST:-$DIR/CloudflareSpeedTest}"
EOF
  say "已生成 cf-hosts.conf"
elif [ -n "$CFST" ]; then
  awk -v v="$CFST" '{ if ($0 ~ /^CF_BIN=/) print "CF_BIN=\""v"\""; else print }' \
    "$DIR/cf-hosts.conf" > "$DIR/cf-hosts.conf.tmp" \
    && mv "$DIR/cf-hosts.conf.tmp" "$DIR/cf-hosts.conf" \
    && say "已同步配置里的 CF_BIN -> $CFST"
fi

# 3) 注册 cron 定时（开机 + 每 N 分钟）
bash "$DIR/cf-hosts.sh" refresh || true

# 4) 立即跑一次
say "立即执行一次优选 ..."
bash "$DIR/cf-hosts.sh" update || true

# 5) 注册全局命令（自动选目录：root→/usr/local/bin，普通用户→~/.local/bin，均无权限则 alias）
LINK_OUT=$(bash "$DIR/cf-hosts.sh" link 2>&1)
printf '%s\n' "$LINK_OUT"

LANIP=$(hostname -I 2>/dev/null | awk '{print $1}')
say "完成 ✅  安装目录: $DIR"
if [ -n "${CFST:-}" ] && [ -x "$CFST" ]; then
  say "测速方式: CloudflareSpeedTest 二进制 -> $CFST"
  [ -f "$DIR/ip.txt" ] || say "⚠ 缺 ip.txt（cfst 的 IP 段文件），优选会失败；重跑本脚本可补回"
else
  say "⚠ 缺少测速二进制：优选无法工作。手动把 cfst（含 ip.txt）放进 $DIR，或重新下载（下载源常被墙，可多试几次）"
fi
if [ "$(id -u 2>/dev/null)" != "0" ]; then
  say "权限提示: 你不是 root。写 /etc/hosts 会自动尝试 sudo（免密才行）；否则请在 QTS「控制台→系统→任务计划」里添加定时（那里以 root 运行），或手动执行 sudo bash $DIR/cf-hosts.sh update"
fi
case "$LINK_OUT" in
  *"已注册全局命令"*) : ;;   # 成功：按 link 自己的提示操作即可
  *) say "提示: 想装到 /usr/local/bin 给所有用户用，可 sudo 重跑一次: sudo bash $DIR/install.sh" ;;
esac
say "加站点 : cf-hosts domains add tracker.你的域名.com"
say "看状态 : cf-hosts status"
say "改频率 : cf-hosts interval 30"
say "日志   : $DIR/cf-hosts.log"
[ -n "${LANIP:-}" ] && say "本机IP: $LANIP（仅供参考）"
