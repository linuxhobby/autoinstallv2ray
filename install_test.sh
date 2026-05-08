#!/bin/bash

# ====================================================
# 作者: 人生若只如初见
# 更新：2024/05/07 （优化版 by Grok）
# 支持以下协议矩阵一键自动安装
#  【1】 . 安装 VLESS-REALITY-Vision
#  【2】 . 安装 VLESS-REALITY-xhttp
#  【3】 . 安装 VLESS-WS-TLS
#  【4】 . 安装 VLESS-gRPC-TLS
#  【5】 . 安装 VLESS-XHTTP-TLS
#  【6】 . 安装 Trojan-WS-TLS
#  【7】 . 安装 Trojan-gRPC-TLS
#  【8】 . 安装 VMess-WS-TLS
#  【9】 . 安装 VMess-gRPC-TLS
#   修改功能：
#   2026/05/01：1、域名检测。2、信息查询功能。3、优化菜单。
#   2026/05/02：1、增加二维码展示功能。
#   2026/05/05：1、修复Trojan协议的二维码。2、修复caddy检查安装。
#   2026/05/07：1、增加VLESS-REALITY-xhttp协议。2、修复当前协议判断，更详细。
#   2026/05/08：增加各种验证、排错、去掉apt lock暴力解决，修改安全性配置。
# ====================================================
# ==================== 严格模式 + 错误追踪 ====================
set -euo pipefail
# 捕获错误，打印行号和出错命令
trap 'echo -e "\n${Font_Red}[ERROR] 脚本在第 $LINENO 行执行失败！\n出错命令: $BASH_COMMAND${Font_Suffix}"' ERR
# 终端颜色定义
Font_Black="\033[30m"   # 黑色
Font_Red="\033[31m"     # 红色
Font_Green="\033[32m"   # 绿色
Font_Yellow="\033[33m"  # 黄色
Font_Blue="\033[34m"    # 蓝色
Font_Magenta="\033[35m" # 洋红色/紫色
Font_Cyan="\033[36m"    # 青色
Font_White="\033[37m"   # 白色
Font_Suffix="\033[0m"   # 重置颜色/颜色结尾

# 变量初始化
is_core="xray"
conf_dir="/usr/local/etc/xray"
config_path="${conf_dir}/config.json"
PRESET_DOMAIN="vultr.myvpsworld.top" 
XRAY_VERSION="26.5.3"
CADDY_VERSION="2.8.4"
FIX_VER=1 #1，锁定。0，最新版#
# ==================== Reality 伪装域名配置 ====================
# ==================== Reality 伪装域名配置（随机选择） ====================
REALITY_DEST_OPTIONS=(
    "www.microsoft.com"
    "www.apple.com"
    "www.amazon.com"
    "www.cloudflare.com"
    "login.microsoftonline.com"
    "www.bing.com"
    "account.microsoft.com"
)

