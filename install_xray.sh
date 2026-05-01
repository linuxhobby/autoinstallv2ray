#!/bin/bash

# ====================================================
# 作者: linuxhobby
# 更新：2024/05/01
# 支持以下协议矩阵安装
#  【1】 . 安装 VLESS-REALITY-Vision
#  【2】 . 安装 VLESS-WS-TLS
#  【3】 . 安装 VLESS-gRPC-TLS
#  【4】 . 安装 VLESS-XHTTP-TLS
#  【5】 . 安装 Trojan-WS-TLS
#  【6】 . 安装 Trojan-gRPC-TLS
# 修改功能：1、域名检测。2、信息查询功能。3、优化菜单
# ====================================================

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
#conf_dir="/etc/xray"
#config_path="/usr/local/etc/xray/config.json"
conf_dir="/usr/local/etc/xray"
config_path="${conf_dir}/config.json"
#默认域名 db.myvpsworld.top
PRESET_DOMAIN="db.myvpsworld.top" # 如果不想预设，留空即可 ""
# --- 版本控制中心 ---
# 锁定 Xray 内核版本
XRAY_VERSION="26.3.27"
# 锁定 Caddy 版本
CADDY_VERSION="2.8.4"
# 是否锁定版本不随系统升级 (1为开启锁定)
FIX_VER=1

# --- 1. 环境准备模块 ---
preparation_stack() {
    # 1.1. 设置上海时区[cite: 1]
    mv /etc/localtime /etc/localtime.bak
    ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    
    # 1.2. 基础依赖与流量统计安装[cite: 2]
    apt-get update
    apt-get install -y wget curl socat tar unzip vnstat
    systemctl enable vnstat
    systemctl start vnstat
    
    # 1.3. 自动安装 Xray 内核 (如果不存在)
    install_caddy() {
        if ! command -v caddy &> /dev/null; then
            echo -e "${Font_Cyan}正在安装 Caddy v${CADDY_VERSION}...${Font_Suffix}"
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
            apt-get update
        
            # 修改点：指定版本安装[cite: 1]
            apt-get install caddy=${CADDY_VERSION} -y
        
            # 修改点：执行版本锁定[cite: 1]
            if [ "$FIX_VER" -eq 1 ]; then
                apt-mark hold caddy
            fi
        fi
    }

    # 1.4. 开启 BBR 加速[cite: 3]
    if [[ $(lsmod | grep bbr) == "" ]]; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p
    fi
}

