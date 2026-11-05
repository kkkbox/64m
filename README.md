# kkkbox sing-box 小内存 VPS 管理脚本

支持 **Alpine Linux（OpenRC）**、**Debian / Ubuntu（systemd）** 的 sing-box 部署与管理，提供 VLESS-Reality 和 SOCKS5。首次运行脚本即注册全局命令 `sb`，以后在 SSH 终端任意目录输入 `sb` 即可添加、修改、删除节点或查看分享链接。

## 环境要求

- 使用 `root` 用户，或通过 `sudo` 运行。
- Alpine 需要 `apk`、OpenRC；Debian / Ubuntu 需要 `apt-get`，并以 systemd 作为初始化系统。
- 支持 `x86_64 / amd64`、`aarch64 / arm64`、`i386 / i486 / i586 / i686` 架构。
- 需要访问软件源、GitHub API 和 GitHub Releases；生成分享链接还需访问公网 IPv4 查询服务。
- 面向 64MB / 128MB 小内存场景，但实际内存需求取决于系统、核心版本及连接数量。Debian / Ubuntu 本身和安装依赖时通常需要更多内存或 Swap；64MB VPS 优先选择 Alpine。

## 安装与升级管理脚本

### Debian / Ubuntu

以 root 执行；普通用户先执行 `sudo -i`：

```sh
apt-get update
apt-get install -y ca-certificates wget
wget -O install.sh https://raw.githubusercontent.com/kkkbox/64m/main/install.sh
sh install.sh
```

### Alpine

```sh
apk add --no-cache ca-certificates wget
wget -O install.sh https://raw.githubusercontent.com/kkkbox/64m/main/install.sh
sh install.sh
```

上述下载地址需要先在仓库发布本次修改。若手上已有新版 `install.sh`，将文件上传至 VPS 后直接执行 `sh install.sh` 即可。

脚本启动时会检测系统、注册 `/usr/local/bin/sb` 并补齐依赖；选择添加协议后才会安装 sing-box 核心、尝试创建临时 Swap 和生成服务配置。核心使用 GitHub 的最新稳定版，仅在本地没有可执行核心时下载。

更新旧版管理脚本时，重新上传或下载新版并运行 `sh install.sh`，即可更新 `sb` 并保留已有节点配置、UUID 和密钥。仅打开菜单不会重设节点，也不会更新已安装核心；选择“添加/重设 VLESS”或 `sb modify keys` 才会重置该节点的 UUID 和密钥。

如果当前终端未将 `/usr/local/bin` 加入 `PATH`，使用 `/usr/local/bin/sb`，或执行：

```sh
export PATH="/usr/local/bin:$PATH"
```

## sb 快捷管理命令

```sh
sb
```

不带参数时打开完整主菜单：

```text
1. 添加/重设 VLESS-Reality 协议
2. 添加/重设 SOCKS5 协议
3. 一键同时安装 VLESS-Reality + SOCKS5
4. 修改已安装协议配置 (端口/SNI/账号密码)
5. 删除指定协议节点
6. 查看当前分享链接与节点信息
7. 重启 sing-box 服务并查看状态
8. 查看 sing-box 服务状态
9. 查看 sb 管理命令帮助
0. 退出脚本
```

也可以直接进入指定管理功能，参数仍通过交互输入：

| 命令 | 功能 |
| --- | --- |
| `sb` / `sb menu` | 打开主菜单 |
| `sb add vless` | 添加/重设 VLESS-Reality，生成新的 UUID 和密钥 |
| `sb add socks5` | 添加/重设 SOCKS5 |
| `sb add all` | 依次添加两个协议 |
| `sb modify` | 打开修改菜单 |
| `sb modify vless` | 修改 VLESS 端口与 SNI，保留原 UUID、私钥和 Short ID |
| `sb modify socks5` | 修改 SOCKS5 端口、用户名和密码 |
| `sb modify keys` | 重设 VLESS-Reality，重新生成 UUID、密钥和 Short ID |
| `sb delete` | 打开删除菜单 |
| `sb delete vless` | 直接删除 VLESS-Reality，保留 SOCKS5 |
| `sb delete socks5` | 直接删除 SOCKS5，保留 VLESS-Reality |
| `sb delete all` | 直接清空所有入站并停止服务 |
| `sb links` | 显示并重新生成分享链接 |
| `sb start` / `sb stop` / `sb restart` | 启动 / 停止 / 重启服务 |
| `sb status` | 查看服务状态 |
| `sb check` | 使用 sing-box 校验当前配置 |
| `sb help` / `sb --help` | 查看管理命令帮助 |

### 修改端口、域名与密码

修改 VLESS-Reality：

```sh
sb modify vless
```

