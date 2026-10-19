# cf-hosts — 自动优选 Cloudflare IP 写入 hosts（纯 shell，零运行时依赖）

解决 PT tracker / Cloudflare 站点在**国内宽带（尤其移动）**下"could not respond / 连不上"：
定时运行 [CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest)（独立二进制，无需运行时）选出当前**最快最通**的 Cloudflare IP，自动写进系统 `hosts` 的托管区段（`# >>> cf-hosts BEGIN >>> ... END`）。Transmission（host 模式）等直接受益。

- **纯 shell**，不装 Node/任何运行时；QNAP / 群晖 / Linux / macOS 自带 bash 即可
- **一行命令远端安装**（自动下载项目 + 测速工具 + 注册 cron + 立即跑一次）
- **命令行**随时调整；hosts 只动托管区段，不破坏原有内容，重启不丢
- 卸载一键清理

## 一键安装（远端，推荐）

**国内网络（raw.githubusercontent.com 常被 TLS 重置，用 jsdelivr 镜像）：**

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/joseplin0/cf-hosts@main/install.sh \
  | REPO_RAW=https://cdn.jsdelivr.net/gh/joseplin0/cf-hosts@main bash
```

**网络环境好时（官方 raw 源）：**

```bash
curl -fsSL https://raw.githubusercontent.com/joseplin0/cf-hosts/main/install.sh | bash
```

- 安装脚本内置多镜像自动回退（jsdelivr / ghfast.top），CloudflareSpeedTest 二进制下载也有 GitHub 直连 + ghproxy 镜像链，哪条通用哪条。
- 会自动判断安装目录：QNAP→`/share/Container/cf-hosts`，其他→`~/.cf-hosts`（可用 `CF_INSTALL_DIR=/your/dir` 覆盖）。
- 装完按提示加站点、看状态即可。
- ⚠️ jsdelivr 对 `@main` 分支缓存最长约 12 小时：刚推送的新版本若装到旧文件，等一会儿或用 `@commit` 短哈希固定版本。

## 命令行

```bash
bash cf-hosts.sh domains add tracker.a.com tracker.b.com   # 添加站点
bash cf-hosts.sh domains remove tracker.a.com              # 删除
bash cf-hosts.sh domains                                   # 查看
bash cf-hosts.sh interval 30                               # 每 30 分钟（同步改 cron）
bash cf-hosts.sh auto off                                  # 关自动（on 开）
bash cf-hosts.sh update                                    # 立即优选一次
bash cf-hosts.sh ip                                        # 当前优选 IP
bash cf-hosts.sh status                                    # 状态总览
bash cf-hosts.sh refresh                                   # 重写 cron 定时
bash cf-hosts.sh clean                                     # 清理 hosts 托管区段
bash cf-hosts.sh help                                      # 帮助
```

## 配置 `cf-hosts.conf`（安装时生成，可手改；样例见 `cf-hosts.conf.example`）

| 键 | 说明 | 默认 |
|---|---|---|
| `INTERVAL` | 自动优选间隔（分钟） | 60 |
| `AUTO` | 是否自动（on/off） | on |
| `USE_IPV6` | 优选 IPv6 还是 IPv4（on/off） | off |
| `MAX_MS` | 延迟上限(ms) | 200 |
| `MAX_LOSS` | 丢包率上限(%) | 0 |
| `DOMAINS` | PT tracker 域名（空格分隔） | 空 |
| `HOSTS` | hosts 路径 | `/etc/hosts` |
| `CF_BIN` | CloudflareSpeedTest 路径 | 程序目录下 |

> 只加**走 Cloudflare** 的 tracker：`nslookup 域名`，IP 在 `104.16-31 / 172.64-72 / 162.158 / 188.114` 等段才算；非 Cloudflare 域名加进来无效。
> 数据目录默认为程序所在目录，可用环境变量 `CF_HOME` 改到别处。

## 推送到 GitHub（自己部署时）

仓库已上线：**https://github.com/joseplin0/cf-hosts**（推送后 raw / jsdelivr 地址即指向 `main` 分支）。
本地改完提交并推送：

```bash
cd cf-hosts
git add -A && git commit -m "update" && git push
```

## QNAP 说明

- 定时走 **crontab**：`@reboot` 开机跑一次 + `*/INTERVAL` 跑；请确认 **控制台 → 系统 → 任务计划 / Cron 已启用**。
- 想完全用界面：控制台 → 系统 → 任务计划，加两条指向 `bash <安装目录>/cf-hosts.sh update`（开机一次 + 每小时）。
- 改 `/etc/hosts` 需要 root；QNAP 计划任务默认以 admin(root) 运行，OK。
- Transmission 容器是 **host 模式**，直接用宿主机 hosts，无需任何容器改动。

## 卸载

```bash
bash uninstall.sh
```
取消 cron、清理 hosts 托管区段；程序文件保留，确认后手动删目录即可。

## 排障

- 日志：`cf-hosts.log`（安装目录）；`result.csv` 是最近一次测速明细。
- `curl: (35) OpenSSL SSL_connect: Connection reset by peer ... raw.githubusercontent.com` = 国内宽带对该域名 TLS 重置，改用 README 顶部的 **jsdelivr 镜像命令**安装。
- 「找不到可执行的 CloudflareSpeedTest」= 手动下载对应平台版放进安装目录并 `chmod +x`（GitHub: XIU2/CloudflareSpeedTest；国内可用 ghfast.top 等镜像）。
- 优选为空：把 `MAX_MS` 调大（如 400）或 `MAX_LOSS` 调高（如 10）。
- 换测速端口/线程等高级参数，可直接改 `cf-hosts.sh` 里 `best_ip()` 的 `-n 200 -tl -tll`。
