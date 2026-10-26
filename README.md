# kkkbox sing-box 64M VPS 极简管理脚本 (Alpine 专版)

专为 **64MB / 128MB 小内存 VPS** 打造的 `sing-box` 部署与交互式管理脚本。支持 **VLESS-Reality**、**SOCKS5** 节点，以及将本机入站流量转发到另一台 VPS。

---

## ✨ 核心特性

* **小内存 VPS 优化**
  * 系统没有 Swap 时，尝试创建并挂载 `128MB` Swap。
  * OpenRC 服务设置 `GOGC=20` 与 `GOMEMLIMIT=20MiB`，并关闭 sing-box 日志。
* **双协议节点管理**
  * 支持 **VLESS-Reality** 和 **SOCKS5**。
  * 可单独添加协议，也可一键添加两种协议。
  * 支持修改端口、SNI、账号密码，或单独删除节点。
* **多出口流量转发**
  * 支持配置多个 **VLESS-Reality** 或 **SOCKS5** 上游出口。
  * 支持新增、编辑、查看列表、设置默认出口和删除配置。
  * 可关闭或恢复转发；转发关闭时，本机入站流量恢复直连。
  * 当前默认出口同时用于本机 VLESS-Reality 和 SOCKS5 入站。
* **快捷管理命令**
  * 安装后可在终端任意位置运行 `sb` 打开管理菜单。
* **多架构核心下载**
  * 根据系统架构选择 sing-box 核心，支持 `amd64` 和 `arm64`。

---

## 🖥️ 环境要求

* **操作系统**：Alpine Linux，使用 `apk` 包管理器和 OpenRC。
* **系统权限**：以 `root` 用户运行。
* **网络要求**：VPS 能访问 GitHub 下载 sing-box。
* **硬件规格**：面向 64MB / 128MB 小内存 VPS；需要预留核心文件和系统运行空间。

---

## 🚀 快速开始

### 一键安装

将 `install.sh` 发布到 GitHub 仓库 `kkkbox/64m` 的 `main` 分支后，以 root 身份在 VPS 上执行：

```sh
wget -O install.sh https://raw.githubusercontent.com/kkkbox/64m/main/install.sh && chmod +x install.sh && ./install.sh
```

命令会下载脚本、设置执行权限并启动安装。首次运行会安装依赖、下载 sing-box、创建 OpenRC 服务并显示管理菜单。

### 日常打开管理菜单

```sh
sb
```

### 一键卸载

将 `uninstall.sh` 发布到同一仓库的 `main` 分支后，以 root 身份在 VPS 上执行：

```sh
wget -O uninstall.sh https://raw.githubusercontent.com/kkkbox/64m/main/uninstall.sh && chmod +x uninstall.sh && ./uninstall.sh
```

卸载脚本会先要求输入 `YES` 确认，然后停止并移除本项目创建的 sing-box 服务、管理命令和 `/root/singbox` 配置目录。系统软件包和 `/swapfile` 会保留。

---

## 📋 功能菜单预览

运行 `install.sh` 或 `sb` 后会显示：

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
8. 配置流量转发到另一台 VPS
0. 退出脚本
==========================================
```

### 转发管理菜单

选择主菜单的 `8` 后，可以管理上游出口：

```text
1. 新增转发配置
2. 编辑转发配置
3. 关闭/恢复流量转发
4. 查看转发列表
5. 设置默认出口
6. 删除转发配置
0. 返回主菜单
```

首次添加的出口会自动设为默认并启用转发。存在多条配置时，可切换默认出口；删除默认出口后，会自动选择列表中的第一条。删除最后一条配置会关闭转发。

### 节点分享信息

配置入站节点后，脚本会生成连接信息并保存到 `/root/singbox/share-link.txt`：

* **VLESS-Reality**：标准 `vless://` 分享链接。
* **SOCKS5**：节点地址、端口和账号密码，以及 `socks5://` 和 Telegram 快连链接。

---

## 🔁 配置流量转发

1. 先通过主菜单添加本机的 VLESS-Reality 或 SOCKS5 入站节点。
2. 进入主菜单 `8`，选择“新增转发配置”。
3. 选择上游协议并填写目标 VPS 的连接参数。
4. 有多个出口时，通过“设置默认出口”选择当前出口。
5. 可使用“关闭/恢复流量转发”临时切换转发状态，配置列表会保留。

支持的上游参数：

* **VLESS-Reality**：目标地址、端口、UUID、SNI、公钥、Short ID 和流控。
* **SOCKS5**：目标地址、端口和可选认证。用户名与密码需要同时填写或同时留空。

目标 VPS 需要已运行对应服务，并允许本机 VPS 连接其服务端口。开启转发后，本机两种入站协议的流量都会经当前默认出口转发。

---

## 📂 文件与目录

| 路径 | 说明 |
| :--- | :--- |
| `/root/singbox/sing-box` | sing-box 核心程序 |
| `/root/singbox/config.json` | sing-box 主配置，包含入站、出口和路由 |
| `/root/singbox/forwarding.json` | 转发配置列表、默认出口和启用状态 |
| `/root/singbox/vless_pub.key` | 本机 Reality 公钥缓存 |
| `/root/singbox/share-link.txt` | 节点分享链接汇总 |
| `/etc/init.d/sing-box` | Alpine OpenRC 服务脚本 |
| `/usr/local/bin/sb` | 全局快捷管理命令 |
| `/swapfile` | 无 Swap 时尝试创建的 128MB 文件 |

`forwarding.json` 保存上游连接参数，可能包含认证信息；脚本创建该文件时会限制访问权限。

---

## 🛠️ 常用维护命令

```sh
# 查看 sing-box 服务状态
service sing-box status

# 重启 sing-box
service sing-box restart

# 停止 sing-box
service sing-box stop

# 查看节点分享链接
cat /root/singbox/share-link.txt

# 检查 sing-box 配置
/root/singbox/sing-box check -c /root/singbox/config.json
```

---

## ❓ 常见问题 (FAQ)

**1. 为什么脚本要求 Alpine Linux？**

脚本使用 `apk` 安装依赖，并用 OpenRC 注册和管理 sing-box 服务。

**2. 转发已开启，但流量无法通过目标 VPS？**

* 确认目标 VPS 上对应的 VLESS-Reality 或 SOCKS5 服务正在运行。
* 确认目标地址、端口、UUID、Reality 参数或 SOCKS5 认证信息填写正确。
* 检查两台 VPS 的防火墙和云平台安全组是否允许相关连接。

**3. 新增出口后会立即转发吗？**

首次新增出口会自动设置为默认并开启转发。添加后续出口不会替换当前默认出口；需要通过“设置默认出口”切换。

**4. 关闭转发会删除已保存的出口吗？**

不会。关闭转发只会让本机入站流量恢复直连；再次恢复时继续使用当前默认出口。

---

## ⚠️ 免责声明

本项目用于 sing-box 部署和网络技术学习。请遵守 VPS 服务商的使用条款及服务器所在地和使用者所在地的法律法规。
