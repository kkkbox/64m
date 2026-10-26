#!/bin/sh


red() { echo -e "\033[31m\033[01m$1\033[0m"; }
green() { echo -e "\033[32m\033[01m$1\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$1\033[0m"; }


WORK_DIR="/root/singbox"
CONFIG_FILE="${WORK_DIR}/config.json"
BIN_FILE="${WORK_DIR}/sing-box"
PUB_KEY_FILE="${WORK_DIR}/vless_pub.key"
LINK_FILE="${WORK_DIR}/share-link.txt"
FORWARDING_FILE="${WORK_DIR}/forwarding.json"


# 1. 基础环境与 Sing-box 初始化检查
init_env() {
    # 自动创建 128M Swap 防止小内存 OOM
    swap_size=$(free -m | awk '/Swap/ {print $2}')
    if [ "$swap_size" = "0" ]; then
        yellow "检测到无 Swap，正在临时创建 128MB 虚拟内存..."
        dd if=/dev/zero of=/swapfile bs=1M count=128 status=none
        chmod 600 /swapfile
        mkswap /swapfile >/dev/null 2>&1
        swapon /swapfile >/dev/null 2>&1
        green "Swap 创建成功！"
    fi


    # 安装必要依赖 (Alpine使用apk)
    if ! command -v jq >/dev/null 2>&1 || ! command -v xxd >/dev/null 2>&1; then
        echo "正在安装必要依赖..."
        apk update >/dev/null 2>&1
        apk add wget tar gcompat jq ncdu xxd >/dev/null 2>&1
    fi


    mkdir -p "$WORK_DIR"


    # 检查并下载 sing-box
    if [ ! -f "$BIN_FILE" ]; then
        echo "正在获取 sing-box 最新版本号..."
        last_version=$(wget -qO- https://api.github.com/repos/SagerNet/sing-box/releases | grep -m1 '"tag_name":' | cut -d '"' -f 4)
        [ -z "$last_version" ] && { red "获取版本号失败！"; exit 1; }


        file_version=$(echo "$last_version" | sed 's/^v//')


        arch=$(uname -m)
        if [ "$arch" = "x86_64" ] || [ "$arch" = "amd64" ]; then
            box_arch="amd64"
        elif [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ]; then
            box_arch="arm64"
        else
            box_arch="386"
        fi


        download_url="https://github.com/SagerNet/sing-box/releases/download/${last_version}/sing-box-${file_version}-linux-${box_arch}.tar.gz"
        yellow "开始下载 sing-box (${box_arch})..."
        wget "$download_url" -O sing-box.tar.gz


        tar -xzf sing-box.tar.gz
        mv "sing-box-${file_version}-linux-${box_arch}/sing-box" "$WORK_DIR/"
        chmod +x "$BIN_FILE"
        rm -rf sing-box.tar.gz "sing-box-${file_version}-linux-${box_arch}"
        green "sing-box 核心下载完成！"
    fi


    # 初始化空白基础配置
    if [ ! -f "$CONFIG_FILE" ]; then
        cat << 'JSON_EOF' > "$CONFIG_FILE"
{
  "log": {
    "disabled": true,
    "level": "fatal"
  },
  "inbounds": [],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
JSON_EOF
    fi


    # 写入 OpenRC 服务并调优内存墙
    if [ ! -f "/etc/init.d/sing-box" ]; then
        cat << 'SVC_EOF' > /etc/init.d/sing-box
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
SVC_EOF
        chmod u+x /etc/init.d/sing-box
        rc-update -q add sing-box default
    fi


    # 注册快捷管理命令 sb
    if [ "$0" != "/usr/local/bin/sb" ]; then
        cp -f "$0" /usr/local/bin/sb 2>/dev/null && chmod +x /usr/local/bin/sb
    fi
}


# 2. 重启服务并检查状态
restart_service() {
    inbound_count=$(jq '.inbounds | length' "$CONFIG_FILE")
    if [ "$inbound_count" -eq 0 ]; then
        yellow "当前未配置任何入站协议，停止 sing-box 服务..."
        service sing-box stop >/dev/null 2>&1
    else
        service sing-box restart
        sleep 1
        service sing-box status
    fi
}


# 3. 添加或重置 VLESS-Reality
add_vless() {
    init_env
    echo "------------------------------------------"
    yellow ">>> 配置 VLESS-Reality 节点"
    read -p "请输入 Reality 端口号 [默认: 8443]：" port
    [ -z "$port" ] && port=8443


    read -p "请输入自定义 SNI / 回落域名 [默认: www.microsoft.com]：" DEST_SERVER
    [ -z "$DEST_SERVER" ] && DEST_SERVER="www.microsoft.com"


    REAL_UUID=$(cat /proc/sys/kernel/random/uuid)
    KEYS=$("$BIN_FILE" generate reality-keypair)
    PRI_KEY=$(echo "$KEYS" | grep PrivateKey | awk '{print $2}')
    PUB_KEY=$(echo "$KEYS" | grep PublicKey | awk '{print $2}')
    SHORT_ID=$(dd bs=4 count=2 if=/dev/urandom 2>/dev/null | xxd -p -c 8)


    echo "$PUB_KEY" > "$PUB_KEY_FILE"


    # 先清理旧的 vless-in，再写入新配置
    tmp_json=$(mktemp)
    jq --argjson port "$port" \
       --arg uuid "$REAL_UUID" \
       --arg sni "$DEST_SERVER" \
       --arg pri "$PRI_KEY" \
       --arg sid "$SHORT_ID" \
       '(.inbounds |= map(select(.tag != "vless-in"))) | .inbounds += [{
          "type": "vless",
          "tag": "vless-in",
          "listen": "0.0.0.0",
          "listen_port": $port,
          "users": [{ "uuid": $uuid, "flow": "xtls-rprx-vision" }],
          "tls": {
            "enabled": true,
            "server_name": $sni,
            "reality": {
              "enabled": true,
              "handshake": { "server": $sni, "server_port": 443 },
              "private_key": $pri,
              "short_id": [$sid]
            }
          }
       }]' "$CONFIG_FILE" > "$tmp_json" && mv "$tmp_json" "$CONFIG_FILE"


    green "VLESS-Reality 协议添加/更新成功！"
    restart_service
    show_links
}


