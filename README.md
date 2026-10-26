# sing-box VPS 管理脚本

`new-install.sh` 用于在 Alpine Linux VPS 上安装和管理 sing-box 节点，支持 VLESS-Reality、SOCKS5，以及将本机入站流量经另一台 VPS 转发。

## 环境要求

- Alpine Linux，使用 OpenRC 管理服务。
- 以 root 身份运行。
- VPS 可访问 GitHub，以下载 sing-box。
- 脚本会使用 `apk` 安装依赖，并将服务配置和数据放在 `/root/singbox`。

## 安装与启动

将脚本复制到 VPS 后运行：

```sh
chmod +x new-install.sh
./new-install.sh
```

运行后会显示交互式管理菜单。脚本首次运行时会安装所需组件、下载 sing-box，并创建 OpenRC 服务。之后可以运行 `sb` 再次打开管理菜单。

## 主菜单

| 选项 | 功能 |
| --- | --- |
| 1 | 添加或重设 VLESS-Reality 入站 |
| 2 | 添加或重设 SOCKS5 入站 |
| 3 | 同时添加 VLESS-Reality 和 SOCKS5 入站 |
| 4 | 修改已安装协议的配置 |
| 5 | 删除协议节点 |
| 6 | 查看节点信息和分享链接 |
| 7 | 重启 sing-box 并查看服务状态 |
| 8 | 管理流量转发 |
| 0 | 退出脚本 |

## 配置流量转发

流量转发将客户端连接到本 VPS 的入站流量，经配置的上游 VPS 出口转发。当前设置的默认出口同时用于本机的 VLESS-Reality 和 SOCKS5 入站。

1. 先通过主菜单的选项 1、2 或 3 创建本机入站节点。
2. 进入主菜单选项 8，选择“新增转发配置”。
3. 选择上游协议并填写目标 VPS 的连接参数。
4. 首条配置会自动设为默认出口并启用转发；有多条配置时，可用“设置默认出口”切换当前上游。
5. 使用“关闭/恢复流量转发”可以暂停转发。恢复后会继续使用当前默认出口。

支持的上游协议：

- **VLESS-Reality**：目标地址、端口、UUID、SNI、公钥、Short ID 和流控。
- **SOCKS5**：目标地址和端口；用户名与密码可以同时填写或同时留空。

转发管理菜单还支持编辑、查看列表和删除配置。删除默认出口时，脚本会自动选择剩余列表中的第一条；删除最后一条配置时会关闭转发。

## 配置文件

- `/root/singbox/config.json`：sing-box 主配置，包含入站、出口和路由规则。
- `/root/singbox/forwarding.json`：转发配置列表、默认出口和启用状态。
- `/root/singbox/vless_pub.key`：本机 VLESS-Reality 分享链接所需的公钥。
- `/root/singbox/share-link.txt`：生成的节点分享链接。

转发配置文件包含上游认证信息，仅供管理员访问。脚本新建该文件时会限制文件权限。

## 注意事项

- 上游 VPS 必须已运行相应协议服务，并允许本 VPS 连接其端口。
- 防火墙或云平台安全组需要放行本机入站节点所使用的端口。
- 脚本配置的 SOCKS5 入站账号密码用于本机 SOCKS5 节点；上游 SOCKS5 的认证信息单独保存在转发配置中。
- `old-install.sh` 是未包含转发管理功能的原始脚本。