# 随机选择函数
get_random_dest() {
    local idx=$((RANDOM % ${#REALITY_DEST_OPTIONS[@]}))
    echo "${REALITY_DEST_OPTIONS[$idx]}"
}
# ==================== 优化新增函数 ====================
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${Font_Red}必须以 root 权限运行此脚本！${Font_Suffix}"
        exit 1
    fi
}

check_command() {
    if ! "$@"; then
        echo -e "${Font_Red}[ERROR] 命令执行失败: $*${Font_Suffix}"
        echo -e "${Font_Red}请查看上方错误信息，脚本已停止执行。${Font_Suffix}"
        journalctl -u xray --no-pager -n 50 2>/dev/null || true
        journalctl -u caddy --no-pager -n 50 2>/dev/null || true
        exit 1
    fi
    return 0
}

setup_xray_user() {
    useradd -r -s /bin/false -U xray 2>/dev/null || true
    mkdir -p "$conf_dir"
    chown -R xray:xray "$conf_dir" 2>/dev/null || true
}

# TLS 类协议公共准备（减少少量重复）
common_tls_setup() {
    check_domain
    install_caddy
    mkdir -p "$conf_dir"
}
# ====================================================

# --- 1. 环境准备模块 ---
preparation_stack() {
    check_root
    setup_xray_user
    
    echo -e "${Font_Cyan}>>> 正在处理 apt 锁...${Font_Suffix}"
    apt-get -o DPkg::Lock::Timeout=180 update --allow-releaseinfo-change -qq || true
    dpkg --configure -a

    echo -e "${Font_Cyan}>>> 配置防火墙...${Font_Suffix}"
    check_command apt-get install -y ufw
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 443/udp
    echo "y" | ufw enable || true

    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

    echo -e "${Font_Cyan}>>> 安装系统依赖...${Font_Suffix}"
    check_command apt-get install -y wget curl socat tar unzip vnstat qrencode gnupg2

    systemctl enable vnstat --now 2>/dev/null || true

    # ==================== Xray 安装 ====================
    if ! command -v xray &> /dev/null || [ ! -f "/etc/systemd/system/xray.service" ]; then
        echo -e "${Font_Cyan}>>> 正在安装 Xray v${XRAY_VERSION}...${Font_Suffix}"
        TMP_SCRIPT=$(mktemp)
        check_command curl -fsSL https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh -o "$TMP_SCRIPT"
        check_command bash "$TMP_SCRIPT" install --version ${XRAY_VERSION}
        rm -f "$TMP_SCRIPT"
        check_command ln -sf /usr/local/bin/xray /usr/bin/xray
        echo -e "${Font_Green}[OK] Xray v${XRAY_VERSION} 安装完成${Font_Suffix}"
    fi

    # 创建 systemd 服务（仅创建，不启动）
    if [ ! -f "/etc/systemd/system/xray.service" ]; then
        cat <<EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
After=network.target nss-lookup.target

[Service]
User=xray
Group=xray
ExecStart=/usr/local/bin/xray run -config ${config_path}
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=${conf_dir}
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
    fi

    systemctl daemon-reload
    systemctl enable xray

    echo -e "${Font_Green}[OK] 环境准备完成（Xray 服务已启用，等待配置生成后启动）${Font_Suffix}"
}

# --- 1.5. Caddy 安装函数（完全保留）---
install_caddy() {
    if ! command -v caddy &> /dev/null; then
        echo -e "${Font_Cyan}正在安装 Caddy v${CADDY_VERSION}...${Font_Suffix}"
        
        rm -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg /etc/apt/sources.list.d/caddy-stable.list

        check_command curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        check_command curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
        
        check_command apt-get update -qq
        check_command apt-get install caddy=${CADDY_VERSION} -y || check_command apt-get install caddy -y

        if [ "$FIX_VER" -eq 1 ] && command -v caddy &> /dev/null; then
            apt-mark hold caddy
        fi

        if ! command -v caddy &> /dev/null; then
            echo -e "${Font_Red}[X] Caddy 安装失败！${Font_Suffix}"
            exit 1
        fi
        echo -e "${Font_Green}[OK] Caddy 安装成功${Font_Suffix}"
    fi
    mkdir -p /etc/caddy
}

# --- 域名解析检测（完全保留）---
check_domain() {
    while true; do
        if [[ -n "$PRESET_DOMAIN" ]]; then
            read -p "请输入您的解析域名后回车 [默认域名: $PRESET_DOMAIN]: " domain
            domain=${domain:-$PRESET_DOMAIN}
        else
            read -p "请输入您的解析域名: " domain
        fi

        if [[ -z "$domain" ]]; then continue; fi

        local local_ipv4=$(curl -4 -s --connect-timeout 5 ip.sb || echo "无")
        local local_ipv6=$(curl -6 -s --connect-timeout 5 ip.sb || echo "无")
        
        local resolved_ips=$(host "$domain" | grep "address" | grep -oP '\d+(\.\d+){3}|([0-9a-fA-F]{1,4}:){1,7}[0-9a-fA-F]{1,4}' | sort -u)
        
        echo -e "${Font_Cyan}本机 IPv4: $local_ipv4${Font_Suffix}"
        echo -e "${Font_Cyan}本机 IPv6: $local_ipv6${Font_Suffix}"
        if [[ -n "$resolved_ips" ]]; then
            echo -e "${Font_Cyan}域名解析地址:${Font_Suffix}\n$resolved_ips"
        else
            echo -e "${Font_Yellow}警告: 未能获取该域名的解析记录。${Font_Suffix}"
        fi

        local pass=0
        for rip in $resolved_ips; do
            if [[ -n "$local_ipv4" && "$rip" == "$local_ipv4" ]] || [[ -n "$local_ipv6" && "$rip" == "$local_ipv6" ]]; then
                pass=1
                break
            fi
        done

        if [[ $pass -eq 1 ]]; then
            echo -e "${Font_Green}检测通过：域名已正确解析到本机 IP。${Font_Suffix}"
            break
        else
            echo -e "${Font_Red}错误: 域名解析地址与本机 IP 不符！${Font_Suffix}"
            echo -e "${Font_Yellow}1. 重新输入 | 2. 强制跳过 (适合已开启 CDN 的域名)${Font_Suffix}"
            read -p "请选择: " retry_choice
            [[ "$retry_choice" == "2" ]] && break
        fi
    done
}

# --- 查看当前协议（完全保留）---
check_current_protocol() {
    if [[ ! -f $config_path ]]; then
        echo -e "${Font_Red}错误: 未检测到配置文件 ($config_path)，请先安装协议。${Font_Suffix}"
        read -p "按回车键返回主菜单"
        return
    fi

    echo -e "${Font_Magenta}--- 当前协议详细信息 ---${Font_Suffix}"
    
    local uuid=$(grep -m1 '"id":' $config_path | grep -oP '(?<="id": ")[^"]+' || grep -m1 '"password":' $config_path | grep -oP '(?<="password": ")[^"]+')
    local network=$(grep -m1 '"network":' $config_path | grep -oP '(?<="network": ")[^"]+')
    
    local ip=$(curl -4 -s --connect-timeout 5 ip.sb || curl -s http://ipv4.icanhazip.com)
    local domain=""
    if [[ -f "/etc/caddy/Caddyfile" ]]; then
        domain=$(grep -oP '^[^#\s{]+' /etc/caddy/Caddyfile | head -n1 | tr -d ' ')
    fi
    [[ -z "$domain" ]] && domain=$(grep -oP '(?<="serverNames": \[")[^"]+' $config_path | head -n1)
    [[ -z "$domain" ]] && domain=$ip

    if grep -q "realitySettings" $config_path; then
        local pub_key=$(cat ${conf_dir}/pub.key 2>/dev/null || echo "未找到公钥文件")
        local short_id=$(grep -m1 '"shortIds":' $config_path | grep -oP '(?<="shortIds": \[").*(?="])' | cut -d'"' -f1)
        local sni=$(grep -m1 '"serverNames":' $config_path | grep -oP '(?<="serverNames": \[").*(?="])' | cut -d'"' -f1)
        show_reality_info "$uuid" "$pub_key" "$short_id" "$sni"
    
    elif [[ "$network" == "ws" ]]; then
        local path=$(grep -m1 '"path":' $config_path | grep -oP '(?<="path": "/)[^"]+')
        if grep -q '"protocol": "trojan"' $config_path; then
            show_trojan_info "ws" "$uuid" "$domain" "$path"
        else
            show_ws_info "$uuid" "$domain" "$path"
        fi

    elif [[ "$network" == "grpc" ]]; then
        local serviceName=$(grep -m1 '"serviceName":' $config_path | grep -oP '(?<="serviceName": ")[^"]+')
        if grep -q '"protocol": "trojan"' $config_path; then
            show_trojan_info "grpc" "$uuid" "$domain" "$serviceName"
        else
            show_grpc_info "$uuid" "$domain" "$serviceName"
        fi

    elif [[ "$network" == "xhttp" ]]; then
        local path=$(grep -m1 '"path":' $config_path | grep -oP '(?<="path": "/)[^"]+')
        show_xhttp_info "$uuid" "$domain" "$path"

    else
        echo -e "${Font_Red}未能识别协议类型。${Font_Suffix}"
    fi
    
    echo -e "${Font_Yellow}-----------------------------------------------${Font_Suffix}"
    read -p "按回车键返回主菜单"
}

# ------------------------------------------------ 核心协议模块 ------------------------------------------------
gen_vless_reality() {
    echo -e "${Font_Cyan}正在配置 VLESS-REALITY-Vision...${Font_Suffix}"
    mkdir -p "$conf_dir"
    
    local xray_bin="/usr/local/bin/xray"
    [[ ! -f "$xray_bin" ]] && xray_bin=$(command -v xray)

    if [ -z "$xray_bin" ]; then
        echo -e "${Font_Red}错误: 未检测到 Xray 核心，请确保执行了环境准备步骤。${Font_Suffix}"
        return 1
    fi

    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local keys=$("$xray_bin" x25519)
    local priv_key=$(echo "$keys" | grep -i "Private" | awk -F': ' '{print $2}' | tr -d ' ')
    local pub_key=$(echo "$keys" | grep -i "Public" | awk -F': ' '{print $2}' | tr -d ' ')
    
    echo "$pub_key" > "${conf_dir}/pub.key"
    
    local dest_server=$(get_random_dest)
    local short_id=$(openssl rand -hex 8)

    echo -e "${Font_Cyan}本次 Reality 伪装站点：${Font_Green}$dest_server${Font_Suffix}"

    cat <<EOF > "$config_path"
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": 443,
        "protocol": "vless",
        "settings": {
            "clients": [{ "id": "$uuid", "flow": "xtls-rprx-vision" }],
            "decryption": "none"
        },
        "streamSettings": {
            "network": "tcp",
            "security": "reality",
            "realitySettings": {
                "show": false,
                "dest": "$dest_server:443",
                "xver": 0,
                "serverNames": ["$dest_server"],
                "privateKey": "$priv_key",
                "shortIds": ["$short_id"]
            }
        }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF

    systemctl daemon-reload
    check_command systemctl restart xray
    
    show_reality_info "$uuid" "$pub_key" "$short_id" "$dest_server"
}

gen_vless_reality_xhttp() {
    echo -e "${Font_Cyan}正在配置 VLESS-REALITY-xhttp...${Font_Suffix}"
    mkdir -p "$conf_dir"
    
    local xray_bin="/usr/local/bin/xray"
    [[ ! -f "$xray_bin" ]] && xray_bin=$(command -v xray)
    
    if [[ -z "$xray_bin" ]]; then
        echo -e "${Font_Red}错误: 未检测到 Xray 核心。${Font_Suffix}"
        return 1
    fi

    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local keys=$("$xray_bin" x25519)
    local priv_key=$(echo "$keys" | grep -i "Private" | awk -F': ' '{print $2}' | tr -d ' ')
    local pub_key=$(echo "$keys" | grep -i "Public" | awk -F': ' '{print $2}' | tr -d ' ')
    local short_id=$(openssl rand -hex 8)
    local path=$(openssl rand -hex 6)
    local dest_server=$(get_random_dest)
    echo -e "${Font_Cyan}本次 Reality 伪装站点：${Font_Green}$dest_server${Font_Suffix}"

    echo "$pub_key" > "${conf_dir}/pub.key"

    cat <<EOF > "$config_path"
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": 443,
        "protocol": "vless",
        "settings": {
            "clients": [{ "id": "$uuid" }],
            "decryption": "none"
        },
        "streamSettings": {
            "network": "xhttp",
            "security": "reality",
            "xhttpSettings": {
                "path": "/$path",
                "mode": "auto"
            },
            "realitySettings": {
                "show": false,
                "dest": "$dest_server:443",
                "xver": 0,
                "serverNames": ["$dest_server"],
                "privateKey": "$priv_key",
                "shortIds": ["$short_id"]
            }
        }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF

    systemctl daemon-reload
    check_command systemctl restart xray
    
    show_reality_xhttp_info "$uuid" "$pub_key" "$short_id" "$dest_server" "$path"
}

# TLS 协议使用 common_tls_setup
gen_vless_ws() {
    common_tls_setup
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local path=$(openssl rand -hex 6)
    local port=10001

    echo -e "${Font_Cyan}正在配置 VLESS-WS-TLS (Caddy 反代)...${Font_Suffix}"

    cat <<EOF > "$config_path"
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": $port, 
        "listen": "127.0.0.1", 
        "protocol": "vless",
        "settings": { 
            "clients": [{ "id": "$uuid" }], 
            "decryption": "none" 
        },
        "streamSettings": { 
            "network": "ws", 
            "wsSettings": { "path": "/$path" } 
        }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF

    echo "$domain {
    tls {
        protocols tls1.2 tls1.3
    }
    reverse_proxy /$path 127.0.0.1:$port
}" > /etc/caddy/Caddyfile

    check_command systemctl restart caddy
    check_command systemctl restart $is_core
    
    show_ws_info "$uuid" "$domain" "$path"
}

gen_vless_grpc() {
    common_tls_setup
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local serviceName=$(openssl rand -hex 4)
    local port=10002

    echo -e "${Font_Cyan}正在配置 VLESS-gRPC-TLS...${Font_Suffix}"

    cat <<EOF > "$config_path"
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": $port, 
        "listen": "127.0.0.1", 
        "protocol": "vless",
        "settings": { 
            "clients": [{ "id": "$uuid" }], 
            "decryption": "none" 
        },
        "streamSettings": { 
            "network": "grpc", 
            "grpcSettings": { "serviceName": "$serviceName" } 
        }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF

    echo "$domain {
    tls {
        protocols tls1.2 tls1.3
    }
    reverse_proxy localhost:$port {
        transport http {
            versions h2c
        }
    }
}" > /etc/caddy/Caddyfile

    check_command systemctl restart caddy
    check_command systemctl restart $is_core
    
    show_grpc_info "$uuid" "$domain" "$serviceName"
}

gen_vless_xhttp() {
    common_tls_setup
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local path=$(openssl rand -hex 6)
    local port=10003

    echo -e "${Font_Cyan}正在配置 VLESS-XHTTP-TLS...${Font_Suffix}"

    cat <<EOF > "$config_path"
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": $port, 
        "listen": "127.0.0.1", 
        "protocol": "vless",
        "settings": { 
            "clients": [{ "id": "$uuid" }], 
            "decryption": "none" 
        },
        "streamSettings": { 
            "network": "xhttp", 
            "xhttpSettings": { 
                "path": "/$path"
            } 
        }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF

    echo "$domain {
    tls {
        protocols tls1.2 tls1.3
    }
    reverse_proxy 127.0.0.1:$port
}" > /etc/caddy/Caddyfile

    check_command systemctl restart caddy
    check_command systemctl restart $is_core
    
    show_xhttp_info "$uuid" "$domain" "$path"
}

