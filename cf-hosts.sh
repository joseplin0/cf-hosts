#!/usr/bin/env bash
# cf-hosts — 自动优选 Cloudflare IP 写入 hosts 托管区段（纯 shell，零运行时依赖）
# 解决 PT tracker / Cloudflare 站点在国内宽带（尤其移动）下连不上。
set -u
# 解析自身真实路径（支持通过符号链接调用，如 /usr/local/bin/cf-hosts → 安装目录/cf-hosts.sh）
# readlink 对非符号链接会返回失败，循环自然结束；最多解析 20 层防成环
SELF="$0"
_ln=0
while [ "$_ln" -lt 20 ]; do
  _t="$(readlink "$SELF" 2>/dev/null)" || break
  [ -z "$_t" ] && break
  case "$_t" in
    /*) SELF="$_t";;
    *)  SELF="$(dirname "$SELF")/$_t";;
  esac
  _ln=$((_ln+1))
done
CF_HOME="${CF_HOME:-$(cd -P "$(dirname "$SELF")" 2>/dev/null && pwd)}"
CONF="$CF_HOME/cf-hosts.conf"
STATE="$CF_HOME/state"
LOG="$CF_HOME/cf-hosts.log"
BEGIN="# >>> cf-hosts BEGIN >>>"
END="# <<< cf-hosts END <<<"
# 兼容旧版误写的 END 标记（# >>> cf-hosts END >>>）
END_RE="cf-hosts END"

# ---- 默认值（被 cf-hosts.conf 覆盖）----
PORT=9876
INTERVAL=60
AUTO=on
USE_IPV6=off
MAX_MS=200
MAX_LOSS=0
HOSTS="/etc/hosts"
DOMAINS=""
CF_BIN="$CF_HOME/CloudflareSpeedTest"
[ -f "$CONF" ] && . "$CONF"
# 相对路径统一相对 CF_HOME 解析（cron 的 cwd 是 $HOME，相对路径会找不到）
case "$CF_BIN" in /*) ;; *) CF_BIN="$CF_HOME/$CF_BIN";; esac
case "$HOSTS"  in /*) ;; *) HOSTS="$CF_HOME/$HOSTS";;  esac

log(){ echo "[$(date '+%F %T')] $*" | tee -a "$LOG" >&2; }

save_conf(){
  cat > "$CONF" <<EOF
# cf-hosts 配置（改完对 update / 定时立即生效）
PORT=$PORT
INTERVAL=$INTERVAL
AUTO=$AUTO
USE_IPV6=$USE_IPV6
MAX_MS=$MAX_MS
MAX_LOSS=$MAX_LOSS
HOSTS="$HOSTS"
DOMAINS="$DOMAINS"
CF_BIN="$CF_BIN"
EOF
}

best_ip(){
  [ -x "$CF_BIN" ] || { log "找不到可执行的 CloudflareSpeedTest: $CF_BIN"; echo ""; return; }
  local out="$CF_HOME/result.csv" ip="" raw="$CF_HOME/cst_run.log"
  if [ "$USE_IPV6" = "on" ]; then
    "$CF_BIN" -ipv6 -tl "$MAX_MS" -tll "$MAX_LOSS" -n 200 -o "$out" >"$raw" 2>&1
    ip=$(grep -oE '^[0-9a-fA-F]{0,4}:[0-9a-fA-F:]+' "$out" 2>/dev/null | head -1)
  else
    "$CF_BIN" -ipv4 -tl "$MAX_MS" -tll "$MAX_LOSS" -n 200 -o "$out" >"$raw" 2>&1
    ip=$(grep -oE '^[0-9]{1,3}(\.[0-9]{1,3}){3}' "$out" 2>/dev/null | head -1)
  fi
  [ -z "$ip" ] && [ -s "$raw" ] && log "CloudflareSpeedTest 输出: $(tail -2 "$raw" | tr '\n' ' ')"
  echo "$ip"
}

# ---- 内置探针：没有 CloudflareSpeedTest 二进制时的降级方案 ----
# 原理与 cfst 相同：对候选 Cloudflare IP 逐个发起带正确 SNI 的 HTTPS 请求，测 TTFB，取最快。
# 只用 curl，零外部二进制；国内宽带下 GitHub release 下载常被 502/重置，此方案保证可用。
CF_PROBE_HOST="${CF_PROBE_HOST:-cloudflare.com}"
CF_PROBE_PATH="${CF_PROBE_PATH:-/cdn-cgi/trace}"
CF_PROBE_PAR="${CF_PROBE_PAR:-24}"
builtin_candidates(){
  # Cloudflare Anycast 主要网段采样（与 cfst 默认测试段一致的代表性 IP）
  local p
  for p in 104.16 104.17 104.18 104.19 104.20 104.21 104.22 104.23 104.24 104.25 104.26 104.27 104.28 104.29 104.30 104.31 \
           172.64 172.65 172.66 172.67 172.68 172.69 172.70 172.71 \
           162.158 162.159 \
           188.114.96 188.114.97 188.114.98 188.114.99 188.114.104 188.114.108 188.114.111 \
           198.41.192 198.41.193 198.41.194 198.41.195 198.41.200 198.41.201 198.41.202 198.41.203 \
           141.101.64 141.101.65 141.101.66 141.101.67 141.101.68 141.101.69 141.101.70 141.101.71 \
           108.162.192 108.162.193 108.162.194 108.162.195 108.162.196 108.162.200 108.162.204 108.162.208 108.162.220 108.162.224 108.162.228 108.162.232 108.162.236 108.162.240 108.162.244 108.162.248 108.162.252; do
    echo "$p.1" "$p.128"
  done
}
best_ip_builtin(){
  command -v curl >/dev/null 2>&1 || { log "内置探针需要 curl，但系统没有"; echo ""; return; }
  local out ip t ms best="" bestms=999999 i=0
  # 并行探测：后台子shell直接输出 "ttfb ip"（单行 echo 原子写，由命令替换统一收集，无需临时文件）
  out=$(
    for ip in $(builtin_candidates); do
      (
        t=$(curl -k -s -o /dev/null --connect-timeout 2 --max-time 4 \
          -w '%{time_starttransfer}' \
          --resolve "$CF_PROBE_HOST:443:$ip" "https://$CF_PROBE_HOST$CF_PROBE_PATH" 2>/dev/null)
        case "$t" in ''|0.000000) ;; *) echo "$t $ip";; esac
      ) &
      i=$((i+1))
      [ $((i % CF_PROBE_PAR)) -eq 0 ] && wait
    done
    wait
  )
  while read -r t ip; do
    case "$t" in ''|0.000000) continue;; esac
    ms=$(awk -v t="$t" 'BEGIN{printf "%d", t*1000}' 2>/dev/null)
    case "$ms" in ''|*[!0-9]*) continue;; esac
    if [ "$ms" -lt "$bestms" ]; then bestms="$ms"; best="$ip"; fi
  done <<< "$out"
  [ -n "$best" ] || { log "内置探针：所有候选 IP 均不可达"; echo ""; return; }
  if [ "$bestms" -gt "$MAX_MS" ]; then
    log "内置探针：最快 $best = ${bestms}ms 超过 MAX_MS=${MAX_MS}，仍采用（聊胜于无）"
  fi
  echo "$best"
}

update_hosts(){ # $1=ip
  awk -v b="$BEGIN" -v e="$END" -v ere="$END_RE" -v ip="$1" -v doms="$DOMAINS" '
    $0==b{ if(!done){ print b; n=split(doms,a," "); for(i=1;i<=n;i++) if(a[i]!="") print ip"\t"a[i]; print e; done=1 } skip=1; next }
    skip && $0 ~ ere{skip=0;next}
    !skip{print}
    END{ if(!done){ print b; n=split(doms,a," "); for(i=1;i<=n;i++) if(a[i]!="") print ip"\t"a[i]; print e } }
  ' "$HOSTS" > "$HOSTS.cfhosts.tmp" && mv "$HOSTS.cfhosts.tmp" "$HOSTS"
}

clean_hosts(){
  awk -v b="$BEGIN" -v ere="$END_RE" '$0==b{skip=1;next} skip && $0 ~ ere{skip=0;next} !skip{print}' \
    "$HOSTS" > "$HOSTS.cfhosts.tmp" && mv "$HOSTS.cfhosts.tmp" "$HOSTS"
}

cmd_update(){
  local fam=IPv4; [ "$USE_IPV6" = "on" ] && fam=IPv6
  local ip="" method=""
  if [ -x "$CF_BIN" ]; then
    ip=$(best_ip); method="CloudflareSpeedTest"
  else
    log "未安装 CloudflareSpeedTest，改用内置探针（curl 测 TTFB，无需外部二进制）..."
    ip=$(best_ip_builtin); method="内置探针"
  fi
  if [ -z "$ip" ]; then log "更新失败：未获取到优选 IP（检查网络，或调大 MAX_MS/MAX_LOSS）"; return 1; fi
  if ! update_hosts "$ip"; then log "写入 $HOSTS 失败（文件不存在或无权限）"; return 1; fi
  echo "$ip" > "$STATE"
  log "优选 $fam = $ip 已写入 $HOSTS（方式：$method，域名：${DOMAINS:-无}）"
}

refresh_cron(){
  command -v crontab >/dev/null 2>&1 || { log "无 crontab，请用系统任务计划手动加定时"; return 0; }
  local keep; keep=$(crontab -l 2>/dev/null | grep -v 'cf-hosts')
  {
    echo "$keep"
    echo "# cf-hosts"
    [ "$AUTO" = "on" ] || return 0
    echo "@reboot \"$CF_HOME/cf-hosts.sh\" update >> \"$LOG\" 2>&1"
    if [ "$INTERVAL" -ge 1 ] 2>/dev/null && [ "$INTERVAL" -le 60 ]; then
      echo "*/$INTERVAL * * * * \"$CF_HOME/cf-hosts.sh\" update >> \"$LOG\" 2>&1"
    else
      echo "0 * * * * \"$CF_HOME/cf-hosts.sh\" update >> \"$LOG\" 2>&1"
    fi
  } | crontab - 2>/dev/null && log "已更新 cron 定时（每 $INTERVAL 分钟 + 开机）" || log "写入 crontab 失败"
}

