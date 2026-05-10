#!/bin/bash
# ====================================================
# 作者: 人生若只如初见 (Grok 优化重构版)
# 更新：2026/05/10
# 优化目标：大幅减少重复代码，增强可维护性
# ====================================================

Font_Red="\033[31m"; Font_Green="\033[32m"; Font_Yellow="\033[33m"
Font_Cyan="\033[36m"; Font_Magenta="\033[35m"; Font_Suffix="\033[0m"

ARCH=$(uname -m)
case ${ARCH} in
    x86_64)   XRAY_ARCH="64" ;;
    aarch64)  XRAY_ARCH="arm64" ;;
    armv7l)   XRAY_ARCH="arm32-v7a" ;;
    armv8l)   XRAY_ARCH="arm64" ;;
    *)        echo -e "${Font_Red}不支持的架构: ${ARCH}${Font_Suffix}"; exit 1 ;;
esac

set -e
set -o pipefail
trap 'echo -e "\n${Font_Red}[ERROR] 脚本在第 $LINENO 行失败！命令: $BASH_COMMAND${Font_Suffix}"' ERR

# 全局变量
is_core="xray"
conf_dir="/usr/local/etc/xray"
config_path="${conf_dir}/config.json"
PRESET_DOMAIN=""
XRAY_VERSION="26.5.3"
CADDY_VERSION="2.11.2"
REALITY_DEST_OPTIONS=("www.microsoft.com" "www.apple.com" "www.amazon.com" "www.cloudflare.com" "login.microsoftonline.com")

# ====================== 基础函数 ======================
check_root() { [ "$EUID" -eq 0 ] || { echo -e "${Font_Red}必须 root 权限运行！${Font_Suffix}"; exit 1; }; }

check_command() {
    "$@" || { echo -e "${Font_Red}[ERROR] 执行失败: $*${Font_Suffix}"; exit 1; }
}

setup_xray_user() {
    useradd -r -s /bin/false -U xray 2>/dev/null || true
    mkdir -p "$conf_dir"
    chown -R xray:xray "$conf_dir" 2>/dev/null || true
}

restart_service() {
    systemctl restart "$1"
    systemctl is-active --quiet "$1" || { echo -e "${Font_Red}[ERROR] $1 启动失败${Font_Suffix}"; exit 1; }
}

check_json() {
    if command -v python3 >/dev/null; then
        python3 -m json.tool "$1" >/dev/null 2>&1 || { echo -e "${Font_Red}[ERROR] JSON 格式错误${Font_Suffix}"; exit 1; }
    fi
}

check_port() {
    ss -tulnp 2>/dev/null | grep -q ":$1 " && { echo -e "${Font_Red}[ERROR] 端口 $1 被占用${Font_Suffix}"; exit 1; }
}

check_caddy() {
    command -v caddy >/dev/null || { echo -e "${Font_Red}[ERROR] Caddy 未安装${Font_Suffix}"; exit 1; }
    caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1 || { echo -e "${Font_Red}[ERROR] Caddyfile 语法错误${Font_Suffix}"; exit 1; }
}

check_service_alive() {
    local port=$1 name=$2
    systemctl is-active --quiet xray || { echo -e "${Font_Red}[ERROR] xray 未运行${Font_Suffix}"; exit 1; }
    timeout 2 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/$port" 2>/dev/null || { echo -e "${Font_Red}[ERROR] $name 端口不可达${Font_Suffix}"; exit 1; }
    echo -e "${Font_Green}[OK] $name 服务正常 ($port)${Font_Suffix}"
}

check_external_tcp() {
    timeout 3 bash -c "cat < /dev/null > /dev/tcp/$1/443" 2>/dev/null && echo -e "${Font_Green}[OK] 443 端口外网可达${Font_Suffix}" || { echo -e "${Font_Red}[ERROR] 外网 443 不可达${Font_Suffix}"; exit 1; }
}

