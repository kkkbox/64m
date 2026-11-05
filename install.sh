#!/bin/sh

red() { printf '\033[1;31m%s\033[0m\n' "$1"; }
green() { printf '\033[1;32m%s\033[0m\n' "$1"; }
yellow() { printf '\033[1;33m%s\033[0m\n' "$1"; }

WORK_DIR="/root/singbox"
CONFIG_FILE="${WORK_DIR}/config.json"
BIN_FILE="${WORK_DIR}/sing-box"
PUB_KEY_FILE="${WORK_DIR}/vless_pub.key"
LINK_FILE="${WORK_DIR}/share-link.txt"
MANAGER_FILE="/usr/local/bin/sb"
SYSTEMD_UNIT="/etc/systemd/system/sing-box.service"
OPENRC_SERVICE="/etc/init.d/sing-box"

prompt() {
    printf '%s' "$1"
    IFS= read -r "$2"
}

detect_platform() {
    [ "$(id -u)" = "0" ] || { red "请使用 root 用户运行，例如 sudo sh install.sh。"; return 1; }
    [ "$(uname -s)" = "Linux" ] || { red "此脚本仅支持 Linux VPS。"; return 1; }
    [ -r /etc/os-release ] || { red "无法识别操作系统：缺少 /etc/os-release。"; return 1; }
    . /etc/os-release
    case "$ID" in
        alpine)
            command -v apk >/dev/null 2>&1 && command -v rc-service >/dev/null 2>&1 || {
                red "Alpine 需要 apk 和 OpenRC。"; return 1;
            }
            PLATFORM="alpine"
            ;;
        debian|ubuntu)
            command -v apt-get >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1 &&
                [ -d /run/systemd/system ] || {
                red "Debian / Ubuntu 需要 apt-get，并使用 systemd 启动系统。"; return 1;
            }
            PLATFORM="debian"
            ;;
        *) red "暂不支持 $ID，请使用 Alpine、Debian 或 Ubuntu。"; return 1 ;;
    esac
}

install_dependencies() {
    missing_dependencies=""
    for dependency in wget tar jq xxd mkswap swapon ss; do
        command -v "$dependency" >/dev/null 2>&1 || missing_dependencies="$missing_dependencies $dependency"
    done
    if [ -z "$missing_dependencies" ] && [ -s /etc/ssl/certs/ca-certificates.crt ]; then
        return 0
    fi
    yellow "正在安装必要依赖..."
    case "$PLATFORM" in
        alpine)
            apk update && apk add ca-certificates wget tar gcompat jq xxd util-linux iproute2 || return 1
            ;;
        debian)
            apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
                ca-certificates wget tar jq xxd util-linux iproute2 || return 1
            ;;
    esac
}

register_manager() {
    manager_source="$0"
    if [ ! -f "$manager_source" ]; then
        manager_source=$(command -v "$0") || return 1
    fi
    if [ "$manager_source" -ef "$MANAGER_FILE" ]; then
        return 0
    fi
    mkdir -p "$(dirname "$MANAGER_FILE")" || return 1
    manager_tmp=$(mktemp "${MANAGER_FILE}.XXXXXX") || return 1
    if ! cp "$manager_source" "$manager_tmp" || ! chmod 755 "$manager_tmp" ||
        ! mv -f "$manager_tmp" "$MANAGER_FILE"; then
        rm -f "$manager_tmp"
        red "注册 sb 管理命令失败。"
        return 1
    fi
    green "已注册快捷管理命令：sb"
    case ":$PATH:" in
        *:/usr/local/bin:*) ;;
        *) yellow "当前 PATH 未包含 /usr/local/bin，可执行 /usr/local/bin/sb。" ;;
    esac
}

