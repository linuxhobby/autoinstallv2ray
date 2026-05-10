#!/bin/bash

# ====================================================
# 作者: 人生若只如初见
# 更新：2026/05/10 (将军专用·九协议全量加固版)
# 特性：100% 还原 9 种协议逻辑，强制 IPv4 监听，防 status=23 报错
# ====================================================

# 终端颜色定义
Font_Red="\033[31m"; Font_Green="\033[32m"; Font_Yellow="\033[33m"; 
Font_Blue="\033[34m"; Font_Magenta="\033[35m"; Font_Cyan="\033[36m"; Font_Suffix="\033[0m"

# 全局变量
conf_dir="/usr/local/etc/xray"
config_path="${conf_dir}/config.json"
XRAY_VERSION="26.5.3"

# --- 基础工具 ---
check_root() { [[ $EUID -ne 0 ]] && echo -e "${Font_Red}请以 root 运行${Font_Suffix}" && exit 1; }

get_ip() { echo "$(curl -4 -s ip.sb || curl -4 -s http://ipv4.icanhazip.com || echo "127.0.0.1")"; }

# 核心：写入配置并重启服务
write_config_and_restart() {
    local fragment=$1
    cat <<EOF > "$config_path"
{
    "log": { "loglevel": "warning" },
    "inbounds": [ $fragment ],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF
    chown -R xray:xray "$conf_dir"
    systemctl restart xray
    sleep 1
    if ! systemctl is-active --quiet xray; then
        echo -e "${Font_Red}[ERROR] 协议配置启动失败，请检查日志。${Font_Suffix}"
    fi
}

preparation_stack() {
    apt-get update -qq && apt-get install -y jq curl openssl qrencode vnstat ufw dnsutils -qq
    sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1
    ufw allow 80/tcp && ufw allow 443/tcp && ufw allow 443/udp && ufw allow 10001:10010/tcp
    if ! command -v xray &> /dev/null; then
        bash <(curl -fsSL https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh) install --version ${XRAY_VERSION}
    fi
    mkdir -p "$conf_dir"
}

install_caddy() {
    if ! command -v caddy &> /dev/null; then
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
        apt-get update -qq && apt-get install caddy -y
    fi
    systemctl enable caddy --now || true
}

# --- 协议生成逻辑 1-9 ---

# 【1】. VLESS-REALITY-Vision
gen_v1() {
    local uuid=$(cat /proc/sys/kernel/random/uuid); local sid=$(openssl rand -hex 8)
    local keys=$(xray x25519); local priv=$(echo "$keys" | awk -F': ' '/Private/ {print $2}' | tr -d ' ')
    local pub=$(echo "$keys" | awk -F': ' '/Public/ {print $2}' | tr -d ' ')
    local frag='{"listen":"0.0.0.0","port":443,"protocol":"vless","settings":{"clients":[{"id":"'$uuid'","flow":"xtls-rprx-vision"}],"decryption":"none"},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"show":false,"dest":"www.microsoft.com:443","xver":0,"serverNames":["www.microsoft.com"],"privateKey":"'$priv'","shortIds":["'$sid'"]}}}'
    write_config_and_restart "$frag"
    local link="vless://$uuid@$(get_ip):443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&fp=chrome&pbk=$pub&sid=$sid&type=tcp#V1_Reality_Vision"
    echo -e "${Font_Yellow}$link${Font_Suffix}" && echo "$link" | qrencode -t utf8
}

# 【2】. VLESS-REALITY-xhttp
gen_v2() {
    local uuid=$(cat /proc/sys/kernel/random/uuid); local sid=$(openssl rand -hex 8); local path=$(openssl rand -hex 6)
    local keys=$(xray x25519); local priv=$(echo "$keys" | awk -F': ' '/Private/ {print $2}' | tr -d ' ')
    local pub=$(echo "$keys" | awk -F': ' '/Public/ {print $2}' | tr -d ' ')
    local frag='{"listen":"0.0.0.0","port":443,"protocol":"vless","settings":{"clients":[{"id":"'$uuid'"}],"decryption":"none"},"streamSettings":{"network":"xhttp","security":"reality","xhttpSettings":{"path":"/'$path'"},"realitySettings":{"show":false,"dest":"www.microsoft.com:443","xver":0,"serverNames":["www.microsoft.com"],"privateKey":"'$priv'","shortIds":["'$sid'"]}}}'
    write_config_and_restart "$frag"
    local link="vless://$uuid@$(get_ip):443?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=$pub&sid=$sid&type=xhttp&path=%2F$path#V2_Reality_xhttp"
    echo -e "${Font_Yellow}$link${Font_Suffix}" && echo "$link" | qrencode -t utf8
}

# 【3, 4, 5】. VLESS-TLS (WS, gRPC, XHTTP)
gen_v345() {
    local mode=$1; read -p "请输入域名: " domain; install_caddy
    local uuid=$(cat /proc/sys/kernel/random/uuid); local path=$(openssl rand -hex 6); local port=10001; local frag=""
    case $mode in
        ws) frag='{"port":'$port',"listen":"127.0.0.1","protocol":"vless","settings":{"clients":[{"id":"'$uuid'"}],"decryption":"none"},"streamSettings":{"network":"ws","wsSettings":{"path":"/'$path'"}}}'
           echo "$domain { reverse_proxy /$path 127.0.0.1:$port }" > /etc/caddy/Caddyfile ;;
        grpc) frag='{"port":'$port',"listen":"127.0.0.1","protocol":"vless","settings":{"clients":[{"id":"'$uuid'"}],"decryption":"none"},"streamSettings":{"network":"grpc","grpcSettings":{"serviceName":"'$path'"}}}'
           echo "$domain { reverse_proxy localhost:$port { transport http { versions h2c } } }" > /etc/caddy/Caddyfile ;;
        xhttp) frag='{"port":'$port',"listen":"127.0.0.1","protocol":"vless","settings":{"clients":[{"id":"'$uuid'"}],"decryption":"none"},"streamSettings":{"network":"xhttp","xhttpSettings":{"path":"/'$path'"}}}'
           echo "$domain { reverse_proxy /$path 127.0.0.1:$port }" > /etc/caddy/Caddyfile ;;
    esac
    systemctl restart caddy; write_config_and_restart "$frag"
    local link="vless://$uuid@$domain:443?encryption=none&security=tls&type=$mode&host=$domain&path=%2F$path&serviceName=$path#VLESS_${mode}_TLS"
    echo -e "${Font_Yellow}$link${Font_Suffix}" && echo "$link" | qrencode -t utf8
}