get_random_dest() {
    echo "${REALITY_DEST_OPTIONS[$((RANDOM % ${#REALITY_DEST_OPTIONS[@]}))]}"
}

# --- 1. 环境准备模块 ---
preparation_stack() {
    check_root
    setup_xray_user

    # === 时区处理（改为可选，不再强制）===
    check_and_set_timezone

    echo -e "${Font_Cyan}>>> 正在处理 apt 锁...${Font_Suffix}"
    apt-get -o DPkg::Lock::Timeout=180 update --allow-releaseinfo-change -qq || true
    dpkg --configure -a

    # 调用防火墙策略函数
    enable_firewall
    
    # 调用开启BBR函数
    enable_bbr
    
    # 调用依赖检查函数
    check_dependencies

    systemctl enable vnstat --now 2>/dev/null || true

    # ==================== Xray 安装 ====================
    # 安装 Xray（安全方式：先下载再执行）
    if ! command -v xray &> /dev/null || [ ! -f "/etc/systemd/system/xray.service" ]; then
        echo -e "${Font_Cyan}>>> 正在安装 Xray v${XRAY_VERSION}...${Font_Suffix}"
        TMP_SCRIPT=$(mktemp)
        check_command curl -fsSL https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh -o "$TMP_SCRIPT"
        
        # -------------------------------------------------------
        # 关键点：设置此变量后，官方脚本将只安装文件，不再报错启动
        export XRAY_INSTALL_SKIP_START=1 
        # -------------------------------------------------------

        check_command bash "$TMP_SCRIPT" install --version ${XRAY_VERSION}
        rm -f "$TMP_SCRIPT"
        check_command ln -sf /usr/local/bin/xray /usr/bin/xray
        
        # 仅开启自启，不触发启动命令
        systemctl enable xray >/dev/null 2>&1 || true
        
        echo -e "${Font_Green}[OK] Xray v${XRAY_VERSION} 安装完成（已屏蔽无效启动告警）${Font_Suffix}"
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
    local domain=""
    while true; do
        if [[ -n "$PRESET_DOMAIN" ]]; then
            read -p "请输入您的解析域名后回车 [默认域名: $PRESET_DOMAIN]: " domain
            domain=${domain:-$PRESET_DOMAIN}
        else
            read -p "请输入您的解析域名: " domain
        fi

        if [[ -z "$domain" ]]; then continue; fi

        local local_ipv4=$(curl -4 -s --connect-timeout 5 ip.sb || echo "")
        local local_ipv6=$(curl -6 -s --connect-timeout 5 ip.sb || echo "")
        local resolved_ips=$(dig +short "$domain" A 2>/dev/null)
        if [[ -z "$local_ipv4" ]]; then
            echo -e "${Font_Red}[ERROR] 获取本机 IP 失败${Font_Suffix}"
            exit 1
        fi
        
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
            echo "$domain" > /tmp/domain
            export domain
            break
        else
            echo -e "${Font_Red}错误: 域名解析地址与本机 IP 不符！${Font_Suffix}"
            echo -e "${Font_Yellow}1. 重新输入 | 2. 强制跳过 (适合已开启 CDN 的域名)${Font_Suffix}"
            read -p "请选择: " retry_choice
            [[ "$retry_choice" == "2" ]] && break
        fi
    done
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


# ====================== 核心优化函数 ======================
generate_caddy_config() {
    local domain=$1 port=$2 path=$3 type=$4
    cat > /etc/caddy/Caddyfile <<EOF
$domain {
    tls {
        protocols tls1.2 tls1.3
    }
EOF
    case "$type" in
        ws|xhttp)
            echo "    reverse_proxy /$path 127.0.0.1:$port" >> /etc/caddy/Caddyfile
            ;;
        grpc)
            cat >> /etc/caddy/Caddyfile <<EOF
    reverse_proxy localhost:$port {
        transport http {
            versions h2c
        }
    }
EOF
            ;;
    esac
    echo "}" >> /etc/caddy/Caddyfile
}

