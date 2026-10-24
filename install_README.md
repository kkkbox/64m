# kkkbox sing-box 64M VPS 极简管理脚本 (Alpine 专版)

专为 **64MB / 128MB 超小内存 VPS** 打造的 `sing-box` 极简部署与交互式管理脚本。深度适配 **Alpine Linux (OpenRC)**，通过内核级内存回收调优与无损配置管理，实现低资源占用下的多协议稳定运行。

---

## ✨ 核心特性

* **极致小内存优化**
  * **自动防 OOM**：检测到系统无 Swap 时，自动创建并挂载 `128MB` 虚拟内存。
  * **Go 内存墙限制**：在 OpenRC 服务中注入 `GOGC=20` 与 `GOMEMLIMIT=20MiB` 环境变量，并彻底关闭日志写入，将常驻内存压制在极低水平。
* **双协议独立与共存**
  * 支持 **VLESS-XTLS-Vision-Reality** 与 **SOCKS5** 协议。
  * 支持单独安装任一协议，或一键同时部署双协议共存。
* **无损增删改查 (CRUD)**
  * 基于 `jq` 动态操作配置文件，支持随时**新增协议**、**单独修改现有协议参数**（如端口、SNI 域名、SOCKS5 账号密码、重置密钥）或**单独删除某一协议**，不影响其他正在运行的节点。
* **全局快捷命令**
  * 首次运行后自动注册系统快捷指令，任意位置输入 `sb` 即可呼出管理面板。
* **多架构自适应**
  * 自动识别 `x86_64 (amd64)`、`aarch64 (arm64)` 及 `386` 架构并拉取对应官方最新核心。

---

## 🖥️ 环境要求

* **操作系统**：Alpine Linux（依赖 `apk` 包管理器与 `OpenRC` 初始化系统）
* **系统权限**：`root` 用户
* **硬件规格**：最低 64MB 内存 / 500MB 可用磁盘空间

---

## 🚀 快速开始

### 方式一：一键脚本运行（适用于已托管至 GitHub / 仓库）

```sh
wget -O install.sh [https://raw.githubusercontent.com/kkkbox/64m/main/install.sh](https://raw.githubusercontent.com/kkkbox/64m/main/install.sh) && chmod +x install.sh && ./install.sh
```

### 方式二：本地手动创建运行

```sh
cat << 'EOF' > install.sh
# 将脚本完整代码粘贴至此处
EOF
chmod +x install.sh && ./install.sh
```

### 日常呼出管理面板

首次执行脚本后，后续只需在终端输入以下命令即可随时管理节点：

```sh
sb
```

---

## 📋 功能菜单预览

运行 `./install.sh` 或 `sb` 后将展示以下交互菜单：

```text
==========================================
    kkkbox sing-box 64M VPS 管理脚本      
==========================================
1. 添加/重设 VLESS-Reality 协议
2. 添加/重设 SOCKS5 协议
3. 一键同时安装 VLESS-Reality + SOCKS5
4. 修改已安装协议配置 (端口/SNI/账号密码)
5. 删除指定协议节点
6. 查看当前分享链接与节点信息
7. 重启 sing-box 服务并查看状态
0. 退出脚本
==========================================
```

### 节点输出格式说明
配置完成后，脚本会自动获取公网 IPv4 并生成以下客户端连接格式（同时自动保存至本地文件）：
* **VLESS-Reality**：标准 `vless://` 分享链接（适配 v2rayN、Nekoray、Shadowrocket、sing-box 等客户端）。
* **SOCKS5**：明文连接信息、标准 `socks5://` 分享链接，以及 **Telegram 一键快连链接 (`https://t.me/socks?...`)**。

---

## 📂 文件与目录结构

| 路径 | 说明 |
| :--- | :--- |
| `/root/singbox/sing-box` | sing-box 核心二进制可执行文件 |
| `/root/singbox/config.json` | sing-box 主配置文件 |
| `/root/singbox/vless_pub.key` | Reality 协议对应的 PublicKey 缓存文件 |
| `/root/singbox/share-link.txt` | 自动生成的节点分享链接汇总文件 |
| `/etc/init.d/sing-box` | Alpine OpenRC 守护进程服务文件（含内存限制参数） |
| `/usr/local/bin/sb` | 全局快捷管理命令脚本 |
| `/swapfile` | 自动创建的 128MB 虚拟内存文件（若系统原本无 Swap） |

---

## 🛠️ 常用维护命令

除使用 `sb` 菜单外，您也可以直接使用 Alpine 原生服务命令管理进程：

```sh
# 查看运行状态
service sing-box status

# 重启服务
service sing-box restart

# 停止服务
service sing-box stop

# 查看已保存的节点分享链接
cat /root/singbox/share-link.txt

# 验证配置文件语法是否正确
/root/singbox/sing-box check -c /root/singbox/config.json
```

---

## ❓ 常见问题 (FAQ)

**1. NAT VPS 无法创建 Swap 怎么办？**
部分基于容器虚拟化（如 LXC / OpenVZ）的特价 64M VPS 不允许宿主机以外挂载 `/swapfile`。即使 Swap 创建跳过，脚本内置的 `GOGC=20` 与 `GOMEMLIMIT=20MiB` 依然能够限制 `sing-box` 的内存体积，保障正常启动。

**2. 节点配置成功但客户端无法连接？**
* 请确认 VPS 服务商后台的**安全组/防火墙**已放行您设置的 TCP 端口。
* 如果使用的是 **NAT 共享 IP VPS**，请确保在脚本中输入的端口号位于服务商分配给您的**可用端口映射区间**内。

**3. 为什么脚本默认只获取 IPv4 地址？**
脚本通过 `ipv4.icanhazip.com` 自动提取公网 IPv4。若您的机器为 **纯 IPv6 VPS**，只需将生成链接中的 IP 地址手动替换为您的 `[IPv6地址]`，并在 `/root/singbox/config.json` 中将入站监听 `"listen": "0.0.0.0"` 改为 `"::"` 后重启服务即可。

---

## ⚠️ 免责声明

本项目仅供网络技术学习、Linux 内存调优研究与个人合法跨境通信测试使用。请勿将其用于任何违反服务器所在地及使用者所在地法律法规的用途，一切因违规使用造成的后果由使用者自行承担。