usage(){
  cat <<EOF
cf-hosts（纯 shell，零依赖）
用法: cf-hosts <命令> [参数]        # 安装后任何目录直接打 cf-hosts
      bash <安装目录>/cf-hosts.sh <命令> [参数]   # 或全路径运行
  update                 立即优选一次并写入 hosts
  ip                     当前优选 IP
  status                 状态总览
  domains                列出 tracker 域名
  domains add <d...>     添加域名
  domains remove <d...>  删除域名
  interval <分钟>        设置频率（如 30；0=仅开机跑）
  auto on|off            开关自动更新
  refresh                重写 cron 定时
  clean                  清理 hosts 里的 cf-hosts 托管区段
  help                   显示帮助
EOF
}

case "${1:-}" in
  update)  cmd_update ;;
  ip)      cat "$STATE" 2>/dev/null || echo "—" ;;
  status)
    echo "cf-hosts 状态"
    echo "  当前IP : $(cat "$STATE" 2>/dev/null || echo '—')"
    echo "  域名   : ${DOMAINS:-（空）}"
    echo "  频率   : 每 ${INTERVAL} 分钟（auto=$AUTO, ipv6=$USE_IPV6, 延迟<${MAX_MS}ms, 丢包<${MAX_LOSS}%）"
    echo "  hosts  : $HOSTS"
    if [ -x "$CF_BIN" ]; then echo "  测速   : $CF_BIN"
    else echo "  测速   : 内置探针（curl，未安装 CloudflareSpeedTest 时自动启用）"; fi
    echo "  日志   : $LOG" ;;
  domains)
    action="${2:-list}"
    case "$action" in
      add)    shift 2; for d in "$@"; do case " $DOMAINS " in *" $d "*) ;; *) DOMAINS="${DOMAINS:+$DOMAINS }$d";; esac; done; save_conf; echo "${DOMAINS:-（空）}" ;;
      remove) shift 2; for d in "$@"; do DOMAINS=$(echo " $DOMAINS " | sed "s/ $d / /g" | xargs); done; save_conf; echo "${DOMAINS:-（空）}" ;;
      *)      echo "${DOMAINS:-（空）}" ;;
    esac ;;
  interval) INTERVAL="${2:-60}"; save_conf; refresh_cron; echo "interval=$INTERVAL 分钟" ;;
  auto)     AUTO="${2:-on}"; save_conf; refresh_cron; echo "auto=$AUTO" ;;
  refresh)  refresh_cron ;;
  clean)    clean_hosts; echo "已清理 $HOSTS 中的 cf-hosts 托管区段" ;;
  help|"")  usage ;;
  *)        echo "未知命令: $1"; usage ;;
esac