setup_swap() {
    swap_size=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
    [ "$swap_size" = "0" ] || return 0
    if [ -e /swapfile ]; then
        yellow "系统无可用 Swap，但 /swapfile 已存在，跳过创建以保留原文件。"
        return 0
    fi
    yellow "检测到无 Swap，尝试创建临时 128MB Swap..."
    if dd if=/dev/zero of=/swapfile bs=1M count=128 2>/dev/null &&
        chmod 600 /swapfile && mkswap /swapfile >/dev/null 2>&1 && swapon /swapfile; then
        green "临时 Swap 创建成功（重启后需重新启用）。"
    else
        rm -f /swapfile
        yellow "Swap 创建或启用失败，将继续安装；部分容器 VPS 不允许启用 Swap。"
    fi
}

install_core() {
    [ ! -x "$BIN_FILE" ] || return 0
    case "$(uname -m)" in
        x86_64|amd64) box_arch="amd64" ;;
        aarch64|arm64) box_arch="arm64" ;;
        i386|i486|i586|i686) box_arch="386" ;;
        *) red "不支持的 CPU 架构：$(uname -m)"; return 1 ;;
    esac
    yellow "正在获取 sing-box 最新稳定版本号..."
    last_version=$(wget -qO- -T 20 -t 2 https://api.github.com/repos/SagerNet/sing-box/releases/latest |
        jq -er '.tag_name | select(type == "string" and test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))') || {
        red "获取版本号失败，请检查网络及 GitHub API 访问限制。"; return 1;
    }
    file_version=${last_version#v}
    download_dir=$(mktemp -d "${WORK_DIR}/.download.XXXXXX") || return 1
    download_url="https://github.com/SagerNet/sing-box/releases/download/${last_version}/sing-box-${file_version}-linux-${box_arch}.tar.gz"
    yellow "正在下载 sing-box ${last_version} (${box_arch})..."
    if wget -T 30 -t 2 "$download_url" -O "$download_dir/sing-box.tar.gz" &&
        tar -xzf "$download_dir/sing-box.tar.gz" -C "$download_dir" &&
        chmod 755 "$download_dir/sing-box-${file_version}-linux-${box_arch}/sing-box" &&
        "$download_dir/sing-box-${file_version}-linux-${box_arch}/sing-box" version &&
        mv "$download_dir/sing-box-${file_version}-linux-${box_arch}/sing-box" "$BIN_FILE"; then
        rm -rf "$download_dir"
        green "sing-box 核心安装完成。"
    else
        rm -rf "$download_dir"
        red "sing-box 下载、解压或运行检查失败。"
        return 1
    fi
}

ensure_service() {
    if [ "$PLATFORM" = "debian" ]; then
        mkdir -p "$(dirname "$SYSTEMD_UNIT")" || return 1
        service_tmp=$(mktemp "${SYSTEMD_UNIT}.XXXXXX") || return 1
        cat > "$service_tmp" <<'SYSTEMD_EOF'
[Unit]
Description=sing-box proxy service
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
WorkingDirectory=/root/singbox
ExecStartPre=/root/singbox/sing-box check -c /root/singbox/config.json
ExecStart=/root/singbox/sing-box run -c /root/singbox/config.json
Environment=GOGC=20
Environment=GOMEMLIMIT=20MiB
LimitNOFILE=30000
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF
        if cmp -s "$service_tmp" "$SYSTEMD_UNIT"; then
            rm -f "$service_tmp"
        else
            chmod 644 "$service_tmp" && mv "$service_tmp" "$SYSTEMD_UNIT" &&
                systemctl daemon-reload || { rm -f "$service_tmp"; return 1; }
        fi
        systemctl enable sing-box || return 1
    else
        mkdir -p "$(dirname "$OPENRC_SERVICE")" || return 1
        service_tmp=$(mktemp "${OPENRC_SERVICE}.XXXXXX") || return 1
        cat > "$service_tmp" <<'OPENRC_EOF'
#!/sbin/openrc-run
name="sing-box"
command="/root/singbox/sing-box"
command_args="run -c /root/singbox/config.json"
pidfile="/run/sing-box.pid"
command_background="yes"
rc_ulimit="-n 30000"
export GOGC=20
export GOMEMLIMIT=20MiB
depend() { need net; after net; }
start_pre() { "$command" check -c /root/singbox/config.json; }
OPENRC_EOF
        chmod 755 "$service_tmp" && mv "$service_tmp" "$OPENRC_SERVICE" &&
            rc-update -q add sing-box default || { rm -f "$service_tmp"; return 1; }
    fi
}

