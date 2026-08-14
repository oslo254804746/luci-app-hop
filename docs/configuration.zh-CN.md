# luci-app-hop 配置指南

`luci-app-hop` 管理 OpenWrt 上的服务外壳和 Hop 核心下载。它不在 UCI 中保存资产、凭据或 Access Key。

安装后会出现两组配置：

| 文件 | 用途 |
|---|---|
| `/etc/config/hop` | UCI 服务设置，包括启用状态和核心版本 |
| `/etc/hop/config.toml` | Hop 启动配置，包括 SSH 监听、SQLite 路径和资源来源 |

Hop 的运行数据保存在 `/var/lib/hop`，核心二进制安装在 `/etc/hop/core/hop-server`。

## 安装和首次启动

安装构建好的 IPK 或 APK：

```sh
# OpenWrt 24.10
opkg install luci-app-hop_*.ipk

# 使用 apk 的 OpenWrt
apk add --allow-untrusted luci-app-hop-*.apk
```

安装后可以在 LuCI 的 `Services -> Hop` 中配置服务。命令行启用方式：

```sh
uci set hop.main.enabled='1'
uci commit hop
/etc/init.d/hop enable
/etc/init.d/hop start
```

默认 `auto_download` 为 `1`。第一次启用时，如果本地没有可用核心，启动脚本会下载当前架构对应的 Release 文件、校验 `SHA256SUMS`，然后执行 `hop-server --version`。校验通过后才会替换现有核心。

当前自动下载支持 `x86_64`、`amd64`、`aarch64` 和 `arm64` 机器名。其他架构需要自行提供 `/etc/hop/core/hop-server`。

查看状态和日志：

```sh
/usr/share/hop/hop-core status
/etc/init.d/hop status
logread -e hop
```

## LuCI 和 UCI 字段

LuCI 页面中的设置对应 `/etc/config/hop`：

```uci
config hop 'main'
        option enabled '0'
        option config_path '/etc/hop/config.toml'
        option auto_download '1'
        option core_version 'latest'
        option release_base 'https://github.com/oslo254804746/hop-rs/releases'
        option log_stdout '1'
        option log_stderr '1'
```

| 字段 | 默认值 | 含义 |
|---|---|---|
| `enabled` | `0` | 是否由 procd 启动 Hop |
| `config_path` | `/etc/hop/config.toml` | 传给 `hop-server --config` 的启动配置路径 |
| `auto_download` | `1` | 核心缺失或固定版本不匹配时是否自动下载 |
| `core_version` | `latest` | 下载 `latest`，或指定 `v0.2.0`、`0.2.0` 这类版本 |
| `release_base` | 官方 GitHub Releases 地址 | 核心和 `SHA256SUMS` 的发布地址 |
| `log_stdout` | `1` | 把标准输出交给 procd 日志 |
| `log_stderr` | `1` | 把标准错误交给 procd 日志 |

修改 UCI 后保存并重启：

```sh
uci commit hop
/etc/init.d/hop restart
```

### 核心版本

`core_version = latest` 适合手工更新。已有核心可用时，服务重启不会每次检查新版本；需要更新时，在 LuCI 中点击核心下载按钮，或执行：

```sh
/usr/share/hop/hop-core update
/etc/init.d/hop restart
```

希望固定版本时设置完整标签或版本号：

```sh
uci set hop.main.core_version='v0.2.0'
uci commit hop
/etc/init.d/hop restart
```

如果安装的 release marker 与固定版本不一致，下一次启动会重新下载。设置 `auto_download = 0` 后，核心缺失或不可执行会让服务启动失败。

`release_base` 可以指向私有镜像，但目录结构必须兼容 GitHub Releases：

```text
<release_base>/latest/download/SHA256SUMS
<release_base>/latest/download/hop-server-linux-<arch>-musl.tar.gz
<release_base>/download/<tag>/SHA256SUMS
```

## Hop 启动配置

软件包自带的 `/etc/hop/config.toml` 内容如下：

```toml
[server]
ssh_listen = "0.0.0.0:2222"

[database]
path = "/var/lib/hop/hop.db"

[api]
enabled = false
listen = "127.0.0.1:8083"
token_file = "/var/lib/hop/api.token"
cors_allowlist = []

[ssh]
host_key_file = "/var/lib/hop/host_key"
host_key_type = "ed25519"
banner = "Welcome to Hop"
keepalive_interval = 30
connect_timeout = 10
proxy_policy = "assets_only"

[security]
master_key_file = "/var/lib/hop/master.key"

[inventory]
sources = []

[runtime]
temp_dir = "/tmp/hop"
log_level = "info"
session_retention_days = 30
```

默认行为：

- SSH 监听所有接口的 `2222` 端口。
- HTTP Control API 关闭。
- SQLite、Master Key 和 Host Key 保存在 `/var/lib/hop`。
- 没有配置资源清单来源。