# 4. 添加或重置 SOCKS5
add_socks5() {
    init_env
    echo "------------------------------------------"
    yellow ">>> 配置 SOCKS5 节点"
    read -p "请输入 SOCKS5 端口号 [默认: 10808]：" s_port
    [ -z "$s_port" ] && s_port=10808


    default_user="user_$(dd bs=2 count=1 if=/dev/urandom 2>/dev/null | xxd -p)"
    default_pass=$(dd bs=6 count=1 if=/dev/urandom 2>/dev/null | xxd -p)


    read -p "请输入 SOCKS5 用户名 [默认随机: ${default_user}]：" s_user
    [ -z "$s_user" ] && s_user="$default_user"


    read -p "请输入 SOCKS5 密码 [默认随机: ${default_pass}]：" s_pass
    [ -z "$s_pass" ] && s_pass="$default_pass"


    tmp_json=$(mktemp)
    jq --argjson port "$s_port" \
       --arg user "$s_user" \
       --arg pass "$s_pass" \
       '(.inbounds |= map(select(.tag != "socks-in"))) | .inbounds += [{
          "type": "socks",
          "tag": "socks-in",
          "listen": "0.0.0.0",
          "listen_port": $port,
          "users": [{ "username": $user, "password": $pass }]
       }]' "$CONFIG_FILE" > "$tmp_json" && mv "$tmp_json" "$CONFIG_FILE"


    green "SOCKS5 协议添加/更新成功！"
    restart_service
    show_links
}


ensure_forwarding_file() {
    if [ ! -f "$FORWARDING_FILE" ]; then
        legacy_outbound=$(jq -c '.outbounds[]? | select(.tag == "relay-out")' "$CONFIG_FILE" 2>/dev/null)
        umask 077
        if [ -n "$legacy_outbound" ]; then
            legacy_outbound=$(printf '%s\n' "$legacy_outbound" | jq -c '.tag = "forward-1"')
            legacy_enabled=$(jq -r 'any(.route.rules[]?; .outbound == "relay-out")' "$CONFIG_FILE")
            jq -n \
                --argjson outbound "$legacy_outbound" \
                --argjson enabled "$legacy_enabled" \
                '{
                    "enabled": $enabled,
                    "default_id": 1,
                    "profiles": [{
                        "id": 1,
                        "name": "已存在的转发配置",
                        "outbound": $outbound
                    }]
                }' > "$FORWARDING_FILE"
        else
            printf '%s\n' '{"enabled":false,"default_id":null,"profiles":[]}' > "$FORWARDING_FILE"
        fi
    fi
}