generate_tls_protocol() {
    local name=$1 proto=$2 network=$3 port=$4 extra_settings=$5 show_func=$6
    check_domain
    local domain=$(cat /tmp/domain 2>/dev/null)
    [[ -z "$domain" ]] && { echo -e "${Font_Red}[ERROR] domain 为空${Font_Suffix}"; exit 1; }

    install_caddy
    local id
    if [[ "$proto" == "trojan" ]]; then
        read -p "请输入 Trojan 密码 (默认随机): " id
        [[ -z "$id" ]] && id=$(openssl rand -hex 8)
    else
        id=$(cat /proc/sys/kernel/random/uuid)
    fi

    local path
    [[ "$network" == "grpc" ]] && path=$(openssl rand -hex 4) || path=$(openssl rand -hex 6)

    check_port "$port"
    echo -e "${Font_Cyan}正在配置 ${name}...${Font_Suffix}"

    cat > "$config_path" <<EOF
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": $port,
        "listen": "127.0.0.1",
        "protocol": "$proto",
        "settings": { "clients": [${extra_settings:-{ "id": "$id" }}] },
        "streamSettings": {
            "network": "$network",
            "$( [[ "$network" == "ws" ]] && echo '"wsSettings"' || [[ "$network" == "grpc" ]] && echo '"grpcSettings"' || echo '"xhttpSettings"')" : {
                "$( [[ "$network" == "ws" || "$network" == "xhttp" ]] && echo 'path' || echo 'serviceName' )": "/$path"
            }
        }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF

    generate_caddy_config "$domain" "$port" "$path" "$network"
    finalize_protocol "$name" "$port" "$domain" "$id" "$path" "$show_func"
}

finalize_protocol() {
    local name=$1 port=$2 domain=$3 id=$4 path=$5 show_func=$6
    check_caddy
    check_json "$config_path"
    restart_service caddy
    restart_service "$is_core"
    sleep 2
    check_service_alive "$port" "$name"
    check_external_tcp "$domain"
    $show_func "$id" "$domain" "$path"
}

# ====================== Reality 协议（保留独立） ======================
gen_vless_reality() {
    echo -e "${Font_Cyan}正在配置 VLESS-REALITY-Vision...${Font_Suffix}"
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local xray_bin=$(command -v xray)
    local keys=$("$xray_bin" x25519)
    local priv_key=$(echo "$keys" | awk -F': ' '/Private/ {print $2}')
    local pub_key=$(echo "$keys" | awk -F': ' '/Public/ {print $2}')
    local dest=$(get_random_dest)
    local short_id=$(openssl rand -hex 8)

    echo "$pub_key" > "${conf_dir}/pub.key"

    cat > "$config_path" <<EOF
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": 443,
        "protocol": "vless",
        "settings": { "clients": [{ "id": "$uuid", "flow": "xtls-rprx-vision" }], "decryption": "none" },
        "streamSettings": {
            "network": "tcp",
            "security": "reality",
            "realitySettings": {
                "show": false,
                "dest": "$dest:443",
                "xver": 0,
                "serverNames": ["$dest"],
                "privateKey": "$priv_key",
                "shortIds": ["$short_id"]
            }
        }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF
    check_json "$config_path"
    restart_service xray
    check_service_alive 443 "VLESS-REALITY"
    check_external_tcp "$(curl -4 -s ip.sb)"
    show_vless_reality_info "$uuid" "$pub_key" "$short_id" "$dest"
}

