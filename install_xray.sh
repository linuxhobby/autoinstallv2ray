#!/bin/bash

# ====================================================
# Project: Xray Moduler Refactoring
# Protocols: VLESS-WS/gRPC/XHTTP/REALITY, Trojan-WS/gRPC
# Author: Marco Chan
# ====================================================

# 终端颜色定义
Font_Black="\033[30m"
Font_Red="\033[31m"
Font_Green="\033[32m"
Font_Yellow="\033[33m"
Font_Blue="\033[34m"
Font_Magenta="\033[35m"
Font_Cyan="\033[36m"
Font_White="\033[37m"
Font_Suffix="\033[0m"

# 变量初始化
is_core="xray"
conf_dir="/etc/xray"
config_path="/usr/local/etc/xray/config.json"

# --- 1. 环境准备模块 ---
preparation_stack() {
    # 1. 设置上海时区[cite: 1]
    mv /etc/localtime /etc/localtime.bak
    ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    
    # 2. 基础依赖与流量统计安装[cite: 2]
    apt-get update
    apt-get install -y wget curl socat tar unzip vnstat
    systemctl enable vnstat
    systemctl start vnstat
    
    # 3. 自动安装 Xray 内核 (如果不存在)
    if ! command -v $is_core &> /dev/null; then
        echo -e "${Font_Cyan}检测到系统未安装 Xray，正在安装官方内核...${Font_Suffix}"
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
        mkdir -p $conf_dir
    fi

    # 4. 开启 BBR 加速[cite: 3]
    if [[ $(lsmod | grep bbr) == "" ]]; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p
    fi
}

# 域名解析检测[cite: 5]
check_domain() {
    read -p "请输入您的解析域名: " domain
    local current_ip=$(curl -s ip.sb)
    local resolved_ip=$(ping "${domain}" -c 1 | sed '1{s/[^(]*(//;s/).*//;q}' | head -n1)

    if [[ "$resolved_ip" != "$current_ip" ]]; then
        echo -e "${Font_Red}错误: 域名解析地址 ($resolved_ip) 与本机 IP ($current_ip) 不符！${Font_Suffix}"
        exit 1
    fi
}

# Caddy 自动化安装[cite: 4]
install_caddy() {
    if ! command -v caddy &> /dev/null; then
        echo -e "${Font_Cyan}正在安装 Caddy...${Font_Suffix}"
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
        apt-get update && apt-get install caddy -y
    fi
}

# ------------------------------------------------ 2. 核心协议模块库 ------------------------------------------------
# 1 VLESS-REALITY 协议逻辑[cite: 5]
gen_vless_reality() {
    echo -e "${Font_Cyan}正在配置 VLESS-REALITY...${Font_Suffix}"
    mkdir -p $conf_dir
    
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    
    # 强制重新生成密钥对并确保变量不为空
    local keys=$($is_core x25519)
# 改进后的提取逻辑
	local priv_key=$(echo "$keys" | grep -i "PrivateKey" | awk -F': ' '{print $2}' | tr -d ' ')
	echo "调试：私钥为 [$priv_key]"
	local pub_key=$(echo "$keys" | grep -i "PublicKey" | awk -F': ' '{print $2}' | tr -d ' ')
	echo "调试：公钥为 [$pub_key]"
    local short_id=$(openssl rand -hex 8)
    local dest_server="www.loewe.com" 

    # 构建配置 JSON[cite: 1, 2]
    cat <<EOF > $config_path
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": 443, "protocol": "vless",
        "settings": { "clients": [{ "id": "$uuid", "flow": "xtls-rprx-vision" }], "decryption": "none" },
        "streamSettings": { "network": "tcp", "security": "reality",
            "realitySettings": { "show": false, "dest": "$dest_server:443", "xver": 0, "serverNames": ["$dest_server"], "privateKey": "$priv_key", "shortIds": ["$short_id"] }
        }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF
    systemctl restart $is_core
    show_reality_info "$uuid" "$pub_key" "$short_id" "$dest_server"
}

