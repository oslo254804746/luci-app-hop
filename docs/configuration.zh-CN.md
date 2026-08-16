# luci-app-hop 配置指南

`luci-app-hop` 在 OpenWrt 上提供两部分能力：

- 原生 LuCI 服务页负责启停 Hop、选择核心版本和下载源；
- 内置 Vue 管理面板负责资产、目标凭据、入口公钥和会话。

Hop 核心仍然是按 CPU 架构单独下载的静态程序，不会编译进 LuCI 包。

## 文件与端口

| 路径或端口 | 用途 |
|---|---|
| `/etc/config/hop` | UCI 服务、版本和下载源设置 |
| `/etc/hop/config.toml` | Hop 0.2.4 启动配置和网页管理 Token |
| `/etc/hop/core/hop-server` | 下载并校验后的核心程序 |
| `/var/lib/hop` | SQLite、加密主密钥和 SSH Host Key |
| `0.0.0.0:2222` | 默认入口 SSH 监听 |
| `127.0.0.1:8083` | 仅供 LuCI 代理访问的 Control API |

Control API 不监听 LAN 地址。浏览器只访问当前 LuCI Origin 下的受认证代理路径。

## 安装和首次启动

```sh
# OpenWrt 24.10
opkg install luci-app-hop_*.ipk

# 使用 apk 的 OpenWrt
apk add --allow-untrusted luci-app-hop-*.apk
```

然后进入 **Services → Hop → Service Settings**，启用服务并保存，或者执行：

```sh
uci set hop.main.enabled='1'
uci commit hop
/etc/init.d/hop enable
/etc/init.d/hop start
```

首次启动会下载与 `uname -m` 匹配的 `x86_64` 或 `aarch64` musl 核心，校验 Release 中的 `SHA256SUMS`，执行 `hop-server --version` 自检，再原子安装。

进入 **Services → Hop → Management Panel**，输入 `/etc/hop/config.toml` 中的网页管理 Token。随包 Token 是仅供首次进入的 `change-me`；请立即替换为随机长字符串：

```sh
token=$(head -c 32 /dev/urandom | hexdump -v -e '/1 "%02x"')
sed -i "s/token = \"change-me\"/token = \"$token\"/" /etc/hop/config.toml
chmod 0600 /etc/hop/config.toml
/etc/init.d/hop restart
```

重启后在面板中输入新 Token。Token 只保存在当前页面内存，刷新后需要重新输入。

## UCI 服务设置

默认配置：

```uci
config hop 'main'
        option enabled '0'
        option config_path '/etc/hop/config.toml'
        option auto_download '1'
        option core_version 'v0.2.4'
        option release_base 'https://github.com/oslo254804746/hop-rs/releases'
        option log_stdout '1'
        option log_stderr '1'
```

| 字段 | 默认值 | 含义 |
|---|---|---|
| `enabled` | `0` | 是否由 procd 启动 Hop |
| `config_path` | `/etc/hop/config.toml` | 传给核心的启动配置 |
| `auto_download` | `1` | 核心缺失或固定版本不匹配时自动下载 |
| `core_version` | `v0.2.4` | 固定版本；也可以填写 `latest` |
| `release_base` | 官方 GitHub Releases | 核心与校验文件的发布根地址 |
| `log_stdout` / `log_stderr` | `1` | 把输出交给 procd 日志 |

## GitHub 与加速下载源

LuCI 的 **Core download source** 是可输入自定义值的组合框，预置：

- 官方 GitHub Releases；
- `gh-proxy.net`；
- 任意兼容 GitHub Releases 路径结构的 HTTPS 地址。

命令行切换到 `gh-proxy.net`：

```sh
uci set hop.main.release_base='https://gh-proxy.net/https://github.com/oslo254804746/hop-rs/releases'
uci commit hop
/usr/share/hop/hop-core update
/etc/init.d/hop restart
```

下载器会访问：

```text
<release_base>/latest/download/SHA256SUMS
<release_base>/latest/download/hop-server-linux-<arch>-musl.tar.gz
<release_base>/download/<tag>/SHA256SUMS
```

第三方镜像可以同时替换压缩包和 `SHA256SUMS`，因此 SHA-256 只能检测传输损坏，不能让不可信镜像变可信。默认仍使用 GitHub；选择镜像前请自行确认运营方。

查看或更新核心：

```sh
/usr/share/hop/hop-core status
/usr/share/hop/hop-core update
/etc/init.d/hop restart
```

## Hop 0.2.4 启动配置

随包 `/etc/hop/config.toml`：

```toml
listen = "0.0.0.0:2222"
data_dir = "/var/lib/hop"

[api]
enabled = true
listen = "127.0.0.1:8083"
token = "change-me"
cors_allowlist = []

[ssh]
host_key_type = "ed25519"
banner = "Welcome to Hop"
keepalive_interval = 30
connect_timeout = 10
proxy_policy = "assets_only"

[runtime]
temp_dir = "/tmp/hop"
log_level = "info"
session_retention_days = 30
```

0.2.4 使用顶层 `listen`、`data_dir` 和直接的 `api.token`。旧版 `[server]`、`[database]`、`api.token_file`、`[security]`、`[inventory]` 字段已经不再支持。

## 面板与 API 安全边界

面板文档由 LuCI 登录路由返回，并发送 CSP、`X-Frame-Options: DENY`、`nosniff` 和 `no-referrer`。API 代理同时要求：

1. 有效 LuCI 会话和 `luci-app-hop` ACL；
2. 浏览器内存中的 Hop Bearer Token；
3. 请求方法与路径属于随包白名单。

代理只连接 `127.0.0.1:8083`，拒绝查询串、未知 API、目录穿越、超大请求和非白名单方法。不要把 `api.listen` 改为 `0.0.0.0:8083`；跨机器管理应优先通过 VPN 或单独的 TLS 反向代理。

## 资源归属

在网页或本地 CLI 创建的资源归属为 `local`，可以在面板中编辑。直接写入启动配置的资源归属为 `config`，面板会只读展示，需要修改 `/etc/hop/config.toml` 后重启。

例如在 TOML 中声明一个资产：

```toml
[assets.router]
type = "ssh"
host = "192.168.1.1"
port = 22
display_name = "Main router"
```

对于包含密码、私钥或入口公钥的完整配置，请参考 [Hop 配置参考](https://github.com/oslo254804746/hop-rs/blob/master/docs/configuration.zh-CN.md)。

## 防火墙、备份与排错

`luci-app-hop` 不修改防火墙。LAN 能否访问 `2222` 取决于现有 zone 策略；不建议直接从 WAN 暴露入口。

备份：

```sh
/etc/init.d/hop stop
tar -czf /tmp/hop-backup.tgz /etc/config/hop /etc/hop /var/lib/hop
/etc/init.d/hop start
```

数据库和 `/var/lib/hop/hop.secret` 必须成对恢复，否则无法解密托管凭据。

| 现象 | 检查项 |
|---|---|
| 核心下载失败 | 系统时间、DNS、CA、下载源和 `logread -e hop-core` |
| 面板返回 502 | 服务是否运行、API 是否启用、`127.0.0.1:8083` 是否监听 |
| 面板返回 401 | `/etc/hop/config.toml` 中的 Token 是否一致 |
| 面板返回 403 | LuCI 会话或 `luci-app-hop` ACL 是否有效 |
| 服务无法启动 | 配置是否仍包含旧字段，查看 `logread -e hop` |
| 修改配置后无变化 | 是否重启 Hop；配置归属资源只在启动时应用 |