gen_trojan_ws() {
    common_tls_setup
    read -p "请输入 Trojan 密码 (默认随机): " pass
    [[ -z "$pass" ]] && pass=$(openssl rand -hex 6)
    
    local path=$(openssl rand -hex 6)
    local port=10004

    cat <<EOF > "$config_path"
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": $port, 
        "listen": "127.0.0.1", 
        "protocol": "trojan",
        "settings": { 
            "clients": [{ "password": "$pass" }] 
        },
        "streamSettings": { 
            "network": "ws", 
            "wsSettings": { "path": "/$path" } 
        }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF

    echo "$domain {
    tls {
        protocols tls1.2 tls1.3
    }
    reverse_proxy /$path localhost:$port
}" > /etc/caddy/Caddyfile

    check_command systemctl restart caddy
    check_command systemctl restart $is_core
    
    show_trojan_info "ws" "$pass" "$domain" "$path"
}

gen_trojan_grpc() {
    common_tls_setup
    read -p "请输入 Trojan 密码 (默认随机): " pass
    [[ -z "$pass" ]] && pass=$(openssl rand -hex 6)
    
    local serviceName=$(openssl rand -hex 4)
    local port=10005

    echo -e "${Font_Cyan}正在配置 Trojan-gRPC-TLS...${Font_Suffix}"

    cat <<EOF > "$config_path"
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": $port, 
        "listen": "127.0.0.1", 
        "protocol": "trojan",
        "settings": { 
            "clients": [{ "password": "$pass" }] 
        },
        "streamSettings": { 
            "network": "grpc", 
            "grpcSettings": { "serviceName": "$serviceName" } 
        }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF

    echo "$domain {
    tls {
        protocols tls1.2 tls1.3
    }
    reverse_proxy localhost:$port {
        transport http {
            versions h2c
        }
    }
}" > /etc/caddy/Caddyfile

    check_command systemctl restart caddy
    check_command systemctl restart $is_core
    
    show_trojan_info "grpc" "$pass" "$domain" "$serviceName"
}