# --- 2. 域名解析检测优化版：增加循环重试机制 ---
check_domain() {
    while true; do
        # 1. 增加预设域名逻辑：如果变量不为空，则提供默认值选项
        if [[ -n "$PRESET_DOMAIN" ]]; then
            read -p "请输入您的解析域名 [直接回车使用: $PRESET_DOMAIN]: " domain
            domain=${domain:-$PRESET_DOMAIN}
        else
            read -p "请输入您的解析域名: " domain
        fi

        if [[ -z "$domain" ]]; then continue; fi

        # 2. 分别获取本机的 IPv4 和 IPv6
        local local_ipv4=$(curl -4 -s --connect-timeout 5 ip.sb || echo "无")
        local local_ipv6=$(curl -6 -s --connect-timeout 5 ip.sb || echo "无")
        
        # 3. 获取域名的解析结果（优化提取逻辑，确保兼容性）
        local resolved_ips=$(host "$domain" | grep "address" | grep -oP '\d+(\.\d+){3}|([0-9a-fA-F]{1,4}:){1,7}[0-9a-fA-F]{1,4}' | sort -u)
        
        echo -e "${Font_Cyan}本机 IPv4: $local_ipv4 | IPv6: $local_ipv6${Font_Suffix}"
        if [[ -n "$resolved_ips" ]]; then
            echo -e "${Font_Cyan}域名解析地址:${Font_Suffix}\n$resolved_ips"
        else
            echo -e "${Font_Yellow}警告: 未能获取该域名的解析记录。${Font_Suffix}"
        fi

        # 4. 检查逻辑：只要域名解析出的 IP 列表中包含本机的任何一个 IP 即可通过[cite: 1]
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

# --- 3. 查看当前安装的协议及详细信息 ---
check_current_protocol() {
    if [[ ! -f $config_path ]]; then
        echo -e "${Font_Red}错误: 未检测到配置文件 ($config_path)，请先安装协议。${Font_Suffix}"
        read -p "按回车键返回主菜单"
        return
    fi

    echo -e "${Font_Magenta}--- 当前协议详细信息 ---${Font_Suffix}"
    
    # 1. 变量提取逻辑优化：使用 grep -oP 确保只抓取引号内的内容
    local uuid=$(grep -m1 '"id":' $config_path | grep -oP '(?<="id": ")[^"]+' || grep -m1 '"password":' $config_path | grep -oP '(?<="password": ")[^"]+')
    local network=$(grep -m1 '"network":' $config_path | grep -oP '(?<="network": ")[^"]+')
    
    # 获取 IP 和 域名
    local ip=$(curl -4 -s --connect-timeout 5 ip.sb || curl -s http://ipv4.icanhazip.com)
    # 优先从 Caddyfile 提取域名
    local domain=$(grep -oP '^[^#\s{]+' /etc/caddy/Caddyfile | head -n1 | tr -d ' ')
    [[ -z "$domain" ]] && domain=$(grep -oP '(?<="serverNames": \[")[^"]+' $config_path | head -n1)
    [[ -z "$domain" ]] && domain=$ip

    # 2. 识别协议类型并分发显示
    if grep -q "realitySettings" $config_path; then
        local pub_key=$(cat ${conf_dir}/pub.key 2>/dev/null || echo "未找到公钥文件")
        local short_id=$(grep -m1 '"shortIds":' $config_path | grep -oP '(?<="shortIds": \[").*(?="])' | cut -d'"' -f1)
        local sni=$(grep -m1 '"serverNames":' $config_path | grep -oP '(?<="serverNames": \[").*(?="])' | cut -d'"' -f1)
        show_reality_info "$uuid" "$pub_key" "$short_id" "$sni"
    
    elif [[ "$network" == "ws" ]]; then
        # 修复 path 提取，去掉 /
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
    
    echo -e "${Font_Yellow}----------------------------------------${Font_Suffix}"
    read -p "按回车键返回主菜单"
}
# ------------------------------------------------ 2. 核心协议模块库 ------------------------------------------------
# 3.1 VLESS-REALITY-Vision 协议逻辑[cite: 5]
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
# 1. 插入位置：在变量生成后，立即将公钥写入文件
    echo "$pub_key" > ${conf_dir}/pub.key
    
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

# 3.2 VLESS-WS-TLS 协议逻辑完善版
gen_vless_ws() {
    mkdir -p $conf_dir  # 确保目录存在
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

# 修正后的 Caddy 配置：恢复对标准 WebSocket 的支持
    echo "$domain {
    tls {
        protocols tls1.2 tls1.3
    }
    # 核心修正：移除 transport 块，直接反代路径
    reverse_proxy /$path 127.0.0.1:$port
}" > /etc/caddy/Caddyfile

    # 3. 重启服务使配置生效[cite: 2]
    systemctl restart caddy
    systemctl restart $is_core
    
    # 4. 展示安装信息[cite: 2]
    show_ws_info "$uuid" "$domain" "$path"
}

# 3.3 VLESS-gRPC-TLS 协议逻辑完善版
gen_vless_grpc() {
    mkdir -p $conf_dir  # 确保目录存在
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

# 3.4 VLESS-XHTTP-TLS 协议逻辑 - 最终兼容版
gen_vless_xhttp() {
    mkdir -p $conf_dir  # 确保目录存在
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

# 3.5 Trojan-WS-TLS 协议逻辑优化版
gen_trojan_ws() {
    mkdir -p $conf_dir  # 确保目录存在
    check_domain
    install_caddy
    
    # 密码处理：如果用户不输入则随机生成
    read -p "请输入 Trojan 密码 (默认随机): " pass
    [[ -z "$pass" ]] && pass=$(openssl rand -hex 6)
    
    local path=$(openssl rand -hex 6)
    local port=10004

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

# 3.6 Trojan-gRPC-TLS 协议逻辑优化版
gen_trojan_grpc() {
    mkdir -p $conf_dir  # 确保目录存在
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

# --- 4. 信息展示与统计模块 ---
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

# --- 4. 流量统计看板 ---
show_usage() {
    echo -e "${Font_Magenta}--- 流量统计看板 ---${Font_Suffix}"
    vnstat -d && vnstat -m
    read -p "按回车键返回主菜单"
}

# --- 5. 主菜单分发 ---
main_menu() {
    clear
    OS_NAME=$(grep "PRETTY_NAME" /etc/os-release | cut -d '"' -f 2 2>/dev/null || echo "Linux")
    echo -e "${Font_Red}===========================================${Font_Suffix}"
    echo -e "${Font_Red}   作者：linuxhobby，更新：2024/05/01   ${Font_Suffix}"
    echo -e "${Font_Red}   名称：install_xray 一键安装脚本    ${Font_Suffix}"
    echo -e "${Font_Red}   版本号：v1.05.01.12.24    ${Font_Suffix}"
    echo -e "${Font_Red}   适用环境：Debian12/13、Ubuntu25/26    ${Font_Suffix}"
    echo -e "${Font_Red}   当前系统：${Font_Suffix}${Font_Green}$OS_NAME    ${Font_Suffix}"
    echo -e "-------------------------------------------"
    echo -e "${Font_Blue}  【1】 . 安装 VLESS-REALITY-Vision${Font_Suffix}"
    echo -e "${Font_Blue}  【2】 . 安装 VLESS-WS-TLS${Font_Suffix}"
    echo -e "${Font_Blue}  【3】 . 安装 VLESS-gRPC-TLS${Font_Suffix}"
    echo -e "${Font_Blue}  【4】 . 安装 VLESS-XHTTP-TLS${Font_Suffix}"
    echo -e "${Font_Blue}  【5】 . 安装 Trojan-WS-TLS${Font_Suffix}"
    echo -e "${Font_Blue}  【6】 . 安装 Trojan-gRPC-TLS${Font_Suffix}"
    echo -e "-------------------------------------------"
    echo -e "${Font_Magenta}  【t】 . 查看当前协议信息与链接${Font_Suffix}" 
    echo -e "${Font_Magenta}  【v】 . 查看流量统计 (vnstat)${Font_Suffix}"
    echo -e "${Font_Red}  【d】 . 卸载与清理${Font_Suffix}"
    echo -e "${Font_Yellow}  【q】 . 退出脚本${Font_Suffix}" 
    echo -e "-------------------------------------------"
    read -p "请选择: " num

    case "$num" in
        1) preparation_stack; gen_vless_reality; echo -e "${Font_Yellow}安装完成，请复制上方链接后按回车键返回菜单...${Font_Suffix}"; read; exit 0 ;;
        2) preparation_stack; gen_vless_ws; echo -e "${Font_Yellow}安装完成，请复制上方链接后按回车键退出...${Font_Suffix}"; read; exit 0 ;;
        3) preparation_stack; gen_vless_grpc; echo -e "${Font_Yellow}安装完成，请复制上方链接后按回车键退出...${Font_Suffix}"; read; exit 0 ;;
        4) preparation_stack; gen_vless_xhttp; echo -e "${Font_Yellow}安装完成，请复制上方链接后按回车键退出...${Font_Suffix}"; read; exit 0 ;;
        5) preparation_stack; gen_trojan_ws; echo -e "${Font_Yellow}安装完成，请复制上方链接后按回车键退出...${Font_Suffix}"; read; exit 0 ;;
        6) preparation_stack; gen_trojan_grpc; echo -e "${Font_Yellow}安装完成，请复制上方链接后按回车键退出...${Font_Suffix}"; read; exit 0 ;;
        d) 
            read -p "确定要卸载吗？(y/n): " confirm
            if [[ "$confirm" == "y" ]]; then
                apt-mark unhold xray caddy 2>/dev/null[cite: 1]
                systemctl stop xray caddy
                apt-get remove --purge -y xray caddy vnstat
                rm -rf $conf_dir
                echo -e "${Font_Green}清理完成${Font_Suffix}"
                read -p "按回车键返回主菜单"
            fi
            main_menu ;;
        q) echo -e "${Font_Green}退出脚本。${Font_Suffix}"; exit 0 ;;
        t) check_current_protocol; main_menu ;; # 这个函数末尾已经有 read 了，不用加
        v) show_usage; main_menu ;;
        *) echo -e "${Font_Red}无效输入，请输入正确选项。${Font_Suffix}"; sleep 1; main_menu ;;
    esac
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_menu
fi