# 2 VLESS-WS-TLS 协议逻辑[cite: 4, 5]
# 2 VLESS-WS-TLS 协议逻辑完善版
gen_vless_ws() {
    check_domain # 检查域名解析是否指向本机[cite: 2]
    install_caddy # 确保 Caddy 已安装[cite: 2]
    
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local path=$(openssl rand -hex 6)
    local port=10001

    echo -e "${Font_Cyan}正在配置 VLESS-WS-TLS (Caddy 反代)...${Font_Suffix}"

    # 1. 配置 Xray 核心[cite: 2]
    cat <<EOF> $config_path
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

# 修正后的 Caddy 配置：确保反代路径精确且支持 h2c[cite: 2, 3]
    echo "$domain {
    tls {
        protocols tls1.2 tls1.3
    }
    # 注意：反代 localhost 时不要带协议头，直接写端口
    reverse_proxy /$path 127.0.0.1:$port {
        transport http {
            versions h2c
        }
    }
}" > /etc/caddy/Caddyfile

    # 3. 重启服务使配置生效[cite: 2]
    systemctl restart caddy
    systemctl restart $is_core
    
    # 4. 展示安装信息[cite: 2]
    show_ws_info "$uuid" "$domain" "$path"
}

# 2 vless_grpc 协议配置
# 3 VLESS-gRPC-TLS 协议逻辑完善版
gen_vless_grpc() {
    check_domain # 检查域名解析
    install_caddy # 确保 Caddy 已安装
    
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local serviceName=$(openssl rand -hex 4)
    local port=10002

    echo -e "${Font_Cyan}正在配置 VLESS-gRPC-TLS...${Font_Suffix}"

    # 1. 配置 Xray 核心 (gRPC 传输层)[cite: 2]
    cat <<EOF > $config_path
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

    # 2. 配置 Caddyfile (启用 h2c 对接 gRPC)[cite: 2]
    echo "$domain {
    tls {
        protocols tls1.2 tls1.3
    }
    # gRPC 必须使用 h2c 传输[cite: 2]
    reverse_proxy localhost:$port {
        transport http {
            versions h2c
        }
    }
}" > /etc/caddy/Caddyfile

    # 3. 重启服务[cite: 2]
    systemctl restart caddy
    systemctl restart $is_core
    
    # 4. 展示安装信息
    show_grpc_info "$uuid" "$domain" "$serviceName"
}

# 4 VLESS-XHTTP-TLS 协议逻辑 - 最终兼容版
gen_vless_xhttp() {
    check_domain
    install_caddy
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local path=$(openssl rand -hex 6)
    local port=10003

    echo -e "${Font_Cyan}正在应用 VLESS-XHTTP-TLS 最终兼容性修复...${Font_Suffix}"

    # 1. 核心配置：明确指定路径
    cat <<EOF > $config_path
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

    # 2. Caddy 配置：移除 transport 限制，改用更通用的反代写法
    # 有时显式写 127.0.0.1 比 localhost 更能避免 IPv6 导致的握手延迟
    echo "$domain {
    tls {
        protocols tls1.2 tls1.3
    }
    reverse_proxy 127.0.0.1:$port
}" > /etc/caddy/Caddyfile

    systemctl restart caddy
    systemctl restart $is_core
    
    show_xhttp_info "$uuid" "$domain" "$path"
}

# 5 Trojan-WS-TLS 协议逻辑优化版
gen_trojan_ws() {
    check_domain
    install_caddy
    
    # 密码处理：如果用户不输入则随机生成
    read -p "请输入 Trojan 密码 (默认随机): " pass
    [[ -z "$pass" ]] && pass=$(openssl rand -hex 6)
    
    local path=$(openssl rand -hex 6)
    local port=10004

    echo -e "${Font_Cyan}正在配置 Trojan-WS-TLS (Caddy 反代)...${Font_Suffix}"

    # 1. 配置 Xray 核心 (Trojan 协议层)
    cat <<EOF > $config_path
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

    # 2. 自动化配置 Caddyfile (包含 TLS 证书自动申请)
    echo "$domain {
    tls {
        protocols tls1.2 tls1.3
    }
    reverse_proxy /$path localhost:$port
}" > /etc/caddy/Caddyfile

    # 3. 重启服务
    systemctl restart caddy
    systemctl restart $is_core
    
    # 4. 展示安装信息
    show_trojan_info "ws" "$pass" "$domain" "$path"
}

# 6 Trojan-gRPC-TLS 协议逻辑优化版
gen_trojan_grpc() {
    check_domain
    install_caddy
    
    read -p "请输入 Trojan 密码 (默认随机): " pass
    [[ -z "$pass" ]] && pass=$(openssl rand -hex 6)
    
    local serviceName=$(openssl rand -hex 4)
    local port=10005

    echo -e "${Font_Cyan}正在配置 Trojan-gRPC-TLS (Caddy 反代)...${Font_Suffix}"

    # 1. 配置 Xray 核心 (Trojan + gRPC)
    cat <<EOF > $config_path
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

    # 2. 配置 Caddyfile (关键：使用 h2c 转发 gRPC 流量)
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

    # 3. 重启服务
    systemctl restart caddy
    systemctl restart $is_core
    
    # 4. 展示安装信息
    show_trojan_info "grpc" "$pass" "$domain" "$serviceName"
}