gen_vmess_ws() {
    common_tls_setup
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local path=$(openssl rand -hex 6)
    local port=10001
    
    UUID=$uuid
    WPATH=$path
    DOMAIN=$domain

    echo -e "${Font_Cyan}正在配置 VMess-WS-TLS...${Font_Suffix}"

    cat <<EOF > "$config_path"
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": $port,
        "listen": "127.0.0.1",
        "protocol": "vmess",
        "settings": {
            "clients": [{"id": "$UUID"}]
        },
        "streamSettings": {
            "network": "ws",
            "wsSettings": {"path": "/$WPATH"}
        }
    }],
    "outbounds": [{"protocol": "freedom"}]
}
EOF

    cat <<EOF > /etc/caddy/Caddyfile
$DOMAIN {
    tls {
        protocols tls1.2 tls1.3
    }
    reverse_proxy /$WPATH 127.0.0.1:$port
}
EOF

    check_command systemctl restart xray caddy
    show_vmess_ws_info
}

gen_vmess_grpc() {
    common_tls_setup
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local serviceName=$(openssl rand -hex 6)
    local port=10002
    
    UUID=$uuid
    WPATH=$serviceName
    DOMAIN=$domain

    echo -e "${Font_Cyan}正在配置 VMess-gRPC-TLS...${Font_Suffix}"

    cat <<EOF > "$config_path"
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": $port,
        "listen": "127.0.0.1",
        "protocol": "vmess",
        "settings": {
            "clients": [{"id": "$UUID"}]
        },
        "streamSettings": {
            "network": "grpc",
            "grpcSettings": {"serviceName": "$WPATH"}
        }
    }],
    "outbounds": [{"protocol": "freedom"}]
}
EOF

    cat <<EOF > /etc/caddy/Caddyfile