forwarding_prompt_outbound() {
    profile_id="$1"
    echo "请选择出口协议："
    echo "1. VLESS-Reality"
    echo "2. SOCKS5"
    read -p "请输入选项 [1-2]：" relay_type

    case "$relay_type" in
        1)
            read -p "请输入目标 VPS 地址或域名：" relay_server
            read -p "请输入目标 VLESS 端口：" relay_port
            read -p "请输入目标 VLESS UUID：" relay_uuid
            read -p "请输入目标 Reality SNI：" relay_sni
            read -p "请输入目标 Reality 公钥：" relay_public_key
            read -p "请输入目标 Reality Short ID：" relay_short_id
            read -p "请输入流控 [默认: xtls-rprx-vision]：" relay_flow
            [ -z "$relay_flow" ] && relay_flow="xtls-rprx-vision"
            if [ -z "$relay_server" ] || [ -z "$relay_port" ] || [ -z "$relay_uuid" ] || \
                [ -z "$relay_sni" ] || [ -z "$relay_public_key" ] || [ -z "$relay_short_id" ]; then
                red "目标 VLESS 参数不能为空！"
                return 1
            fi
            ;;
        2)
            read -p "请输入目标 VPS 地址或域名：" relay_server
            read -p "请输入目标 SOCKS5 端口：" relay_port
            read -p "请输入目标 SOCKS5 用户名 (无认证则留空)：" relay_user
            read -s -p "请输入目标 SOCKS5 密码 (无认证则留空)：" relay_pass
            echo ""
            if [ -z "$relay_server" ] || [ -z "$relay_port" ]; then
                red "目标地址和端口不能为空！"
                return 1
            fi
            if { [ -n "$relay_user" ] && [ -z "$relay_pass" ]; } || \
                { [ -z "$relay_user" ] && [ -n "$relay_pass" ]; }; then
                red "SOCKS5 用户名和密码必须同时填写，或同时留空。"
                return 1
            fi
            ;;
        *)
            red "输入无效！"
            return 1
            ;;
    esac

    case "$relay_port" in *[!0-9]*|'') red "端口必须是 1-65535 的数字！"; return 1 ;; esac
    if [ "$relay_port" -lt 1 ] || [ "$relay_port" -gt 65535 ]; then
        red "端口必须是 1-65535 的数字！"
        return 1
    fi

    if [ "$relay_type" = "1" ]; then
        relay_outbound=$(jq -n \
            --arg tag "forward-${profile_id}" \
            --arg server "$relay_server" \
            --argjson port "$relay_port" \
            --arg uuid "$relay_uuid" \
            --arg flow "$relay_flow" \
            --arg sni "$relay_sni" \
            --arg public_key "$relay_public_key" \
            --arg short_id "$relay_short_id" \
            '{
                "type": "vless",
                "tag": $tag,
                "server": $server,
                "server_port": $port,
                "uuid": $uuid,
                "flow": $flow,
                "tls": {
                    "enabled": true,
                    "server_name": $sni,
                    "utls": { "enabled": true, "fingerprint": "chrome" },
                    "reality": {
                        "enabled": true,
                        "public_key": $public_key,
                        "short_id": $short_id
                    }
                }
            }')
    else
        relay_outbound=$(jq -n \
            --arg tag "forward-${profile_id}" \
            --arg server "$relay_server" \
            --argjson port "$relay_port" \
            --arg user "$relay_user" \
            --arg pass "$relay_pass" \
            '{
                "type": "socks",
                "tag": $tag,
                "server": $server,
                "server_port": $port
            } + (if $user == "" then {} else {
                "username": $user,
                "password": $pass
            } end)')
    fi
}

