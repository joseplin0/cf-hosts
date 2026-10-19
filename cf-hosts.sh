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
  local ip; ip=$(best_ip)
  if [ -z "$ip" ]; then log "更新失败：未获取到优选 IP（检查 CF_BIN/网络，或调大 MAX_MS/MAX_LOSS）"; return 1; fi
  if ! update_hosts "$ip"; then log "写入 $HOSTS 失败（文件不存在或无权限）"; return 1; fi
  echo "$ip" > "$STATE"
  log "优选 $fam = $ip 已写入 $HOSTS（域名：${DOMAINS:-无}）"
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
    echo "  测速   : $CF_BIN"
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