# 【6, 7】. Trojan-TLS (WS, gRPC)
gen_v67() {
    local mode=$1; read -p "请输入域名: " domain; install_caddy
    local pass=$(openssl rand -hex 8); local path=$(openssl rand -hex 6); local port=10004; local frag=""
    if [[ "$mode" == "ws" ]]; then
        frag='{"port":'$port',"listen":"127.0.0.1","protocol":"trojan","settings":{"clients":[{"password":"'$pass'"}]},"streamSettings":{"network":"ws","wsSettings":{"path":"/'$path'"}}}'
        echo "$domain { reverse_proxy /$path 127.0.0.1:$port }" > /etc/caddy/Caddyfile
    else
        frag='{"port":'$port',"listen":"127.0.0.1","protocol":"trojan","settings":{"clients":[{"password":"'$pass'"}]},"streamSettings":{"network":"grpc","grpcSettings":{"serviceName":"'$path'"}}}'
        echo "$domain { reverse_proxy localhost:$port { transport http { versions h2c } } }" > /etc/caddy/Caddyfile
    fi
    systemctl restart caddy; write_config_and_restart "$frag"
    local link="trojan://$pass@$domain:443?security=tls&type=$mode&sni=$domain&path=%2F$path&serviceName=$path#Trojan_${mode}_TLS"
    echo -e "${Font_Yellow}$link${Font_Suffix}" && echo "$link" | qrencode -t utf8
}