forwarding_commit() {
    state_candidate="$1"
    config_candidate=$(mktemp)
    if jq --slurpfile forwarding "$state_candidate" \
       '(.outbounds = (((.outbounds // []) | map(select(
            ((.tag // "") != "relay-out") and
            (((.tag // "") | startswith("forward-")) | not)
        ))) + ($forwarding[0].profiles | map(.outbound)))) |
        .route = (.route // {}) |
        .route.rules = (
            ((.route.rules // []) | map(select(
                .inbound != ["vless-in", "socks-in"] or
                (((.outbound // "") != "relay-out") and
                 (((.outbound // "") | startswith("forward-")) | not))
            ))) as $existing |
            if $forwarding[0].enabled and $forwarding[0].default_id != null then
                ([{
                    "inbound": ["vless-in", "socks-in"],
                    "action": "route",
                    "outbound": (
                        $forwarding[0].profiles |
                        map(select(.id == $forwarding[0].default_id)) |
                        .[0].outbound.tag
                    )
                }] + $existing)
            else
                $existing
            end
        )' "$CONFIG_FILE" > "$config_candidate"; then
        mv "$config_candidate" "$CONFIG_FILE"
        mv "$state_candidate" "$FORWARDING_FILE"
        restart_service
    else
        rm -f "$config_candidate" "$state_candidate"
        red "转发配置写入失败，未应用更改。"
        return 1
    fi
}

forwarding_list() {
    ensure_forwarding_file
    echo "------------------------------------------"
    if [ "$(jq '.profiles | length' "$FORWARDING_FILE")" -eq 0 ]; then
        yellow "转发列表为空。"
    else
        jq -r '
            . as $state |
            "转发状态: \(if $state.enabled then "开启" else "关闭" end)",
            "默认出口 ID: \(if $state.default_id == null then "未设置" else ($state.default_id|tostring) end)",
            (.profiles[] |
                "ID: \(.id) \(if .id == $state.default_id then "[默认]" else "" end) | \(.name) | \(.outbound.type) | \(.outbound.server):\(.outbound.server_port)")
        ' "$FORWARDING_FILE"
    fi
    echo "------------------------------------------"
}

forwarding_add() {
    ensure_forwarding_file
    profile_id=$(jq '([.profiles[].id] | max // 0) + 1' "$FORWARDING_FILE")
    read -p "请输入转发配置名称：" profile_name
    [ -z "$profile_name" ] && { red "名称不能为空！"; return; }
    forwarding_prompt_outbound "$profile_id" || return
    profile=$(jq -n \
        --argjson id "$profile_id" \
        --arg name "$profile_name" \
        --argjson outbound "$relay_outbound" \
        '{id:$id,name:$name,outbound:$outbound}')
    state_candidate=$(mktemp)
    if jq --argjson profile "$profile" \
       '(.profiles += [$profile]) |
        if .default_id == null then .default_id = $profile.id else . end |
        if (.profiles | length) == 1 then .enabled = true else . end' \
       "$FORWARDING_FILE" > "$state_candidate"; then
        forwarding_commit "$state_candidate" &&
            green "转发配置已新增，ID: ${profile_id}。"
    else
        rm -f "$state_candidate"
        red "新增转发配置失败。"
    fi
}

forwarding_edit() {
    ensure_forwarding_file
    forwarding_list
    read -p "请输入要编辑的配置 ID：" profile_id
    case "$profile_id" in *[!0-9]*|'') red "ID 必须是数字！"; return ;; esac
    if [ "$(jq --argjson id "$profile_id" '[.profiles[] | select(.id == $id)] | length' "$FORWARDING_FILE")" -eq 0 ]; then
        red "找不到该转发配置。"
        return
    fi
    read -p "请输入新的配置名称：" profile_name
    [ -z "$profile_name" ] && { red "名称不能为空！"; return; }
    forwarding_prompt_outbound "$profile_id" || return
    profile=$(jq -n \
        --argjson id "$profile_id" \
        --arg name "$profile_name" \
        --argjson outbound "$relay_outbound" \
        '{id:$id,name:$name,outbound:$outbound}')
    state_candidate=$(mktemp)
    if jq --argjson profile "$profile" \
       '(.profiles[] | select(.id == $profile.id)) |= $profile' \
       "$FORWARDING_FILE" > "$state_candidate"; then
        forwarding_commit "$state_candidate" &&
            green "转发配置已更新。"
    else
        rm -f "$state_candidate"
        red "编辑转发配置失败。"
    fi
}

forwarding_toggle() {
    ensure_forwarding_file
    if [ "$(jq '.profiles | length' "$FORWARDING_FILE")" -eq 0 ]; then
        red "请先新增转发配置。"
        return
    fi
    state_candidate=$(mktemp)
    if jq 'if .enabled then .enabled = false else .enabled = true end' \
       "$FORWARDING_FILE" > "$state_candidate"; then
        forwarding_commit "$state_candidate" &&
            green "流量转发状态已切换。"
    else
        rm -f "$state_candidate"
        red "切换转发状态失败。"
    fi
}

forwarding_set_default() {
    ensure_forwarding_file
    forwarding_list
    read -p "请输入默认出口配置 ID：" profile_id
    case "$profile_id" in *[!0-9]*|'') red "ID 必须是数字！"; return ;; esac
    if [ "$(jq --argjson id "$profile_id" '[.profiles[] | select(.id == $id)] | length' "$FORWARDING_FILE")" -eq 0 ]; then
        red "找不到该转发配置。"
        return
    fi
    state_candidate=$(mktemp)
    if jq --argjson id "$profile_id" '.default_id = $id' \
       "$FORWARDING_FILE" > "$state_candidate"; then
        forwarding_commit "$state_candidate" &&
            green "默认出口已切换为 ID ${profile_id}。"
    else
        rm -f "$state_candidate"
        red "设置默认出口失败。"
    fi
}

forwarding_delete() {
    ensure_forwarding_file
    forwarding_list
    read -p "请输入要删除的配置 ID：" profile_id
    case "$profile_id" in *[!0-9]*|'') red "ID 必须是数字！"; return ;; esac
    if [ "$(jq --argjson id "$profile_id" '[.profiles[] | select(.id == $id)] | length' "$FORWARDING_FILE")" -eq 0 ]; then
        red "找不到该转发配置。"
        return
    fi
    state_candidate=$(mktemp)
    if jq --argjson id "$profile_id" \
       '(.profiles |= map(select(.id != $id))) |
        if .default_id == $id then
            .default_id = (.profiles[0].id // null)
        else . end |
        if (.profiles | length) == 0 then .enabled = false else . end' \
       "$FORWARDING_FILE" > "$state_candidate"; then
        forwarding_commit "$state_candidate" &&
            green "转发配置已删除。"
    else
        rm -f "$state_candidate"
        red "删除转发配置失败。"
    fi
}

configure_forwarding() {
    [ ! -f "$CONFIG_FILE" ] && { red "尚未安装配置！"; return; }
    ensure_forwarding_file
    while true; do
        echo "------------------------------------------"
        echo "转发管理："
        echo "1. 新增转发配置"
        echo "2. 编辑转发配置"
        echo "3. 关闭/恢复流量转发"
        echo "4. 查看转发列表"
        echo "5. 设置默认出口"
        echo "6. 删除转发配置"
        echo "0. 返回主菜单"
        read -p "请输入选项 [0-6]：" relay_action
        case "$relay_action" in
            1) forwarding_add ;;
            2) forwarding_edit ;;
            3) forwarding_toggle ;;
            4) forwarding_list ;;
            5) forwarding_set_default ;;
            6) forwarding_delete ;;
            0) return ;;
            *) red "输入无效！" ;;
        esac
    done
}