gen_vless_reality_xhttp() {
    echo -e "${Font_Cyan}正在配置 VLESS-REALITY-xhttp...${Font_Suffix}"
    
    local xray_bin="/usr/local/bin/xray"
    [[ ! -f "$xray_bin" ]] && xray_bin=$(command -v xray)
    
    if [[ -z "$xray_bin" ]]; then
        echo -e "${Font_Red}错误: 未检测到 Xray 核心。${Font_Suffix}"
        return 1
    fi

    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local keys=$("$xray_bin" x25519)   
    if [[ -z "$keys" ]]; then
        echo -e "${Font_Red}[ERROR] x25519 生成失败${Font_Suffix}"
        exit 1
    fi
    
    local priv_key=$(echo "$keys" | grep -i "Private" | awk -F': ' '{print $2}' | tr -d ' ')
    local pub_key=$(echo "$keys" | grep -i "Public" | awk -F': ' '{print $2}' | tr -d ' ')
    
    if [[ -z "$priv_key" || -z "$pub_key" ]]; then
        echo -e "${Font_Red}[ERROR] key 解析失败${Font_Suffix}"
        exit 1
    fi
        
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
    check_json "$config_path"
    systemctl daemon-reload
    restart_service xray
    check_service_alive 443 "VLESS-REALITY"
    check_external_tcp "$(curl -4 -s ip.sb || true)" 443      
    show_vless_reality_xhttp_info "$uuid" "$pub_key" "$short_id" "$dest_server" "$path"
}


# ====================== TLS 协议（使用通用函数） ======================
gen_vless_ws()      { generate_tls_protocol "VLESS-WS-TLS"      "vless"  "ws"    10001 "" "show_vless_ws_info"; }
gen_vless_grpc()    { generate_tls_protocol "VLESS-gRPC-TLS"    "vless"  "grpc"  10002 "" "show_vless_grpc_info"; }
gen_vless_xhttp()   { generate_tls_protocol "VLESS-XHTTP-TLS"   "vless"  "xhttp" 10003 "" "show_vless_xhttp_info"; }
gen_trojan_ws()     { generate_tls_protocol "Trojan-WS-TLS"     "trojan" "ws"    10004 '"password": "$id"' "show_trojan_info"; }
gen_trojan_grpc()   { generate_tls_protocol "Trojan-gRPC-TLS"   "trojan" "grpc"  10005 '"password": "$id"' "show_trojan_info"; }
gen_vmess_ws()      { generate_tls_protocol "VMess-WS-TLS"      "vmess"  "ws"    10001 "" "show_vmess_ws_info"; }
gen_vmess_grpc()    { generate_tls_protocol "VMess-gRPC-TLS"    "vmess"  "grpc"  10002 "" "show_vmess_grpc_info"; }

