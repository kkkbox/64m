#!/bin/sh

set -eu

WORK_DIR="/root/singbox"
SERVICE_FILE="/etc/init.d/sing-box"
SB_COMMAND="/usr/local/bin/sb"

if [ "$(id -u)" -ne 0 ]; then
    echo "请以 root 身份运行卸载脚本。"
    exit 1
fi

echo "此操作将停止并移除 sing-box 服务、管理命令和配置目录："
echo "  - ${SERVICE_FILE} (仅当它由本安装脚本创建时)"
echo "  - ${SB_COMMAND} (仅当它包含本项目标识时)"
echo "  - ${WORK_DIR} (包括节点配置、转发配置和分享链接)"
echo "系统软件包和 /swapfile 不会被删除。"
printf '确认卸载请输入 YES：'
read -r answer

if [ "$answer" != "YES" ]; then
    echo "已取消卸载。"
    exit 0
fi

if [ -f "$SERVICE_FILE" ] &&
    grep -Fq 'command="/root/singbox/sing-box"' "$SERVICE_FILE"; then
    service sing-box stop >/dev/null 2>&1 || true
    rc-update del sing-box default >/dev/null 2>&1 || true
    rm -f "$SERVICE_FILE"
else
    echo "未发现由本脚本创建的 sing-box 服务文件，跳过服务删除。"
fi

if [ -f "$SB_COMMAND" ] &&
    grep -Fq 'kkkbox sing-box 64M VPS 管理脚本' "$SB_COMMAND"; then
    rm -f "$SB_COMMAND"
else
    echo "未发现本项目的 sb 管理命令，跳过命令删除。"
fi

rm -rf "$WORK_DIR"
echo "sing-box 管理脚本相关文件已卸载。"