$DOMAIN {
    tls {
        protocols tls1.2 tls1.3
    }
    reverse_proxy localhost:$port {
        transport http {
            versions h2c
        }
    }
}
EOF

    check_command systemctl restart xray caddy
    show_vmess_grpc_info
}

# ------------------------------------------------ 信息展示模块（完全保留）------------------------------------------------
show_reality_info() {
    local uuid=$1
    local pub_key=$2
    local short_id=$3
    local sni=$4
    local ip=$(curl -4 -s ip.sb || curl -s http://ipv4.icanhazip.com)
    local ps_name="VLESS-REALITY_${sni}_$(date +%Y%m%d)"
    local link="vless://$uuid@$ip:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$sni&fp=chrome&pbk=$pub_key&sid=$short_id&type=tcp#$ps_name"

    echo -e "${Font_Green}VLESS-REALITY 安装成功！${Font_Suffix}"
    echo -e "${Font_Magenta}===============================================${Font_Suffix}"
    echo -e "${Font_Cyan}地址 (IPv4):${Font_Suffix} $ip"
    echo -e "${Font_Cyan}公钥 (pbk):${Font_Suffix} $pub_key"
    echo -e "${Font_Cyan}ShortID:${Font_Suffix} $short_id"
    echo -e "${Font_Magenta}===============================================${Font_Suffix}"
    echo -e "${Font_Yellow}分享链接:${Font_Suffix}"
    echo -e "$link"
    show_qr_code "$link"
    echo -e "${Font_Magenta}===============================================${Font_Suffix}"
}

show_reality_xhttp_info() {
    local uuid=$1 pub_key=$2 short_id=$3 sni=$4 path=$5
    local ip=$(curl -4 -s ip.sb || curl -s http://ipv4.icanhazip.com)
    local ps_name="VLESS-R-XHTTP_${sni}_$(date +%Y%m%d)"
    local link="vless://$uuid@$ip:443?encryption=none&security=reality&sni=$sni&fp=chrome&pbk=$pub_key&sid=$short_id&type=xhttp&path=%2F$path#$ps_name"

    echo -e "${Font_Green}VLESS-REALITY-xhttp 安装成功！${Font_Suffix}"
    echo -e "${Font_Magenta}===============================================${Font_Suffix}"
    echo -e "${Font_Cyan}地址 (IPv4):${Font_Suffix} $ip"
    echo -e "${Font_Cyan}公钥 (pbk):${Font_Suffix} $pub_key"
    echo -e "${Font_Cyan}路径 (Path):${Font_Suffix} /$path"
    echo -e "${Font_Magenta}===============================================${Font_Suffix}"
    echo -e "${Font_Yellow}分享链接:${Font_Suffix}"
    echo -e "$link"
    show_qr_code "$link"
    echo -e "${Font_Magenta}===============================================${Font_Suffix}"
}

show_ws_info() {
    local uuid=$1 domain=$2 path=$3
    local ps_name="${domain}_$(date +%Y%m%d)"
    local link="vless://$uuid@$domain:443?encryption=none&security=tls&type=ws&host=$domain&path=%2F$path#$ps_name"

    echo -e "${Font_Green}VLESS-WS-TLS 安装成功！${Font_Suffix}"
    echo -e "${Font_Magenta}===============================================${Font_Suffix}"
    echo -e "${Font_Cyan}域名:${Font_Suffix} $domain"
    echo -e "${Font_Cyan}UUID:${Font_Suffix} $uuid"
    echo -e "${Font_Cyan}路径:${Font_Suffix} /$path"
    echo -e "${Font_Cyan}端口:${Font_Suffix} 443 (TLS)"
    echo -e "${Font_Magenta}===============================================${Font_Suffix}"
    echo -e "${Font_Yellow}分享链接:${Font_Suffix}"
    echo -e "$link"
    show_qr_code "$link"
    echo -e "${Font_Magenta}===============================================${Font_Suffix}"
}

show_grpc_info() {
    local uuid=$1 domain=$2 serviceName=$3
    local ps_name="${domain}_$(date +%Y%m%d)"
    local link="vless://$uuid@$domain:443?encryption=none&security=tls&type=grpc&serviceName=$serviceName&sni=$domain#$ps_name"

    echo -e "${Font_Green}VLESS-gRPC-TLS 安装成功！${Font_Suffix}"
    echo -e "${Font_Magenta}===============================================${Font_Suffix}"
    echo -e "${Font_Cyan}域名:${Font_Suffix} $domain"
    echo -e "${Font_Cyan}UUID:${Font_Suffix} $uuid"
    echo -e "${Font_Cyan}ServiceName:${Font_Suffix} $serviceName"
    echo -e "${Font_Cyan}端口:${Font_Suffix} 443 (TLS)"
    echo -e "${Font_Magenta}===============================================${Font_Suffix}"
    echo -e "${Font_Yellow}分享链接:${Font_Suffix}"
    echo -e "$link"
    show_qr_code "$link"
    echo -e "${Font_Magenta}===============================================${Font_Suffix}"
}

show_xhttp_info() {
    local uuid=$1 domain=$2 path=$3
    local ps_name="${domain}_$(date +%Y%m%d)"
    local link="vless://$uuid@$domain:443?encryption=none&security=tls&type=xhttp&path=%2F$path&sni=$domain#$ps_name"

    echo -e "${Font_Green}VLESS-XHTTP-TLS 安装成功！${Font_Suffix}"
    echo -e "${Font_Magenta}===============================================${Font_Suffix}"
    echo -e "${Font_Cyan}域名:${Font_Suffix} $domain"
    echo -e "${Font_Cyan}UUID:${Font_Suffix} $uuid"
    echo -e "${Font_Cyan}路径:${Font_Suffix} /$path"
    echo -e "${Font_Cyan}模式:${Font_Suffix} auto (建议客户端手动选 auto)"
    echo -e "${Font_Magenta}===============================================${Font_Suffix}"
    echo -e "${Font_Yellow}分享链接:${Font_Suffix}"
    echo -e "$link"
    show_qr_code "$link"
    echo -e "${Font_Magenta}===============================================${Font_Suffix}"
}

show_trojan_info() {
    local type=$1 pass=$2 host=$3 param=$4
    local ps_name="${host}_$(date +%Y%m%d)"
    local link
    if [[ "$type" == "ws" ]]; then
        link="trojan://$pass@$host:443?security=tls&type=ws&sni=$host&path=%2F$param#$ps_name"
    else
        link="trojan://$pass@$host:443?security=tls&type=grpc&sni=$host&serviceName=$param#$ps_name"
    fi

    echo -e "${Font_Green}Trojan-$type 安装成功！${Font_Suffix}"
    echo -e "${Font_Magenta}===============================================${Font_Suffix}"
    echo -e "${Font_Cyan}密码:${Font_Suffix} $pass"
    echo -e "${Font_Cyan}域名:${Font_Suffix} $host"
    echo -e "${Font_Cyan}端口:${Font_Suffix} 443 (TLS)"
    if [[ "$type" == "ws" ]]; then
        echo -e "${Font_Cyan}路径:${Font_Suffix} /$param"
    else
        echo -e "${Font_Cyan}ServiceName:${Font_Suffix} $param"
    fi
    echo -e "${Font_Magenta}===============================================${Font_Suffix}"
    echo -e "${Font_Yellow}分享链接:${Font_Suffix}"
    show_qr_code "$link"
    echo -e "${Font_Magenta}===============================================${Font_Suffix}"
}

# VMess 展示函数（完全保留）
display_config_board() {
    local p_name=$1 p_link=$2
    echo -e "${Font_Green}————————————————————————————————————————————————————————————————${Font_Suffix}"
    echo -e "  协议类型    :  ${Font_Cyan}${p_name}${Font_Suffix}"
    echo -e "  地址 (Addr) :  ${Font_Cyan}${DOMAIN}${Font_Suffix}"
    echo -e "  端口 (Port) :  ${Font_Cyan}443${Font_Suffix}"
    echo -e "  用户ID(UUID):  ${Font_Cyan}${UUID}${Font_Suffix}"
    if [[ -n "$WPATH" ]]; then
        echo -e "  路径 (Path) :  ${Font_Cyan}/${WPATH}${Font_Suffix}"
    fi
    echo -e "${Font_Green}————————————————————————————————————————————————————————————————${Font_Suffix}"
    echo -e "  分享链接: ${Font_Yellow}${p_link}${Font_Suffix}"
    echo -e "${Font_Green}————————————————————————————————————————————————————————————————${Font_Suffix}"
    show_qr_code "$p_link"
}

show_vmess_ws_info() {
    local domain_name="${DOMAIN:-域名未设置}"
    local uuid_val="${UUID:-UUID未生成}"
    local path_val="${WPATH:-path}"
    local vmess_json=$(cat <<EOF
{
  "v": "2", "ps": "${domain_name}_WS", "add": "${domain_name}", "port": "443", "id": "${uuid_val}",
  "aid": "0", "net": "ws", "path": "/${path_val}", "type": "none", "host": "${domain_name}", "tls": "tls"
}
EOF
)
    local v_link="vmess://$(echo -n "$vmess_json" | base64 | tr -d '\n')"
    display_config_board "VMess-WS-TLS" "$v_link"
}

show_vmess_grpc_info() {
    local domain_name="${DOMAIN:-域名未设置}"
    local uuid_val="${UUID:-UUID未生成}"
    local path_val="${WPATH:-path}"
    local vmess_json=$(cat <<EOF
{
  "v": "2", "ps": "${domain_name}_gRPC", "add": "${domain_name}", "port": "443", "id": "${uuid_val}",
  "aid": "0", "net": "grpc", "path": "${path_val}", "type": "none", "host": "${domain_name}", "tls": "tls"
}
EOF
)
    local v_link="vmess://$(echo -n "$vmess_json" | base64 | tr -d '\n')"
    display_config_board "VMess-gRPC-TLS" "$v_link"
}

show_qr_code() {
    local link=$1
    if command -v qrencode &> /dev/null; then
        echo -e "${Font_Cyan}手机客户端扫描二维码:${Font_Suffix}"
        echo "$link" | qrencode -t utf8
    else
        echo -e "${Font_Red}提示: qrencode 未安装，无法生成二维码。${Font_Suffix}"
    fi
}

show_usage() {
    echo -e "${Font_Magenta}--- 流量统计看板 ---${Font_Suffix}"
    if ! command -v vnstat &> /dev/null; then
        echo -e "${Font_Yellow}检测到 vnstat 未安装，正在尝试安装...${Font_Suffix}"
        apt-get update && apt-get install -y vnstat
        systemctl enable vnstat --now
    fi
    if command -v vnstat &> /dev/null; then
        vnstat -d && vnstat -m
    else
        echo -e "${Font_Red}错误: vnstat 不可用。${Font_Suffix}"
    fi
    read -p "按回车键返回主菜单"
}

# ==================== 彻底卸载功能（已优化） ====================
uninstall_all() {
    echo -e "${Font_Red}⚠️ 警告：此操作将彻底卸载 Xray + Caddy 并清理所有配置和日志！${Font_Suffix}"
    read -p "确定要继续吗？(y/N): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${Font_Green}已取消卸载。${Font_Suffix}"
        read -p "按回车键返回主菜单"
        return
    fi

    echo -e "${Font_Cyan}>>> 开始执行彻底卸载...${Font_Suffix}"

    # 停止服务
    systemctl stop xray caddy 2>/dev/null || true
    systemctl disable xray caddy 2>/dev/null || true

    # 调用官方彻底卸载脚本（推荐 --purge）
    if command -v xray &> /dev/null; then
        echo -e "${Font_Cyan}>>> 调用官方 Xray 彻底卸载脚本 (--purge)...${Font_Suffix}"
        bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) remove --purge
    fi

    # 清理 Caddy
    echo -e "${Font_Cyan}>>> 清理 Caddy...${Font_Suffix}"
    apt-get purge -y caddy 2>/dev/null || true
    rm -rf /etc/caddy /var/log/caddy /root/.config/caddy /usr/share/caddy 2>/dev/null

    # 额外深度清理（防止残留）
    echo -e "${Font_Cyan}>>> 深度清理残留文件...${Font_Suffix}"
    rm -rf /usr/local/bin/xray \
           /usr/local/etc/xray \
           /usr/local/share/xray \
           /var/log/xray \
           /etc/systemd/system/xray.service \
           /etc/systemd/system/xray@*.service \
           /etc/apt/sources.list.d/caddy-stable.list \
           /usr/share/keyrings/caddy-stable-archive-keyring.gpg \
           ~/.acme.sh 2>/dev/null || true

    # 删除 xray 用户（可选，谨慎）
    userdel -r xray 2>/dev/null || true

    systemctl daemon-reload
    echo -e "${Font_Green}✅ 彻底卸载完成！系统已清理干净。${Font_Suffix}"
    read -p "按回车键返回主菜单"
}

# --- 主菜单（保留原样，仅加强调用）---
main_menu() {
    clear
    echo -e "${Font_Magenta}================= 系统状态检查 ================${Font_Suffix}"
    
    local local_ip=$(curl -4 -s --connect-timeout 2 ip.sb || curl -s --connect-timeout 2 http://ipv4.icanhazip.com || echo "获取失败")
    echo -e "   本机 IP  : ${Font_Green}${local_ip}${Font_Suffix}"

    # ==================== 改进后的 Xray 服务状态检测 ====================
    local xray_installed=false
    local xray_active=false

    if [ -f "/etc/systemd/system/xray.service" ] || systemctl list-unit-files | grep -q "xray.service"; then
        xray_installed=true
    fi

    if command -v xray &> /dev/null && [ -f "${config_path}" ]; then
        if systemctl is-active --quiet xray; then
            xray_active=true
        fi
    fi

    if [[ "$xray_installed" == true && "$xray_active" == true ]]; then
        echo -e "   Xray 服务: ${Font_Green}运行中${Font_Suffix}"
    elif [[ "$xray_installed" == true ]]; then
        echo -e "   Xray 服务: ${Font_Yellow}已安装但未运行${Font_Suffix}"
    else
        echo -e "   Xray 服务: ${Font_Red}未安装${Font_Suffix}"
    fi

    # 当前协议检测（已优化）
    if [[ -f $config_path ]]; then
        local current_proto="未知"
        if grep -q "realitySettings" $config_path; then
            if grep -q '"network": "xhttp"' $config_path; then
                current_proto="VLESS-REALITY-xhttp"
            elif grep -q "xtls-rprx-vision" $config_path; then
                current_proto="VLESS-REALITY-Vision"
            else
                current_proto="VLESS-REALITY"
            fi
        elif grep -q '"protocol": "trojan"' $config_path; then
            if grep -q '"network": "ws"' $config_path; then 
                current_proto="Trojan-WS-TLS"
            elif grep -q '"network": "grpc"' $config_path; then 
                current_proto="Trojan-gRPC-TLS"
            fi
        elif grep -q '"protocol": "vmess"' $config_path; then
            if grep -q '"network": "ws"' $config_path; then 
                current_proto="VMess-WS-TLS"
            elif grep -q '"network": "grpc"' $config_path; then 
                current_proto="VMess-gRPC-TLS"
            fi
        elif grep -q '"protocol": "vless"' $config_path; then
            local net=$(grep -m1 '"network":' $config_path | grep -oP '(?<="network": ")[^"]+' || echo "")
            case "${net,,}" in
                ws)    current_proto="VLESS-WS-TLS" ;;
                grpc)  current_proto="VLESS-gRPC-TLS" ;;
                xhttp) current_proto="VLESS-XHTTP-TLS" ;;
                *)     current_proto="VLESS-${net^^}" ;;
            esac
        fi
        echo -e "   当前协议 : ${Font_Green}${current_proto}${Font_Suffix}"
    else
        echo -e "   当前协议 : ${Font_Red}未配置${Font_Suffix}"
    fi

    # ==================== 流量统计 ====================
    if command -v vnstat &> /dev/null && systemctl is-active --quiet vnstat; then
        echo -e "   流量统计 : ${Font_Green}监控中${Font_Suffix}"
    elif command -v vnstat &> /dev/null; then
        echo -e "   流量统计 : ${Font_Yellow}已安装但未启动${Font_Suffix}"
    else
        echo -e "   流量统计 : ${Font_Red}未安装${Font_Suffix}"
    fi
    
    
    OS_NAME=$(grep "PRETTY_NAME" /etc/os-release | cut -d '"' -f 2 2>/dev/null || echo "Linux")
    echo -e "${Font_Red}===============================================${Font_Suffix}"
    echo -e "${Font_Red}   作者：人生若只如初见，更新：2024/05/08   ${Font_Suffix}"
    echo -e "${Font_Red}   名称：xray 一键安装脚本    ${Font_Suffix}"
    echo -e "${Font_Red}   版本号：v1.0.05.08.10.41    ${Font_Suffix}"
    echo -e "${Font_Red}   适用环境：Debian12/13、Ubuntu25/26    ${Font_Suffix}"
    echo -e "${Font_Red}   当前系统：${Font_Suffix}${Font_Green}$OS_NAME    ${Font_Suffix}"
    echo -e "-----------------------------------------------"
    echo -e "${Font_Blue}  【1】 . 安装 VLESS-REALITY-Vision${Font_Suffix}   ${Font_Red}【推荐，最强隐蔽/不依赖域名】${Font_Suffix}"
    echo -e "${Font_Blue}  【2】 . 安装 VLESS-REALITY-xhttp${Font_Suffix}    ${Font_Cyan}【最新黑科技/综合最强】${Font_Suffix}"   
    echo -e "${Font_Blue}  【3】 . 安装 VLESS-WS-TLS${Font_Suffix}           ${Font_Cyan}【CDN兼容/标准WebSocket】${Font_Suffix}"
    echo -e "${Font_Blue}  【4】 . 安装 VLESS-gRPC-TLS${Font_Suffix}         ${Font_Cyan}【低延迟/多路复用】${Font_Suffix}"
    echo -e "${Font_Blue}  【5】 . 安装 VLESS-XHTTP-TLS${Font_Suffix}        ${Font_Cyan}【流式传输/防指纹】${Font_Suffix}"
    echo -e "${Font_Blue}  【6】 . 安装 Trojan-WS-TLS${Font_Suffix}          ${Font_Cyan}【仿HTTPS/老牌稳定】${Font_Suffix}"
    echo -e "${Font_Blue}  【7】 . 安装 Trojan-gRPC-TLS${Font_Suffix}        ${Font_Cyan}【高效转发/适合游戏】${Font_Suffix}"
    echo -e "${Font_Blue}  【8】 . 安装 VMess-WS-TLS${Font_Suffix}           ${Font_Yellow}【广泛兼容/传统方案】${Font_Suffix}"
    echo -e "${Font_Blue}  【9】 . 安装 VMess-gRPC-TLS${Font_Suffix}         ${Font_Yellow}【兼容gRPC新特性】${Font_Suffix}"
  
    echo -e "-----------------------------------------------"
    echo -e "${Font_Magenta}  【c】 . 查看当前协议信息与链接${Font_Suffix}" 
    echo -e "${Font_Magenta}  【v】 . 查看流量统计 (vnstat)${Font_Suffix}"
    echo -e "${Font_Green}  【d】 . 卸载与清理${Font_Suffix}"
    echo -e "${Font_Yellow}  【q】 . 退出脚本${Font_Suffix}" 
    echo -e "-----------------------------------------------"
    read -p "请选择: " num

    case "$num" in
        1) preparation_stack; gen_vless_reality; echo -e "${Font_Red}安装完成，请复制上方链接后按回车键返回菜单...${Font_Suffix}"; read; main_menu ;;
        2) preparation_stack; gen_vless_reality_xhttp; echo -e "${Font_Red}安装完成，请复制上方链接后按回车键返回菜单...${Font_Suffix}"; read; main_menu ;;
        3) preparation_stack; gen_vless_ws; echo -e "${Font_Red}安装完成，请复制上方链接后按回车键返回菜单...${Font_Suffix}"; read; main_menu ;;
        4) preparation_stack; gen_vless_grpc; echo -e "${Font_Red}安装完成，请复制上方链接后按回车键返回菜单...${Font_Suffix}"; read; main_menu ;;
        5) preparation_stack; gen_vless_xhttp; echo -e "${Font_Red}安装完成，请复制上方链接后按回车键返回菜单...${Font_Suffix}"; read; main_menu ;;
        6) preparation_stack; gen_trojan_ws; echo -e "${Font_Red}安装完成，请复制上方链接后按回车键返回菜单...${Font_Suffix}"; read; main_menu ;;
        7) preparation_stack; gen_trojan_grpc; echo -e "${Font_Red}安装完成，请复制上方链接后按回车键返回菜单...${Font_Suffix}"; read; main_menu ;;
        8) preparation_stack; gen_vmess_ws; echo -e "${Font_Red}安装完成，请复制上方链接后按回车键返回菜单...${Font_Suffix}"; read; main_menu ;;
        9) preparation_stack; gen_vmess_grpc; echo -e "${Font_Red}安装完成，请复制上方链接后按回车键返回菜单...${Font_Suffix}"; read; main_menu ;;
        c|C) check_current_protocol; main_menu ;;
        v|V) show_usage; main_menu ;;
        d|D) uninstall_all; main_menu ;;
        q|Q) exit 0 ;;
        *) echo -e "${Font_Red}输入错误，请重新选择！${Font_Suffix}"; sleep 1; main_menu ;;
    esac
}

# 脚本入口
check_root
main_menu