依次输入新端口、新 SNI 域名；回车保留当前值。SNI 填写用于 Reality 握手的 TLS 域名，例如 `www.microsoft.com`，不含 `https://`、路径或端口。

修改 SOCKS5：

```sh
sb modify socks5
```

依次输入新端口、新用户名和新密码；回车保留当前值。端口必须位于 `1–65535`，脚本会检查其他节点和本机 TCP 监听端口是否冲突。

配置修改后先执行 `sing-box check`，校验通过后才保存并重启服务，随后输出新链接。更改端口、域名、账号或密码后，需要同步更新客户端；服务重启会短暂中断两个协议的已有连接。

## 服务与内存设置

脚本自动选择服务管理方式，并设置开机启动：

| 系统 | 服务文件 | 原生服务命令 |
| --- | --- | --- |
| Debian / Ubuntu | `/etc/systemd/system/sing-box.service` | `systemctl status/restart/stop sing-box`，按需选择一个动作 |
| Alpine | `/etc/init.d/sing-box` | `rc-service sing-box status/restart/stop`，按需选择一个动作 |

两个服务都设置 `GOGC=20`、`GOMEMLIMIT=20MiB`，默认关闭 sing-box 日志。`GOMEMLIMIT` 是 Go 运行时的软内存目标，并非进程总内存的硬上限，也不能保证不会 OOM。

系统没有 Swap 且 `/swapfile` 不存在时，添加协议会尝试创建 128MB 临时 Swap。启用失败会提示并继续安装；已有 `/swapfile` 不会被覆盖。脚本不修改 `/etc/fstab`，系统重启后不会自动重新挂载此临时 Swap。

查看 Debian / Ubuntu 服务启动日志：

```sh
journalctl -u sing-box -n 50 --no-pager
```

## 配置、分享链接与备份

| 路径 | 用途 |
| --- | --- |
| `/root/singbox/sing-box` | sing-box 核心 |
| `/root/singbox/config.json` | 当前服务配置 |
| `/root/singbox/config.json.bak` | 最近一次成功保存配置前的副本，每次保存覆盖 |
| `/root/singbox/vless_pub.key` | 当前 Reality 公钥 |
| `/root/singbox/vless_pub.key.bak` | 最近一次重设或删除 VLESS 前的公钥备份 |
| `/root/singbox/share-link.txt` | 当前节点分享链接，包含账号凭据 |
| `/usr/local/bin/sb` | 独立的快捷管理脚本，原上传文件移走后仍可使用 |
| `/swapfile` | 条件满足时创建的临时 Swap |
| 项目内 `install.sh.bak` | 本次修改前的原始安装脚本存档 |

配置目录设为 `700`，配置与生成的链接文件设为 `600`。修改或删除单个协议不会删掉另一个协议的配置；清空所有协议会停止服务并删除当前链接文件。

VLESS 输出 `vless://` 链接；SOCKS5 输出 `socks5://` 和 Telegram 快连链接。用户名、密码中的特殊字符会进行 URL 编码。链接按公网 IPv4 生成，使用 HTTPS 获取地址；获取失败时不会覆盖已有链接文件。

```sh
cat /root/singbox/share-link.txt
/root/singbox/sing-box check -c /root/singbox/config.json
```

配置校验失败会保留原配置。若配置通过校验但服务启动失败，脚本会报错，保存前配置仍在 `config.json.bak` 中；可按需恢复：

```sh
cp /root/singbox/config.json.bak /root/singbox/config.json
sb check
sb restart
sb links
```

若要撤销最近一次 VLESS 重设或删除，在恢复配置的同时，还需恢复与备份配置配套的 `vless_pub.key.bak`，再重新生成链接。公钥备份与配置备份各自覆盖，未必总属于同一版本，恢复前需核对。

## 常见问题

- **节点无法连接**：检查 VPS 防火墙、安全组是否开放所选 TCP 端口；NAT VPS 需使用已分配且正确映射的公网端口。脚本不自动修改防火墙。
- **纯 IPv6 VPS**：当前自动安装与链接输出按 IPv4 监听地址 `0.0.0.0` 设计；纯 IPv6 环境需自行调整监听和链接地址。
- **没有 systemd 的 Debian 容器**：当前 Debian / Ubuntu 服务部署需要运行中的 systemd；精简容器和 SysVinit 不在本脚本支持范围内。
- **提示端口占用**：更换端口，或先处理占用端口的程序。修改节点时继续使用该节点原端口是允许的。
- **小内存 VPS 安装失败**：先确认软件源可达、磁盘空间足够以及 Swap 是否可用。临时 Swap 创建发生在安装依赖之后，无法解决包管理器阶段本身的内存不足。

本项目用于网络技术学习与个人合法通信测试，请遵守服务器所在地和使用所在地的相关规定。