# 6. 修改现有协议配置
modify_protocol() {
    [ ! -f "$CONFIG_FILE" ] && { red "尚未安装配置！"; return; }
    echo "------------------------------------------"
    echo "请选择要修改的协议："
    echo "1. 修改 VLESS-Reality (端口 / SNI 域名，保留原密钥与UUID)"
    echo "2. 修改 SOCKS5 (端口 / 用户名 / 密码)"
    echo "3. 重新生成 VLESS-Reality 全部密钥与 UUID"
    echo "0. 返回主菜单"
    read -p "请输入选项 [0-3]：" mod_num


    case "$mod_num" in
        1)
            has_vless=$(jq '.inbounds[] | select(.tag=="vless-in")' "$CONFIG_FILE")
            [ -z "$has_vless" ] && { red "当前未安装 VLESS-Reality 节点，请先添加！"; return; }


            cur_port=$(jq -r '.inbounds[] | select(.tag=="vless-in") | .listen_port' "$CONFIG_FILE")
            cur_sni=$(jq -r '.inbounds[] | select(.tag=="vless-in") | .tls.server_name' "$CONFIG_FILE")


            read -p "请输入新端口号 [当前: ${cur_port}，回车保持不变]：" new_port
            [ -z "$new_port" ] && new_port="$cur_port"


            read -p "请输入新 SNI 域名 [当前: ${cur_sni}，回车保持不变]：" new_sni
            [ -z "$new_sni" ] && new_sni="$cur_sni"


            tmp_json=$(mktemp)
            jq --argjson port "$new_port" --arg sni "$new_sni" \
               '(.inbounds[] | select(.tag=="vless-in")) |= (
                   .listen_port = $port |
                   .tls.server_name = $sni |
                   .tls.reality.handshake.server = $sni
               )' "$CONFIG_FILE" > "$tmp_json" && mv "$tmp_json" "$CONFIG_FILE"


            green "VLESS-Reality 修改成功！"
            restart_service
            show_links
            ;;
        2)
            has_socks=$(jq '.inbounds[] | select(.tag=="socks-in")' "$CONFIG_FILE")
            [ -z "$has_socks" ] && { red "当前未安装 SOCKS5 节点，请先添加！"; return; }


            cur_port=$(jq -r '.inbounds[] | select(.tag=="socks-in") | .listen_port' "$CONFIG_FILE")
            cur_user=$(jq -r '.inbounds[] | select(.tag=="socks-in") | .users[0].username' "$CONFIG_FILE")
            cur_pass=$(jq -r '.inbounds[] | select(.tag=="socks-in") | .users[0].password' "$CONFIG_FILE")


            read -p "请输入新端口号 [当前: ${cur_port}，回车保持不变]：" new_port
            [ -z "$new_port" ] && new_port="$cur_port"


            read -p "请输入新用户名 [当前: ${cur_user}，回车保持不变]：" new_user
            [ -z "$new_user" ] && new_user="$cur_user"


            read -p "请输入新密码 [当前: ${cur_pass}，回车保持不变]：" new_pass
            [ -z "$new_pass" ] && new_pass="$cur_pass"


            tmp_json=$(mktemp)
            jq --argjson port "$new_port" --arg user "$new_user" --arg pass "$new_pass" \
               '(.inbounds[] | select(.tag=="socks-in")) |= (
                   .listen_port = $port |
                   .users[0].username = $user |
                   .users[0].password = $pass
               )' "$CONFIG_FILE" > "$tmp_json" && mv "$tmp_json" "$CONFIG_FILE"


            green "SOCKS5 修改成功！"
            restart_service
            show_links
            ;;
        3)
            add_vless
            ;;
        0)
            return
            ;;
        *)
            red "输入无效！"
            ;;
    esac
}