init_env() {
    mkdir -p "$WORK_DIR" && chmod 700 "$WORK_DIR" || return 1
    setup_swap
    install_core || return 1
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" <<'JSON_EOF'
{
  "log": { "disabled": true, "level": "fatal" },
  "inbounds": [],
  "outbounds": [{ "type": "direct", "tag": "direct" }]
}
JSON_EOF
    fi
    chmod 600 "$CONFIG_FILE" || return 1
    ensure_service
}

require_config() {
    [ -f "$CONFIG_FILE" ] && [ -x "$BIN_FILE" ] || {
        red "尚未安装 sing-box 或配置，请先添加协议节点。"; return 1;
    }
    jq -e '.inbounds | type == "array"' "$CONFIG_FILE" >/dev/null || {
        red "配置文件无效，请检查 $CONFIG_FILE。"; return 1;
    }
}

service_action() {
    if [ "$PLATFORM" = "debian" ]; then
        systemctl "$1" sing-box --no-pager
    else
        rc-service sing-box "$1"
    fi
}

restart_service() {
    require_config || return 1
    "$BIN_FILE" check -c "$CONFIG_FILE" || return 1
    inbound_count=$(jq '.inbounds | length' "$CONFIG_FILE") || return 1
    if [ "$inbound_count" -eq 0 ]; then
        yellow "当前未配置任何入站协议，停止 sing-box 服务。"
        service_action stop
    else
        service_action restart && sleep 1 && service_action status || {
            red "服务未能正常运行，请检查配置、端口占用及服务日志。"
            red "修改前的配置备份：${CONFIG_FILE}.bak"
            return 1
        }
    fi
}

save_config() {
    config_filter="$1"
    shift
    config_tmp=$(mktemp "${CONFIG_FILE}.XXXXXX") || return 1
    if ! jq "$@" "$config_filter" "$CONFIG_FILE" > "$config_tmp" ||
        ! "$BIN_FILE" check -c "$config_tmp"; then
        rm -f "$config_tmp"
        red "配置生成或校验失败，原配置未修改。"
        return 1
    fi
    if ! cp -p "$CONFIG_FILE" "${CONFIG_FILE}.bak" ||
        ! chmod 600 "$config_tmp" "${CONFIG_FILE}.bak" || ! mv "$config_tmp" "$CONFIG_FILE"; then
        rm -f "$config_tmp"
        red "保存配置失败。"
        return 1
    fi
}

normalize_port() {
    case "$1" in ''|*[!0-9]*) red "端口必须是 1–65535 的整数。" >&2; return 1 ;; esac
    normalized_port=$(printf '%s' "$1" | sed 's/^0*//')
    if [ -z "$normalized_port" ] || [ "${#normalized_port}" -gt 5 ] ||
        [ "$normalized_port" -gt 65535 ]; then
        red "端口必须是 1–65535 的整数。" >&2
        return 1
    fi
    printf '%s\n' "$normalized_port"
}

check_port() {
    if jq -e --arg tag "$2" --argjson port "$1" \
        'any(.inbounds[]; .tag != $tag and .listen_port == $port)' "$CONFIG_FILE" >/dev/null; then
        red "端口 $1 已被其他入站节点使用。"; return 1
    fi
    if jq -e --arg tag "$2" --argjson port "$1" \
        'any(.inbounds[]; .tag == $tag and .listen_port == $port)' "$CONFIG_FILE" >/dev/null; then
        return 0
    fi
    port_listeners=$(ss -H -ltn "sport = :$1") || return 1
    [ -z "$port_listeners" ] || { red "TCP 端口 $1 已被其他程序监听。"; return 1; }
}

validate_sni() {
    printf '%s\n' "$1" | awk '
        length($0) > 253 || $0 !~ /^[A-Za-z0-9.-]+$/ { exit 1 }
        {
            label_count = split($0, labels, ".")
            for (label_index = 1; label_index <= label_count; label_index++) {
                if (length(labels[label_index]) < 1 || length(labels[label_index]) > 63 ||
                    labels[label_index] ~ /^-/ || labels[label_index] ~ /-$/) exit 1
            }
        }' || { red "请输入有效的 SNI 域名，不含 https://、路径或端口。"; return 1; }
}