# --- 3. 信息展示与统计模块 ---
show_reality_info() {
    local uuid=$1
    local pub_key=$2
    local short_id=$3
    local sni=$4
    
    # 强制获取 IPv4 地址[cite: 2]
    local ip=$(curl -4 -s ip.sb || curl -s http://ipv4.icanhazip.com)
    
    # 备注命名规范[cite: 1, 2]
    local ps_name="REALITY_${sni}_$(date +%Y%m%d)"
    
    # 拼接完整链接，修复 pbk 为空的缺陷[cite: 2]
    local link="vless://$uuid@$ip:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$sni&fp=chrome&pbk=$pub_key&sid=$short_id&type=tcp#$ps_name"

    echo -e "${Font_Green}VLESS-REALITY 安装成功！${Font_Suffix}"
    echo -e "${Font_Magenta}========================================${Font_Suffix}"
    echo -e "${Font_Cyan}地址 (IPv4):${Font_Suffix} $ip"
    echo -e "${Font_Cyan}公钥 (pbk):${Font_Suffix} $pub_key"
    echo -e "${Font_Cyan}ShortID:${Font_Suffix} $short_id"
    echo -e "${Font_Magenta}========================================${Font_Suffix}"
    echo -e "${Font_Yellow}分享链接 (请确保完整复制):${Font_Suffix}"
    echo -e "$link"
    echo -e "${Font_Magenta}========================================${Font_Suffix}"
}

show_ws_info() {
    local uuid=$1
    local domain=$2
    local path=$3
    
    # 备注命名规范：域名_日期[cite: 1, 2]
    local ps_name="${domain}_$(date +%Y%m%d)"
    
    # 构建 VLESS-WS-TLS 分享链接[cite: 2]
    # 使用 %2F 对路径中的 / 进行转义
    local link="vless://$uuid@$domain:443?encryption=none&security=tls&type=ws&host=$domain&path=%2F$path#$ps_name"

    echo -e "${Font_Green}VLESS-WS-TLS 安装成功！${Font_Suffix}"
    echo -e "${Font_Magenta}========================================${Font_Suffix}"
    echo -e "${Font_Cyan}域名:${Font_Suffix} $domain"
    echo -e "${Font_Cyan}UUID:${Font_Suffix} $uuid"
    echo -e "${Font_Cyan}路径:${Font_Suffix} /$path"
    echo -e "${Font_Cyan}端口:${Font_Suffix} 443 (TLS)"
    echo -e "${Font_Magenta}========================================${Font_Suffix}"
    echo -e "${Font_Yellow}分享链接:${Font_Suffix}"
    echo -e "$link"
    echo -e "${Font_Magenta}========================================${Font_Suffix}"
}

show_grpc_info() {
    local uuid=$1
    local domain=$2
    local serviceName=$3
    
    # 备注命名规范[cite: 1, 2]
    local ps_name="${domain}_$(date +%Y%m%d)"
    
    # 构建 VLESS-gRPC-TLS 分享链接[cite: 2]
    local link="vless://$uuid@$domain:443?encryption=none&security=tls&type=grpc&serviceName=$serviceName&sni=$domain#$ps_name"

    echo -e "${Font_Green}VLESS-gRPC-TLS 安装成功！${Font_Suffix}"
    echo -e "${Font_Magenta}========================================${Font_Suffix}"
    echo -e "${Font_Cyan}域名:${Font_Suffix} $domain"
    echo -e "${Font_Cyan}UUID:${Font_Suffix} $uuid"
    echo -e "${Font_Cyan}ServiceName:${Font_Suffix} $serviceName"
    echo -e "${Font_Cyan}端口:${Font_Suffix} 443 (TLS)"
    echo -e "${Font_Magenta}========================================${Font_Suffix}"
    echo -e "${Font_Yellow}分享链接:${Font_Suffix}"
    echo -e "$link"
    echo -e "${Font_Magenta}========================================${Font_Suffix}"
}

show_xhttp_info() {
    local uuid=$1
    local domain=$2
    local path=$3
    local ps_name="${domain}_$(date +%Y%m%d)"
    
    # 关键：path 需转义，且必须携带 sni
    local link="vless://$uuid@$domain:443?encryption=none&security=tls&type=xhttp&path=%2F$path&sni=$domain#$ps_name"

    echo -e "${Font_Green}VLESS-XHTTP-TLS 安装成功！${Font_Suffix}"
    echo -e "${Font_Magenta}========================================${Font_Suffix}"
    echo -e "${Font_Cyan}域名:${Font_Suffix} $domain"
    echo -e "${Font_Cyan}UUID:${Font_Suffix} $uuid"
    echo -e "${Font_Cyan}路径:${Font_Suffix} /$path"
    echo -e "${Font_Cyan}模式:${Font_Suffix} auto (建议客户端手动选 auto)${Font_Suffix}"
    echo -e "${Font_Magenta}========================================${Font_Suffix}"
    echo -e "${Font_Yellow}分享链接:${Font_Suffix}"
    echo -e "$link"
    echo -e "${Font_Magenta}========================================${Font_Suffix}"
}

show_trojan_info() {
    local type=$1
    local pass=$2
    local host=$3
    local param=$4
    # 遵循 User Summary 中的命名规范：域名_日期[cite: 1, 2]
    local ps_name="${host}_$(date +%Y%m%d)"
    
    if [[ "$type" == "ws" ]]; then
        # 针对 WS 路径进行 %2F 转义
        local link="trojan://$pass@$host:443?security=tls&type=ws&sni=$host&path=%2F$param#$ps_name"
    else
        local link="trojan://$pass@$host:443?security=tls&type=grpc&sni=$host&serviceName=$param#$ps_name"
    fi

    echo -e "${Font_Green}Trojan-$type 安装成功！${Font_Suffix}"
    echo -e "${Font_Magenta}========================================${Font_Suffix}"
    echo -e "${Font_Cyan}密码:${Font_Suffix} $pass"
    echo -e "${Font_Cyan}域名:${Font_Suffix} $host"
    echo -e "${Font_Cyan}端口:${Font_Suffix} 443 (TLS)"
    if [[ "$type" == "ws" ]]; then
        echo -e "${Font_Cyan}路径:${Font_Suffix} /$param"
    else
        echo -e "${Font_Cyan}ServiceName:${Font_Suffix} $param"
    fi
    echo -e "${Font_Magenta}========================================${Font_Suffix}"
    echo -e "${Font_Yellow}分享链接:${Font_Suffix}"
    echo -e "$link"
    echo -e "${Font_Magenta}========================================${Font_Suffix}"
}

# 流量统计工具[cite: 2]
show_usage() {
    echo -e "${Font_Magenta}--- 流量统计看板 ---${Font_Suffix}"
    vnstat -d && vnstat -m
    read -p "按回车键返回主菜单"
}

# --- 4. 主菜单分发 ---
# --- 4. 主菜单分发 ---

main_menu() {
    clear
    echo -e "${Font_Magenta}--- Xray 模块化管理脚本v1.05.01.03.52 ---${Font_Suffix}"
    echo -e "${Font_Blue}1. 安装 VLESS-REALITY【ok】${Font_Suffix}"
    echo -e "${Font_Blue}2. 安装 VLESS-WS-TLS【ok】${Font_Suffix}"
    echo -e "${Font_Blue}3. 安装 VLESS-gRPC-TLS【ok】${Font_Suffix}"
    echo -e "${Font_Blue}4. 安装 VLESS-XHTTP-TLS【no】${Font_Suffix}"
    echo -e "${Font_Blue}5. 安装 Trojan-WS-TLS【ok】${Font_Suffix}"
    echo -e "${Font_Blue}6. 安装 Trojan-gRPC-TLS【ok】${Font_Suffix}"
    echo -e "${Font_Cyan}t. 查看流量统计 (vnstat)${Font_Suffix}"
    echo -e "${Font_Red}7. 卸载与清理${Font_Suffix}"
    read -p "请选择: " num

    case "$num" in
        1) preparation_stack; gen_vless_reality ;;
        2) preparation_stack; gen_vless_ws ;;
        3) preparation_stack; gen_vless_grpc ;;
        4) preparation_stack; gen_vless_xhttp ;;
        5) preparation_stack; gen_trojan_ws ;;
        6) preparation_stack; gen_trojan_grpc ;;
        t) show_usage; main_menu ;;
        7) systemctl stop xray caddy; apt-get remove --purge -y vnstat caddy; echo "清理完成";;
        *) exit 1 ;;
    esac
}

# 脚本最后一行必须调用函数
main_menu