# 6. 删除指定协议
delete_protocol() {
    [ ! -f "$CONFIG_FILE" ] && { red "尚未安装配置！"; return; }
    echo "------------------------------------------"
    echo "请选择要删除的协议："
    echo "1. 删除 VLESS-Reality 节点"
    echo "2. 删除 SOCKS5 节点"
    echo "3. 清空所有协议节点"
    echo "0. 返回主菜单"
    read -p "请输入选项 [0-3]：" del_num


    tmp_json=$(mktemp)
    case "$del_num" in
        1)
            jq 'del(.inbounds[] | select(.tag=="vless-in"))' "$CONFIG_FILE" > "$tmp_json" && mv "$tmp_json" "$CONFIG_FILE"
            rm -f "$PUB_KEY_FILE"
            green "VLESS-Reality 节点已删除！"
            restart_service
            show_links
            ;;
        2)
            jq 'del(.inbounds[] | select(.tag=="socks-in"))' "$CONFIG_FILE" > "$tmp_json" && mv "$tmp_json" "$CONFIG_FILE"
            green "SOCKS5 节点已删除！"
            restart_service
            show_links
            ;;
        3)
            jq '.inbounds = []' "$CONFIG_FILE" > "$tmp_json" && mv "$tmp_json" "$CONFIG_FILE"
            rm -f "$PUB_KEY_FILE" "$LINK_FILE"
            green "所有协议节点已清空！"
            restart_service
            ;;
        0)
            rm -f "$tmp_json"
            return
            ;;
        *)
            rm -f "$tmp_json"
            red "输入无效！"
            ;;
    esac
}