修改监听地址、数据库路径或其他启动字段后，需要重启服务。完整字段说明见 [Hop 配置参考](https://github.com/oslo254804746/hop-rs/blob/master/docs/configuration.zh-CN.md)。

## 使用资源清单完成首次配置

OpenWrt 上推荐用资源清单管理 Access Key、SSH 资产和 TCP 资产。这样不需要在 root 和 `hop` 用户之间反复处理 CLI 写入权限。

### 1. 准备目录

```sh
mkdir -p /etc/hop/resources.d /etc/hop/keys /etc/hop/secrets
chown root:hop /etc/hop/resources.d /etc/hop/keys /etc/hop/secrets
chmod 0750 /etc/hop/resources.d /etc/hop/keys /etc/hop/secrets
```

把用于登录 Hop 的公钥保存为 `/etc/hop/keys/laptop.pub`：

```sh
chmod 0644 /etc/hop/keys/laptop.pub
```

如果 Hop 需要托管目标 SSH 登录，把目标密码或私钥放到 `/etc/hop/secrets`。例如：

```sh
chown root:hop /etc/hop/secrets/nas-root
chmod 0640 /etc/hop/secrets/nas-root
```

### 2. 创建资源文件

将以下内容保存为 `/etc/hop/resources.d/home.yaml`：

```yaml
api_version: hop/v1alpha1

credentials:
  nas-root:
    type: ssh_key
    username: root
    private_key:
      file: /etc/hop/secrets/nas-root

assets:
  nas:
    type: ssh
    host: 192.168.1.20
    port: 22
    credential: nas-root

  windows-rdp:
    type: tcp
    host: 192.168.1.30
    port: 3389

access:
  laptop:
    public_key:
      file: /etc/hop/keys/laptop.pub
```

```sh
chown root:hop /etc/hop/resources.d/home.yaml
chmod 0640 /etc/hop/resources.d/home.yaml
```

当前资产类型只有 `ssh` 和 `tcp`。RDP、MySQL、Redis 等服务都配置为 `tcp`，不需要单独的类型别名。

### 3. 启用资源来源

编辑 `/etc/hop/config.toml`，删除：

```toml
[inventory]
sources = []
```

替换为：

```toml
[[inventory.sources]]
id = "openwrt"
path = "/etc/hop/resources.d/*.yaml"
watch = true
prune = false
```

离线校验后重启：

```sh
su -s /bin/ash -c \
  '/etc/hop/core/hop-server config validate -f /etc/hop/resources.d/home.yaml --offline' \
  hop

/etc/init.d/hop restart
logread -e hop
```

Hop 会在启动时 apply 资源文件。`watch = true` 时，后续修改会自动生效；无效文件不会覆盖上一份有效 Catalog。

### 4. 测试 SSH 和 TCP

从电脑连接路由器上的 Hop：

```bash
ssh -p 2222 menu@192.168.1.1
ssh -p 2222 nas@192.168.1.1
```

转发 RDP：

```bash
ssh -N -T -p 2222 \
  -L 13389:windows-rdp.hop:3389 \
  menu@192.168.1.1
```

RDP 客户端随后连接 `127.0.0.1:13389`。更多连接方式见 [SSH 与 TCP 代理](https://github.com/oslo254804746/hop-rs/blob/master/docs/proxying.zh-CN.md)。

## Control API

LuCI 页面不使用 Hop Control API，也不管理 Catalog 资源。默认配置中的 `api.enabled = false` 不会打开 HTTP 端口。

如果外部面板需要 API，先创建 Token：

```sh
umask 077
head -c 32 /dev/urandom | hexdump -v -e '/1 "%02x"' > /var/lib/hop/api.token
chown hop:hop /var/lib/hop/api.token
chmod 0600 /var/lib/hop/api.token
```

然后修改 `/etc/hop/config.toml`：

```toml
[api]
enabled = true
listen = "127.0.0.1:8083"
token_file = "/var/lib/hop/api.token"
cors_allowlist = []
```

重启后，API 仍只监听路由器本机。远程开放 API 前需要单独配置 TLS、认证和防火墙。

## 防火墙

`luci-app-hop` 不修改 OpenWrt 防火墙。LAN 区域能否访问路由器的 `2222` 端口取决于现有 zone 策略。

如果需要从 WAN 访问，建议先通过 VPN 进入家庭网络。直接开放 SSH 端口时，应创建范围尽可能小的防火墙规则，并确认 Access Key 只包含需要的资产。

## 备份

停止服务后备份以下目录：

```sh
/etc/init.d/hop stop
tar -czf /tmp/hop-backup.tgz /etc/config/hop /etc/hop /var/lib/hop
/etc/init.d/hop start
```

`/var/lib/hop` 中的数据库和 Master Key 必须成对保留。只恢复数据库无法解密托管凭据。

## 排错

| 现象 | 检查项 |
|---|---|
| 核心下载失败 | 系统时间、DNS、CA 证书、`release_base` 和 `logread -e hop-core` |
| `unsupported Hop core architecture` | `uname -m` 是否属于当前支持的机器名 |
| 服务没有运行 | `enabled`、`config_path`、核心状态和 `logread -e hop` |
| 资源文件没有生效 | `watch`、文件权限和 `config validate` 输出 |
| SSH 公钥被拒绝 | `access` 中的公钥文件是否完整，Catalog 是否成功 apply |
| TCP 转发被拒绝 | 资产名称、端口和 Access Key 白名单 |
| 修改 UCI 后无变化 | 是否执行了 `uci commit hop` 和服务重启 |
