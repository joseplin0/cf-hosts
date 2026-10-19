# cf-hosts — 自动优选 Cloudflare IP 写入 hosts（纯 shell，零运行时依赖）

解决 PT tracker / Cloudflare 站点在**国内宽带（尤其移动）**下"could not respond / 连不上"：
定时运行 [CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest)（独立二进制，无需运行时）选出当前**最快最通**的 Cloudflare IP，自动写进系统 `hosts` 的托管区段（`# >>> cf-hosts BEGIN >>> ... END`）。Transmission（host 模式）等直接受益。

- **纯 shell**，不装 Node/任何运行时；QNAP / 群晖 / Linux / macOS 自带 bash 即可
- **一行命令远端安装**（自动下载项目 + 测速工具 + 注册 cron + 立即跑一次）
- **命令行**随时调整；hosts 只动托管区段，不破坏原有内容，重启不丢
- **命令注册自动降级**：非 root 也能直接打 `cf-hosts`（装不进系统目录就落 `~/.local/bin` 并自动加 PATH），最后兜底写 alias
- 卸载一键清理

## 一键安装（远端，推荐）

**国内移动/电信宽带（raw.githubusercontent.com 和 jsdelivr 都是 Fastly，会被 TLS 重置）——用 codeload 官方 tarball：**

```bash
D=$(mktemp -d) && curl -fsSL https://codeload.github.com/joseplin0/cf-hosts/tar.gz/refs/heads/main \
  | tar -xz -C "$D" && bash "$D"/cf-hosts-*/install.sh
```

**或者 git clone（github.com 可达时最快）：**

```bash
git clone --depth 1 https://github.com/joseplin0/cf-hosts.git /share/Container/cf-hosts \
  && bash /share/Container/cf-hosts/install.sh
```

**网络环境好时（raw / jsdelivr 源的 curl|bash）：**

```bash
curl -fsSL https://raw.githubusercontent.com/joseplin0/cf-hosts/main/install.sh | bash
curl -fsSL https://cdn.jsdelivr.net/gh/joseplin0/cf-hosts@main/install.sh \
  | REPO_RAW=https://cdn.jsdelivr.net/gh/joseplin0/cf-hosts@main bash
```

- 安装脚本会自动选择可达路径：**本地已有完整项目 → 直接复制；codeload tarball → 一次拿全量；都不行 → 逐文件镜像（raw/jsdelivr/ghfast）**。
- 自动判断安装目录：QNAP→`/share/Container/cf-hosts`，其他→`~/.cf-hosts`（可用 `CF_INSTALL_DIR=/your/dir` 覆盖）。
- 装完自动注册全局命令 `cf-hosts` 并立即优选一次。root → `/usr/local/bin`；**非 root 自动落到 `~/.local/bin`（或 `~/bin`），并写进 `~/.bashrc`/`~/.profile` 的 PATH，无需 sudo**。

## 测速方式：CloudflareSpeedTest（cfst）二进制

| 项 | 说明 |
|---|---|
| 作用 | 完整测速（延迟+丢包+下载速度），选出当前最快最通的 Cloudflare IP |
| 安装 | installer 自动下载；网络不通时手动把 `cfst` 放进安装目录 |
| 配套文件 | 压缩包里的 **`ip.txt` / `ipv6.txt` 必须保留**（cfst 靠 `-f` 读 IP 段，删了会报 `open ip.txt: no such file or directory`）；脚本会自动用 `-f <安装目录>/ip.txt` 调用，不依赖当前工作目录 |
| 版本注意 | v2.3+ **已移除 `-ipv4` / `-ipv6` 参数**（传了会被当未知参数、只打印帮助然后退出）。IPv6 改用 `-f ipv6.txt`。脚本已按新版参数调用 |
| 缺失时 | 不做降级，直接报错并在日志里列出原因（缺 ip.txt / 阈值太严 / 架构不匹配） |

- 资产文件名一律从 GitHub releases API 的 `browser_download_url` 读取（**不手拼**，作者改过命名），按 OS/架构匹配、自动排除 `*_old` 兼容包。新版包名 `cfst_linux_amd64.tar.gz`，解压后可执行文件叫 **`cfst`**（旧版才叫 `CloudflareSpeedTest`），两种都认。
- 下载源顺序：GitHub 直连 → `gh-proxy.com` → `ghfast.top` → `ghproxy.net` → `mirror.ghproxy.com`，国内宽带逐个试到能通为止。

## 权限：写 `/etc/hosts` 需要 root