# 7. 生成并打印客户端连接链接
show_links() {
    [ ! -f "$CONFIG_FILE" ] && { red "尚未安装配置！"; return; }
    IP=$(wget -qO- http://ipv4.icanhazip.com || wget -qO- http://ifconfig.me)
    > "$LINK_FILE"


    echo "=========================================="
    echo "           当前节点配置与分享链接         "
    echo "=========================================="


    # 检查 VLESS
    has_vless=$(jq '.inbounds[] | select(.tag=="vless-in")' "$CONFIG_FILE")
    if [ -n "$has_vless" ]; then
        v_port=$(jq -r '.inbounds[] | select(.tag=="vless-in") | .listen_port' "$CONFIG_FILE")
        v_uuid=$(jq -r '.inbounds[] | select(.tag=="vless-in") | .users[0].uuid' "$CONFIG_FILE")
        v_sni=$(jq -r '.inbounds[] | select(.tag=="vless-in") | .tls.server_name' "$CONFIG_FILE")
        v_sid=$(jq -r '.inbounds[] | select(.tag=="vless-in") | .tls.reality.short_id[0]' "$CONFIG_FILE")
        v_pub=$(cat "$PUB_KEY_FILE" 2>/dev/null)


        VLESS_LINK="vless://${v_uuid}@${IP}:${v_port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${v_sni}&fp=chrome&pbk=${v_pub}&sid=${v_sid}&type=tcp&headerType=none#kkkbox-64M-VLESS"
        echo "$VLESS_LINK" >> "$LINK_FILE"
        green "【VLESS-Reality 分享链接】："
        red "$VLESS_LINK"
        echo "------------------------------------------"
    fi


    # 检查 SOCKS5
    has_socks=$(jq '.inbounds[] | select(.tag=="socks-in")' "$CONFIG_FILE")
    if [ -n "$has_socks" ]; then
        s_port=$(jq -r '.inbounds[] | select(.tag=="socks-in") | .listen_port' "$CONFIG_FILE")
        s_user=$(jq -r '.inbounds[] | select(.tag=="socks-in") | .users[0].username' "$CONFIG_FILE")
        s_pass=$(jq -r '.inbounds[] | select(.tag=="socks-in") | .users[0].password' "$CONFIG_FILE")


        SOCKS_LINK="socks5://${s_user}:${s_pass}@${IP}:${s_port}#kkkbox-64M-SOCKS5"
        TG_LINK="https://t.me/socks?server=${IP}&port=${s_port}&user=${s_user}&pass=${s_pass}"
        echo "$SOCKS_LINK" >> "$LINK_FILE"
        echo "$TG_LINK" >> "$LINK_FILE"


        green "【SOCKS5 节点信息】："
        echo "地址: ${IP} | 端口: ${s_port} | 用户: ${s_user} | 密码: ${s_pass}"
        green "【SOCKS5 通用链接】："
        red "$SOCKS_LINK"
        green "【Telegram 快连链接】："
        red "$TG_LINK"
        echo "------------------------------------------"
    fi


    if [ -z "$has_vless" ] && [ -z "$has_socks" ]; then
        yellow "当前未安装任何协议节点，请从主菜单选择添加。"
    else
        yellow "分享链接已自动汇总保存到: ${LINK_FILE}"
        yellow "提示: 以后在终端直接输入 sb 即可随时打开此管理面板！"
    fi
    echo "=========================================="
}


# 8. 主菜单交互
main_menu() {
    while true; do
        echo ""
        echo "=========================================="
        echo "    kkkbox sing-box 64M VPS 管理脚本      "
        echo "=========================================="
        echo "1. 添加/重设 VLESS-Reality 协议"
        echo "2. 添加/重设 SOCKS5 协议"
        echo "3. 一键同时安装 VLESS-Reality + SOCKS5"
        echo "4. 修改已安装协议配置 (端口/SNI/账号密码)"
        echo "5. 删除指定协议节点"
        echo "6. 查看当前分享链接与节点信息"
        echo "7. 重启 sing-box 服务并查看状态"
        echo "8. 配置流量转发到另一台 VPS"
        echo "0. 退出脚本"
        echo "=========================================="
        read -p "请输入选项 [0-8]：" choice


        case "$choice" in
            1) add_vless ;;
            2) add_socks5 ;;
            3) add_vless; add_socks5 ;;
            4) modify_protocol ;;
            5) delete_protocol ;;
            6) show_links ;;
            7) restart_service ;;
            8) configure_forwarding ;;
            0) exit 0 ;;
            *) red "请输入正确的数字 [0-8]！" ;;
        esac
    done
}


main_menu