add_vless() {
    init_env || return 1
    yellow ">>> 配置 VLESS-Reality 节点（重设会更新 UUID 和密钥）"
    prompt "请输入 Reality 端口号 [默认: 8443]：" port || return 1
    port=$(normalize_port "${port:-8443}") || return 1
    check_port "$port" "vless-in" || return 1
    prompt "请输入 SNI / 握手域名 [默认: www.microsoft.com]：" dest_server || return 1
    dest_server=${dest_server:-www.microsoft.com}
    validate_sni "$dest_server" || return 1

    real_uuid=$(cat /proc/sys/kernel/random/uuid) || return 1
    reality_keys=$("$BIN_FILE" generate reality-keypair) || return 1
    private_key=$(printf '%s\n' "$reality_keys" | awk '/^PrivateKey:/ {print $2}')
    public_key=$(printf '%s\n' "$reality_keys" | awk '/^PublicKey:/ {print $2}')
    short_id=$(xxd -p -l 8 /dev/urandom) || return 1
    [ -n "$private_key" ] && [ -n "$public_key" ] && [ "${#short_id}" -eq 16 ] || {
        red "Reality 密钥生成失败。"; return 1;
    }
    if [ -f "$PUB_KEY_FILE" ]; then
        cp -p "$PUB_KEY_FILE" "${PUB_KEY_FILE}.bak" || return 1
    fi
    save_config '(.inbounds |= map(select(.tag != "vless-in"))) | .inbounds += [{
        "type": "vless", "tag": "vless-in", "listen": "0.0.0.0", "listen_port": $port,
        "users": [{"uuid": $uuid, "flow": "xtls-rprx-vision"}],
        "tls": {"enabled": true, "server_name": $sni,
            "reality": {"enabled": true, "handshake": {"server": $sni, "server_port": 443},
                "private_key": $private, "short_id": [$sid]}}
    }]' --argjson port "$port" --arg uuid "$real_uuid" --arg sni "$dest_server" \
        --arg private "$private_key" --arg sid "$short_id" || return 1
    printf '%s\n' "$public_key" > "$PUB_KEY_FILE" && chmod 600 "$PUB_KEY_FILE" || return 1
    green "VLESS-Reality 配置已保存。"
    restart_service && show_links
}

add_socks5() {
    init_env || return 1
    yellow ">>> 配置 SOCKS5 节点"
    prompt "请输入 SOCKS5 端口号 [默认: 10808]：" socks_port || return 1
    socks_port=$(normalize_port "${socks_port:-10808}") || return 1
    check_port "$socks_port" "socks-in" || return 1
    default_user="user_$(xxd -p -l 2 /dev/urandom)"
    default_pass=$(xxd -p -l 6 /dev/urandom) || return 1
    prompt "请输入 SOCKS5 用户名 [默认随机: ${default_user}]：" socks_user || return 1
    socks_user=${socks_user:-$default_user}
    prompt "请输入 SOCKS5 密码 [回车随机生成]：" socks_pass || return 1
    socks_pass=${socks_pass:-$default_pass}
    save_config '(.inbounds |= map(select(.tag != "socks-in"))) | .inbounds += [{
        "type": "socks", "tag": "socks-in", "listen": "0.0.0.0", "listen_port": $port,
        "users": [{"username": $user, "password": $pass}]
    }]' --argjson port "$socks_port" --arg user "$socks_user" --arg pass "$socks_pass" || return 1
    green "SOCKS5 配置已保存。"
    restart_service && show_links
}