- 脚本写 hosts 时**自动尝试**：直接写 → 失败则 `sudo tee` 兜底（免密 sudo 才行）。
- 都失败会明确报「无写权限，请执行 `sudo bash <安装目录>/cf-hosts.sh update`」。
- **定时任务的正确做法**：QNAP/群晖到「控制台 → 系统 → 任务计划」添加（那里以 **root** 运行，权限问题自然消失）；命令填 `bash <安装目录>/cf-hosts.sh update`，开机一次 + 每 N 分钟。crontab 对非 root 用户通常写不进去，属正常。

## 命令行

安装后自动注册全局命令 `cf-hosts`（符号链接进 `/usr/local/bin` 等 PATH 目录），**任何目录直接打**：

```bash
cf-hosts domains add tracker.a.com tracker.b.com   # 添加站点
cf-hosts domains remove tracker.a.com              # 删除
cf-hosts domains                                   # 查看
cf-hosts interval 30                               # 每 30 分钟（同步改 cron）
cf-hosts auto off                                  # 关自动（on 开）
cf-hosts update                                    # 立即优选一次
cf-hosts ip                                        # 当前优选 IP
cf-hosts status                                    # 状态总览
cf-hosts refresh                                   # 重写 cron 定时
cf-hosts clean                                     # 清理 hosts 托管区段
cf-hosts link                                      # （重新）注册全局命令（随时重跑）
cf-hosts unlink                                    # 注销全局命令
cf-hosts help                                      # 帮助
```

### 命令是怎么注册的（非 root 也不用管）

`cf-hosts link` 按顺序找地方放软链，**哪个能用用哪个**：

1. root → `/usr/local/bin` → `/usr/bin` → `/bin`
2. 普通用户 → `~/.local/bin` → `~/bin` → 系统目录
3. 全不可写、但有免密 `sudo` → 用 sudo 装进 `/usr/local/bin`（`SUDO_BIN_DIR` 可改目标）
4. 还是不行 → 往 `~/.bashrc`/`~/.profile` 写一行 alias（带 `# >>> cf-hosts >>>` 标记，卸载时会被清掉）

注册到的目录如果不在 `$PATH` 里，会自动追加一行 `export PATH=...` 到 shell 配置，重开终端（或 `source ~/.profile`）即生效。`cf-hosts status` 会显示当前是否已注册。

> QNAP：SSH 登录的 admin 可以直接 `bash <安装目录>/cf-hosts.sh link`；若想装到系统目录给所有用户用，用 `sudo bash <安装目录>/install.sh` 重跑一次即可（QTS 支持 sudo）。
> 任何时候都能绕过注册，直接全路径运行：`bash /share/Container/cf-hosts/cf-hosts.sh <命令>`。

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
取消 cron、注销全局命令 `cf-hosts`（含 `~/.local/bin` 里的，并清掉 shell 配置中带 `# >>> cf-hosts >>>` 的 PATH/alias 行）、清理 hosts 托管区段；程序文件保留，确认后手动删目录即可。

## 排障

- 日志：`cf-hosts.log`（安装目录）；`result.csv` 是最近一次测速明细。
- `curl: (35) OpenSSL SSL_connect: Connection reset by peer` → raw.githubusercontent.com / cdn.jsdelivr.net（均 Fastly）在你这条宽带被重置，**改用 README 顶部的 codeload tarball 安装命令**（ghfast/gh-proxy 等镜像也常挂）。
- `ln: /usr/local/bin/cf-hosts: Permission denied` = 登录用户不是 root，**不需要 sudo**：安装脚本会自动改用 `~/.local/bin`（或 `~/bin`）并写进 shell 配置的 PATH。重开终端或 `source ~/.profile` 后即可直接打 `cf-hosts`；也可随时手动 `cf-hosts link` 重注册。想在系统目录给所有用户用，再 `sudo bash <安装目录>/install.sh`。
- 「未找到可执行的测速二进制」= 目录里没有 `cfst`。重跑 `install.sh`，或手动下载对应平台版（连同 ip.txt/ipv6.txt）放进安装目录并 `chmod +x`。
- 「cfst 没返回结果」：日志会列出三条常见原因（缺 ip.txt / 阈值太严 / 架构不匹配），按提示处理。先把 `MAX_MS` 调大（如 400）通常就能出结果。
- 换测速端口/线程等高级参数，可直接改 `cf-hosts.sh` 里 `best_ip()` 的 `-n 200 -tl -tll`。