# 【8, 9】. VMess-TLS (WS, gRPC)
gen_v89() {
    local mode=$1; read -p "请输入域名: " domain; install_caddy
    local uuid=$(cat /proc/sys/kernel/random/uuid); local path=$(openssl rand -hex 6); local port=10006; local frag=""
    if [[ "$mode" == "ws" ]]; then
        frag='{"port":'$port',"listen":"127.0.0.1","protocol":"vmess","settings":{"clients":[{"id":"'$uuid'"}]},"streamSettings":{"network":"ws","wsSettings":{"path":"/'$path'"}}}'
        echo "$domain { reverse_proxy /$path 127.0.0.1:$port }" > /etc/caddy/Caddyfile
    else
        frag='{"port":'$port',"listen":"127.0.0.1","protocol":"vmess","settings":{"clients":[{"id":"'$uuid'"}]},"streamSettings":{"network":"grpc","grpcSettings":{"serviceName":"'$path'"}}}'
        echo "$domain { reverse_proxy localhost:$port { transport http { versions h2c } } }" > /etc/caddy/Caddyfile
    fi
    systemctl restart caddy; write_config_and_restart "$frag"
    local v_json=$(echo -n "{\"v\":\"2\",\"ps\":\"VMess_${mode}_TLS\",\"add\":\"$domain\",\"port\":\"443\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"$mode\",\"path\":\"/$path\",\"type\":\"none\",\"host\":\"$domain\",\"tls\":\"tls\"}" | base64 -w 0)
    local link="vmess://$v_json"
    echo -e "${Font_Yellow}$link${Font_Suffix}" && echo "$link" | qrencode -t utf8
}

# --- 菜单 ---
main_menu() {
    clear
    echo -e "${Font_Cyan}===========================================================${Font_Suffix}"
    echo -e "   将军阁下，9 种协议完整矩阵 (强制 IPv4 加固版)"
    echo -e "   当前 Xray 状态: $(systemctl is-active xray 2>/dev/null)"
    echo -e "${Font_Cyan}===========================================================${Font_Suffix}"
    echo -e " 【1】. VLESS-REALITY-Vision    【2】. VLESS-REALITY-xhttp"
    echo -e " 【3】. VLESS-WS-TLS            【4】. VLESS-gRPC-TLS"
    echo -e " 【5】. VLESS-XHTTP-TLS         【6】. Trojan-WS-TLS"
    echo -e " 【7】. Trojan-gRPC-TLS         【8】. VMess-WS-TLS"
    echo -e " 【9】. VMess-gRPC-TLS"
    echo -e "-----------------------------------------------------------"
    echo -e " 【D】. 清空配置并卸载  【V】. 流量统计  【Q】. 退出"
    read -p "请下旨选择: " num
    case "$num" in
        1) preparation_stack; gen_v1; read; main_menu ;;
        2) preparation_stack; gen_v2; read; main_menu ;;
        3) preparation_stack; gen_v345 ws; read; main_menu ;;
        4) preparation_stack; gen_v345 grpc; read; main_menu ;;
        5) preparation_stack; gen_v345 xhttp; read; main_menu ;;
        6) preparation_stack; gen_v67 ws; read; main_menu ;;
        7) preparation_stack; gen_v67 grpc; read; main_menu ;;
        8) preparation_stack; gen_v89 ws; read; main_menu ;;
        9) preparation_stack; gen_v89 grpc; read; main_menu ;;
        [Dd]) systemctl stop xray caddy; rm -rf "$conf_dir" /etc/caddy; echo "已清空"; read; main_menu ;;
        [Vv]) vnstat; read; main_menu ;;
        [Qq]) exit 0 ;;
        *) main_menu ;;
    esac
}

check_root; main_menu