modify_protocol() {
    require_config || return 1
    case "${1:-}" in
        vless) mod_num=1 ;;
        socks5) mod_num=2 ;;
        keys) mod_num=3 ;;
        *)
            printf '%s\n' "1. 修改 VLESS-Reality 端口 / SNI（保留 UUID 和密钥）" \
                "2. 修改 SOCKS5 端口 / 用户名 / 密码" "3. 重设 VLESS-Reality（更新 UUID 和全部密钥）" "0. 返回"
            prompt "请输入选项 [0-3]：" mod_num || return 1
            ;;
    esac
    case "$mod_num" in
        1)
            jq -e 'any(.inbounds[]; .tag == "vless-in")' "$CONFIG_FILE" >/dev/null || {
                red "未安装 VLESS-Reality，请先添加。"; return 1;
            }
            cur_port=$(jq -r '.inbounds[] | select(.tag == "vless-in") | .listen_port' "$CONFIG_FILE")
            cur_sni=$(jq -r '.inbounds[] | select(.tag == "vless-in") | .tls.server_name' "$CONFIG_FILE")
            prompt "请输入新端口 [当前: ${cur_port}，回车保持不变]：" new_port || return 1
            new_port=$(normalize_port "${new_port:-$cur_port}") || return 1
            check_port "$new_port" "vless-in" || return 1
            prompt "请输入新 SNI [当前: ${cur_sni}，回车保持不变]：" new_sni || return 1
            new_sni=${new_sni:-$cur_sni}
            validate_sni "$new_sni" || return 1
            save_config '(.inbounds[] | select(.tag == "vless-in")) |= (
                .listen_port = $port | .tls.server_name = $sni | .tls.reality.handshake.server = $sni
            )' --argjson port "$new_port" --arg sni "$new_sni" || return 1
            ;;
        2)
            jq -e 'any(.inbounds[]; .tag == "socks-in")' "$CONFIG_FILE" >/dev/null || {
                red "未安装 SOCKS5，请先添加。"; return 1;
            }
            cur_port=$(jq -r '.inbounds[] | select(.tag == "socks-in") | .listen_port' "$CONFIG_FILE")
            cur_user=$(jq -r '.inbounds[] | select(.tag == "socks-in") | .users[0].username' "$CONFIG_FILE")
            cur_pass=$(jq -r '.inbounds[] | select(.tag == "socks-in") | .users[0].password' "$CONFIG_FILE")
            prompt "请输入新端口 [当前: ${cur_port}，回车保持不变]：" new_port || return 1
            new_port=$(normalize_port "${new_port:-$cur_port}") || return 1
            check_port "$new_port" "socks-in" || return 1
            prompt "请输入新用户名 [当前: ${cur_user}，回车保持不变]：" new_user || return 1
            new_user=${new_user:-$cur_user}
            prompt "请输入新密码 [回车保持不变]：" new_pass || return 1
            new_pass=${new_pass:-$cur_pass}
            save_config '(.inbounds[] | select(.tag == "socks-in")) |= (
                .listen_port = $port | .users[0].username = $user | .users[0].password = $pass
            )' --argjson port "$new_port" --arg user "$new_user" --arg pass "$new_pass" || return 1
            ;;
        3) add_vless; return $? ;;
        0) return 0 ;;
        *) red "输入无效。"; return 1 ;;
    esac
    green "配置已修改并保存。"
    restart_service && show_links
}

delete_protocol() {
    require_config || return 1
    case "${1:-}" in
        vless) del_num=1 ;;
        socks5) del_num=2 ;;
        all) del_num=3 ;;
        *)
            printf '%s\n' "1. 删除 VLESS-Reality" "2. 删除 SOCKS5" "3. 清空所有协议节点" "0. 返回"
            prompt "请输入选项 [0-3]：" del_num || return 1
            ;;
    esac
    case "$del_num" in
        1|3)
            if [ -f "$PUB_KEY_FILE" ]; then
                cp -p "$PUB_KEY_FILE" "${PUB_KEY_FILE}.bak" || return 1
            fi
            if [ "$del_num" = "1" ]; then
                save_config '.inbounds |= map(select(.tag != "vless-in"))' || return 1
            else
                save_config '.inbounds = []' || return 1
            fi
            rm -f "$PUB_KEY_FILE"
            ;;
        2) save_config '.inbounds |= map(select(.tag != "socks-in"))' || return 1 ;;
        0) return 0 ;;
        *) red "输入无效。"; return 1 ;;
    esac
    rm -f "$LINK_FILE"
    green "所选协议节点已删除，修改前配置已备份。"
    restart_service && show_links
}