# ====================== 其他必要函数（check_domain、install_caddy、展示函数等） ======================
# ------------------------------------------------ 信息展示模块（完全保留）------------------------------------------------
show_vless_reality_info() {
    local uuid=$1
    local pub_key=$2
    local short_id=$3
    local sni=$4
    local ip=$(curl -4 -s ip.sb || curl -s http://ipv4.icanhazip.com)
    local ps_name="VLESS-REALITY_${sni}_$(date +%Y%m%d)"
    local link="vless://$uuid@$ip:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$sni&fp=chrome&pbk=$pub_key&sid=$short_id&type=tcp#$ps_name"

    echo -e "${Font_Green}VLESS-REALITY 安装成功！${Font_Suffix}"
    echo -e "${Font_Magenta}===========================================================${Font_Suffix}"
    echo -e "${Font_Cyan}地址 (IPv4):${Font_Suffix} $ip"
    echo -e "${Font_Cyan}公钥 (pbk):${Font_Suffix} $pub_key"
    echo -e "${Font_Cyan}ShortID:${Font_Suffix} $short_id"
    echo -e "${Font_Magenta}===========================================================${Font_Suffix}"
    echo -e "${Font_Red}分享链接:${Font_Suffix}"
    echo -e "$link"
    show_qr_code "$link"
    echo -e "${Font_Magenta}===========================================================${Font_Suffix}"
}

show_vless_reality_xhttp_info() {
    local uuid=$1 pub_key=$2 short_id=$3 sni=$4 path=$5
    local ip=$(curl -4 -s ip.sb || curl -s http://ipv4.icanhazip.com)
    local ps_name="VLESS-R-XHTTP_${sni}_$(date +%Y%m%d)"
    local link="vless://$uuid@$ip:443?encryption=none&security=reality&sni=$sni&fp=chrome&pbk=$pub_key&sid=$short_id&type=xhttp&path=%2F$path#$ps_name"

    echo -e "${Font_Green}VLESS-REALITY-xhttp 安装成功！${Font_Suffix}"
    echo -e "${Font_Magenta}===========================================================${Font_Suffix}"
    echo -e "${Font_Cyan}地址 (IPv4):${Font_Suffix} $ip"
    echo -e "${Font_Cyan}公钥 (pbk):${Font_Suffix} $pub_key"
    echo -e "${Font_Cyan}路径 (Path):${Font_Suffix} /$path"
    echo -e "${Font_Magenta}===========================================================${Font_Suffix}"
    echo -e "${Font_Red}分享链接:${Font_Suffix}"
    echo -e "$link"
    show_qr_code "$link"
    echo -e "${Font_Magenta}===========================================================${Font_Suffix}"
}

show_vless_ws_info() {
    local uuid=$1 domain=$2 path=$3
    local ps_name="${domain}_$(date +%Y%m%d)"
    local link="vless://$uuid@$domain:443?encryption=none&security=tls&type=ws&host=$domain&path=%2F$path#$ps_name"

    echo -e "${Font_Green}VLESS-WS-TLS 安装成功！${Font_Suffix}"
    echo -e "${Font_Magenta}===========================================================${Font_Suffix}"
    echo -e "${Font_Cyan}域名:${Font_Suffix} $domain"
    echo -e "${Font_Cyan}UUID:${Font_Suffix} $uuid"
    echo -e "${Font_Cyan}路径:${Font_Suffix} /$path"
    echo -e "${Font_Cyan}端口:${Font_Suffix} 443 (TLS)"
    echo -e "${Font_Magenta}===========================================================${Font_Suffix}"
    echo -e "${Font_Red}分享链接:${Font_Suffix}"
    echo -e "$link"
    show_qr_code "$link"
    echo -e "${Font_Magenta}===========================================================${Font_Suffix}"
}

show_vless_grpc_info() {
    local uuid=$1 domain=$2 serviceName=$3
    local ps_name="${domain}_$(date +%Y%m%d)"
    local link="vless://$uuid@$domain:443?encryption=none&security=tls&type=grpc&serviceName=$serviceName&sni=$domain#$ps_name"

    echo -e "${Font_Green}VLESS-gRPC-TLS 安装成功！${Font_Suffix}"
    echo -e "${Font_Magenta}===========================================================${Font_Suffix}"
    echo -e "${Font_Cyan}域名:${Font_Suffix} $domain"
    echo -e "${Font_Cyan}UUID:${Font_Suffix} $uuid"
    echo -e "${Font_Cyan}ServiceName:${Font_Suffix} $serviceName"
    echo -e "${Font_Cyan}端口:${Font_Suffix} 443 (TLS)"
    echo -e "${Font_Magenta}===========================================================${Font_Suffix}"
    echo -e "${Font_Red}分享链接:${Font_Suffix}"
    echo -e "$link"
    show_qr_code "$link"
    echo -e "${Font_Magenta}===========================================================${Font_Suffix}"
}

show_vless_xhttp_info() {
    local uuid=$1 domain=$2 path=$3
    local ps_name="${domain}_$(date +%Y%m%d)"
    local link="vless://$uuid@$domain:443?encryption=none&security=tls&type=xhttp&path=%2F$path&sni=$domain#$ps_name"

    echo -e "${Font_Green}VLESS-XHTTP-TLS 安装成功！${Font_Suffix}"
    echo -e "${Font_Magenta}===========================================================${Font_Suffix}"
    echo -e "${Font_Cyan}域名:${Font_Suffix} $domain"
    echo -e "${Font_Cyan}UUID:${Font_Suffix} $uuid"
    echo -e "${Font_Cyan}路径:${Font_Suffix} /$path"
    echo -e "${Font_Cyan}模式:${Font_Suffix} auto (建议客户端手动选 auto)"
    echo -e "${Font_Magenta}===========================================================${Font_Suffix}"
    echo -e "${Font_Red}分享链接:${Font_Suffix}"
    echo -e "$link"
    show_qr_code "$link"
    echo -e "${Font_Magenta}===========================================================${Font_Suffix}"
}

show_trojan_info() {
    local type=$1
    local pass=$2
    local dom=$3
    local path_or_service=$4
    local link=""

    if [[ "$type" == "ws" ]]; then
        # 拼接 Trojan-WS 链接
        link="trojan://${pass}@${dom}:443?security=tls&type=ws&sni=${dom}&path=%2f${path_or_service}#Trojan_WS_${dom}"
    elif [[ "$type" == "grpc" ]]; then
        # 拼接 Trojan-gRPC 链接
        link="trojan://${pass}@${dom}:443?security=tls&encryption=none&type=grpc&serviceName=${path_or_service}&sni=${dom}#Trojan_gRPC_${dom}"
    fi

    echo -e "\n${Font_Green}---------- Trojan 配置信息 ----------${Font_Suffix}"
    echo -e "${Font_Cyan}协议类型    :${Font_Suffix} Trojan-${type}"
    echo -e "${Font_Cyan}地址 (Address):${Font_Suffix} ${dom}"
    echo -e "${Font_Cyan}端口 (Port)   :${Font_Suffix} 443"
    echo -e "${Font_Cyan}密码 (Password):${Font_Suffix} ${pass}"
    echo -e "${Font_Cyan}传输协议 (Net):${Font_Suffix} ${type}"
    echo -e "${Font_Cyan}路径/服务名   :${Font_Suffix} ${path_or_service}"
    echo -e "${Font_Cyan}TLS/SNI       :${Font_Suffix} ${dom}"
    echo -e "${Font_Green}-------------------------------------${Font_Suffix}"
    echo -e "${Font_Red}分享链接:${Font_Suffix}"
    echo -e "${Font_Yellow}${link}${Font_Suffix}"
    echo -e "${Font_Green}-------------------------------------${Font_Suffix}\n"
    show_qr_code "$link"
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
    echo -e "  分享链接: ${Font_Red}${p_link}${Font_Suffix}"
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
    echo -e "${Font_Magenta}======================= 系统状态检查 ======================${Font_Suffix}"
    # 1、vnstat 流量统计状态
    if command -v vnstat &> /dev/null && systemctl is-active --quiet vnstat; then
        echo -e "   流量统计 : ${Font_Green}监控中 ✅${Font_Suffix}"
    elif command -v vnstat &> /dev/null; then
        echo -e "   流量统计 : ${Font_Yellow}已安装但未启动${Font_Suffix}"
    else
        echo -e "   流量统计 : ${Font_Red}未安装 ❌ ${Font_Suffix}"
    fi
    
    # 2、BBR 状态
    local bbr_status
    if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        bbr_status="${Font_Green}运行中 ✅${Font_Suffix}"
    else
        bbr_status="${Font_Red}未开启 ❌ ${Font_Suffix}"
    fi
    echo -e "   BBR 状态 : ${bbr_status}"  
    
    # 3、xray状态
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
        echo -e "   Xray 服务: ${Font_Green}运行中 ✅${Font_Suffix}"
    elif [[ "$xray_installed" == true ]]; then
        echo -e "   Xray 服务: ${Font_Yellow}已安装但未运行${Font_Suffix}"
    else
        echo -e "   Xray 服务: ${Font_Red}未安装 ❌ ${Font_Suffix}"
    fi 
    # 4、当前安装的协议
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
        echo -e "   当前协议 : ${Font_Red}未配置 ❌ ${Font_Suffix}"
    fi
    # 5、当前IP地址
    local local_ip=$(curl -4 -s --connect-timeout 2 ip.sb || curl -s --connect-timeout 2 http://ipv4.icanhazip.com || echo "获取失败")
    echo -e "   本机 IP  : ${Font_Green}${local_ip}${Font_Suffix}"  
    
    OS_NAME=$(grep "PRETTY_NAME" /etc/os-release | cut -d '"' -f 2 2>/dev/null || echo "Linux")
    echo -e "${Font_Red}===========================================================${Font_Suffix}"
    echo -e "${Font_Red}   作者：人生若只如初见，更新：2024/05/10   ${Font_Suffix}"
    echo -e "${Font_Red}   名称：xray 一键安装脚本    ${Font_Suffix}"
    echo -e "${Font_Red}   版本号：v1.0.05.10.18.58（release）    ${Font_Suffix}"
    echo -e "${Font_Red}   适用环境：Debian12/13、Ubuntu25/26    ${Font_Suffix}"
    echo -e "${Font_Red}   当前系统：${Font_Suffix}${Font_Green}$OS_NAME    ${Font_Suffix}"
    echo -e "-----------------------------------------------------------"
    echo -e "${Font_Blue}  【1】 . 安装 VLESS-REALITY-Vision${Font_Suffix}   ${Font_Red}【推荐，最强隐蔽/不依赖域名】${Font_Suffix}"
    echo -e "${Font_Blue}  【2】 . 安装 VLESS-REALITY-xhttp${Font_Suffix}    ${Font_Cyan}【最新黑科技/综合最强】${Font_Suffix}"   
    echo -e "${Font_Blue}  【3】 . 安装 VLESS-WS-TLS${Font_Suffix}           ${Font_Cyan}【CDN兼容/标准WebSocket】${Font_Suffix}"
    echo -e "${Font_Blue}  【4】 . 安装 VLESS-gRPC-TLS${Font_Suffix}         ${Font_Cyan}【低延迟/多路复用】${Font_Suffix}"
    echo -e "${Font_Blue}  【5】 . 安装 VLESS-XHTTP-TLS${Font_Suffix}        ${Font_Cyan}【流式传输/防指纹】${Font_Suffix}"
    echo -e "${Font_Blue}  【6】 . 安装 Trojan-WS-TLS${Font_Suffix}          ${Font_Cyan}【仿HTTPS/老牌稳定】${Font_Suffix}"
    echo -e "${Font_Blue}  【7】 . 安装 Trojan-gRPC-TLS${Font_Suffix}        ${Font_Cyan}【高效转发/适合游戏】${Font_Suffix}"
    echo -e "${Font_Blue}  【8】 . 安装 VMess-WS-TLS${Font_Suffix}           ${Font_Yellow}【广泛兼容/传统方案】${Font_Suffix}"
    echo -e "${Font_Blue}  【9】 . 安装 VMess-gRPC-TLS${Font_Suffix}         ${Font_Yellow}【兼容gRPC新特性】${Font_Suffix}"
  
    echo -e "-----------------------------------------------------------"
    echo -e "${Font_Magenta}  【c】 . 查看当前协议信息与链接${Font_Suffix}" 
    echo -e "${Font_Magenta}  【v】 . 查看流量统计 (vnstat)${Font_Suffix}"
    echo -e "${Font_Magenta}  【b】 . 管理网络加速 (BBR)${Font_Suffix}"
    echo -e "${Font_Green}  【d】 . 卸载与清理${Font_Suffix}"
    echo -e "${Font_Yellow}  【q】 . 退出脚本${Font_Suffix}" 
    echo -e "-----------------------------------------------------------"
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
        b|B) menu_bbr; main_menu ;;
        d|D) uninstall_all; main_menu ;;
        q|Q) exit 0 ;;
        *) echo -e "${Font_Red}输入错误，请重新选择！${Font_Suffix}"; sleep 1; main_menu ;;
    esac
}

# 脚本入口
check_root
main_menu