urlencode() {
    jq -rn --arg value "$1" '$value | @uri'
}

show_links() {
    require_config || return 1
    if [ "$(jq '.inbounds | length' "$CONFIG_FILE")" -eq 0 ]; then
        rm -f "$LINK_FILE"
        yellow "当前未配置任何协议节点。"
        return 0
    fi
    server_ip=$(wget -4 -qO- -T 10 -t 1 https://ipv4.icanhazip.com ||
        wget -4 -qO- -T 10 -t 1 https://api.ipify.org) || {
        red "公网 IPv4 获取失败，现有分享链接文件保持不变：$LINK_FILE"; return 1;
    }
    server_ip=$(printf '%s' "$server_ip" | tr -d '\r\n')
    printf '%s\n' "$server_ip" | awk -F. '
        NF != 4 { exit 1 }
        { for (octet_index = 1; octet_index <= NF; octet_index++)
            if ($octet_index !~ /^[0-9]+$/ || $octet_index > 255) exit 1 }' || {
        red "获取的公网 IPv4 无效，现有分享链接文件保持不变。"; return 1;
    }
    link_tmp=$(mktemp "${LINK_FILE}.XXXXXX") || return 1
    printf '%s\n' "==========================================" "当前节点配置与分享链接"
    if jq -e 'any(.inbounds[]; .tag == "vless-in")' "$CONFIG_FILE" >/dev/null; then
        v_port=$(jq -r '.inbounds[] | select(.tag == "vless-in") | .listen_port' "$CONFIG_FILE")
        v_uuid=$(jq -r '.inbounds[] | select(.tag == "vless-in") | .users[0].uuid' "$CONFIG_FILE")
        v_sni=$(jq -r '.inbounds[] | select(.tag == "vless-in") | .tls.server_name' "$CONFIG_FILE")
        v_sid=$(jq -r '.inbounds[] | select(.tag == "vless-in") | .tls.reality.short_id[0]' "$CONFIG_FILE")
        v_pub=$(cat "$PUB_KEY_FILE" 2>/dev/null)
        if [ -z "$v_pub" ]; then
            rm -f "$link_tmp"
            red "缺少 Reality 公钥：$PUB_KEY_FILE，请恢复备份或执行 sb modify keys 重设节点。"
            return 1
        fi
        vless_link="vless://${v_uuid}@${server_ip}:${v_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$(urlencode "$v_sni")&fp=chrome&pbk=$(urlencode "$v_pub")&sid=${v_sid}&type=tcp&headerType=none#kkkbox-64M-VLESS"
        printf '%s\n' "$vless_link" >> "$link_tmp"
        green "【VLESS-Reality 分享链接】"
        printf '%s\n' "$vless_link"
    fi
    if jq -e 'any(.inbounds[]; .tag == "socks-in")' "$CONFIG_FILE" >/dev/null; then
        s_port=$(jq -r '.inbounds[] | select(.tag == "socks-in") | .listen_port' "$CONFIG_FILE")
        s_user=$(jq -r '.inbounds[] | select(.tag == "socks-in") | .users[0].username' "$CONFIG_FILE")
        s_pass=$(jq -r '.inbounds[] | select(.tag == "socks-in") | .users[0].password' "$CONFIG_FILE")
        encoded_user=$(urlencode "$s_user")
        encoded_pass=$(urlencode "$s_pass")
        socks_link="socks5://${encoded_user}:${encoded_pass}@${server_ip}:${s_port}#kkkbox-64M-SOCKS5"
        telegram_link="https://t.me/socks?server=${server_ip}&port=${s_port}&user=${encoded_user}&pass=${encoded_pass}"
        printf '%s\n' "$socks_link" "$telegram_link" >> "$link_tmp"
        green "【SOCKS5 节点信息】"
        printf '地址: %s | 端口: %s | 用户: %s | 密码: %s\n' "$server_ip" "$s_port" "$s_user" "$s_pass"
        printf '%s\n' "$socks_link" "$telegram_link"
    fi
    chmod 600 "$link_tmp" && mv "$link_tmp" "$LINK_FILE" || { rm -f "$link_tmp"; return 1; }
    yellow "分享链接已保存至 $LINK_FILE"
}

main_menu() {
    while true; do
        printf '\n%s\n' "==========================================" \
            "kkkbox sing-box 64M VPS 管理脚本 ($PLATFORM)" \
            "==========================================" \
            "1. 添加/重设 VLESS-Reality 协议" \
            "2. 添加/重设 SOCKS5 协议" \
            "3. 一键同时安装 VLESS-Reality + SOCKS5" \
            "4. 修改已安装协议配置 (端口/SNI/账号密码)" \
            "5. 删除指定协议节点" \
            "6. 查看当前分享链接与节点信息" \
            "7. 重启 sing-box 服务并查看状态" \
            "8. 查看 sing-box 服务状态" \
            "9. 查看 sb 管理命令帮助" \
            "0. 退出脚本" \
            "=========================================="
        prompt "请输入选项 [0-9]：" choice || return 0
        case "$choice" in
            1) add_vless ;;
            2) add_socks5 ;;
            3) add_vless && add_socks5 ;;
            4) modify_protocol ;;
            5) delete_protocol ;;
            6) show_links ;;
            7) restart_service ;;
            8) service_action status ;;
            9) show_help ;;
            0) return 0 ;;
            *) red "请输入正确的数字 [0-9]。" ;;
        esac
    done
}

show_help() {
    cat <<'HELP_EOF'
用法：sb [命令] [协议]
  sb / sb menu              打开交互式主菜单
  sb add vless              添加/重设 VLESS-Reality（重新生成 UUID 和密钥）
  sb add socks5             添加/重设 SOCKS5
  sb add all                依次添加两个协议
  sb modify                 打开修改菜单
  sb modify vless           修改 VLESS 端口和 SNI，保留 UUID 和密钥
  sb modify socks5          修改 SOCKS5 端口、用户名和密码
  sb modify keys            重设 VLESS-Reality，重新生成 UUID 和密钥
  sb delete [vless|socks5|all] 删除指定协议；不指定协议时打开删除菜单
  sb links                  显示并重新生成分享链接
  sb start / stop / restart  启动 / 停止 / 重启服务
  sb status                 查看服务状态
  sb check                  检查当前 sing-box 配置
  sb help                   查看管理命令帮助
首次运行：以 root 执行 sh install.sh，即注册 /usr/local/bin/sb。
HELP_EOF
}

main() {
    if [ "$#" -gt 2 ]; then
        show_help; return 2
    fi
    case "${1:-menu}:${2:-}" in
        help:|--help:|-h:) show_help; return 0 ;;
        menu:|modify:|delete:|links:|start:|stop:|restart:|status:|check:|\
        add:vless|add:socks5|add:all|modify:vless|modify:socks5|modify:keys|\
        delete:vless|delete:socks5|delete:all) ;;
        *) red "未知命令或协议。"; show_help; return 2 ;;
    esac
    umask 077
    detect_platform && register_manager && install_dependencies || return 1
    if [ -x "$BIN_FILE" ] && [ -f "$CONFIG_FILE" ]; then
        chmod 700 "$WORK_DIR" && chmod 600 "$CONFIG_FILE" || return 1
        ensure_service || return 1
    fi
    case "${1:-menu}" in
        menu) main_menu ;;
        add)
            case "$2" in
                vless) add_vless ;;
                socks5) add_socks5 ;;
                all) add_vless && add_socks5 ;;
            esac
            ;;
        modify) modify_protocol "${2:-}" ;;
        delete) delete_protocol "${2:-}" ;;
        links) show_links ;;
        restart) restart_service ;;
        start)
            require_config && "$BIN_FILE" check -c "$CONFIG_FILE" && service_action start
            ;;
        stop|status) service_action "$1" ;;
        check) require_config && "$BIN_FILE" check -c "$CONFIG_FILE" ;;
    esac
}

main "$@"
