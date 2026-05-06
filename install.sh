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
#   修改功能：
#   2026/05/01：1、域名检测。2、信息查询功能。3、优化菜单。
#   2026/05/02：1、增加二维码展示功能。
#   2026/05/04：1、修复Trojan协议的二维码。2、修复caddy检查安装。
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
#默认域名 A-Record.YourDomain.com
PRESET_DOMAIN="test.myvpsworld.top" # 如果不想预设，留空即可 ""
# --- 版本控制中心 ---
# 锁定 Xray 内核版本
XRAY_VERSION="26.3.27"
# 锁定 Caddy 版本
CADDY_VERSION="2.8.4"
# 是否锁定版本不随系统升级 (1为开启锁定)
FIX_VER=0

# --- 1. 环境准备模块 ---
preparation_stack() {
    echo -e "${Font_Cyan}>>> 正在深度清理软件包管理器锁 (防止安装失败)...${Font_Suffix}"
    
    # 1. 停止并禁用自动更新服务
    systemctl stop unattended-upgrades 2>/dev/null
    systemctl disable unattended-upgrades 2>/dev/null
    
    # 2. 循环检查并杀死占用 apt/dpkg 的进程
    local kill_count=0
    while fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1; do
        if [ $kill_count -gt 5 ]; then break; fi
        fuser -k /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1
        sleep 1
        ((kill_count++))
    done

    # 3. 强制删除锁文件[cite: 1]
    rm -f /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock
    
    # 4. 重新配置 dpkg 以修复可能的损坏[cite: 1]
    dpkg --configure -a

    # 1.1. 安装 ufw 并自动开放端口
    echo -e "${Font_Cyan}>>> 正在配置系统防火墙策略...${Font_Suffix}"
    apt-get update && apt-get install -y ufw
    
    # 允许 SSH (默认22)，防止断连
    ufw allow 22/tcp 
    # 允许 80/443 用于 Caddy 证书申请和 Xray 服务
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 443/udp
    
    # 静默开启 ufw (输入 y 确认)
    echo "y" | ufw enable
    echo -e "${Font_Green}[OK] 系统防火墙已自动开放 80, 443 端口。${Font_Suffix}"

    # 1.2. 设置时区
    rm -f /etc/localtime
    ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    
    # 1.3. 安装基础依赖[cite: 1]
    apt-get install -y wget curl socat tar unzip vnstat qrencode gnupg2 || {
        echo -e "${Font_Red}[X] 依赖安装失败${Font_Suffix}"
        exit 1
    }
    
    systemctl enable vnstat --now 2>/dev/null
    
    # 1.3. 强制安装 Xray 核心并修复路径
    # 逻辑优化：只有当 xray 不存在或 service 文件缺失时才安装[cite: 1, 3]
    if ! command -v xray &> /dev/null || [ ! -f "/etc/systemd/system/xray.service" ]; then
        echo -e "${Font_Cyan}>>> 正在通过官方脚本部署 Xray 最新版核心...${Font_Suffix}"
        # 移除 -v 参数，确保安装最新版本[cite: 1]
        bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install
        
        # 【关键修复 1】建立软链接[cite: 1]
        ln -sf /usr/local/bin/xray /usr/bin/xray
        # 【关键修复 2】刷新哈希表
        hash -r
    fi

    # 【关键修复 3】修正路径拼写错误：从 /e/ 改为 /etc/[cite: 3]
    if [ ! -f "/etc/systemd/system/xray.service" ] && [ ! -f "/lib/systemd/system/xray.service" ]; then
        echo -e "${Font_Yellow}>>> 正在补偿性生成 xray.service 单元...${Font_Suffix}"
        cat <<EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls/xray-core
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
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
    systemctl start xray

    # 1.4. 开启 BBR
    if [[ $(lsmod | grep bbr) == "" ]]; then
        echo -e "${Font_Cyan}>>> 开启 BBR 加速...${Font_Suffix}"
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p
    fi
}

# --- 1.5. Caddy 安装函数（独立出来）---
install_caddy() {
    if ! command -v caddy &> /dev/null; then
        echo -e "${Font_Cyan}正在安装 Caddy v${CADDY_VERSION}...${Font_Suffix}"
        
        # 1. 清理可能存在的旧密钥和源文件（防止 GPG 报错）
        rm -f /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        rm -f /etc/apt/sources.list.d/caddy-stable.list

        # 2. 添加官方源
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
        
        # 3. 更新索引并安装
        apt-get update
        apt-get install caddy=${CADDY_VERSION} -y || apt-get install caddy -y
        
        # 4. 锁定版本（如果 FIX_VER 为 1）
        if [ "$FIX_VER" -eq 1 ] && command -v caddy &> /dev/null; then
            apt-mark hold caddy
        fi

        # 5. 安装后检测
        if ! command -v caddy &> /dev/null; then
            echo -e "${Font_Red}[X] 错误：Caddy 安装失败。可能原因：APT 锁被占用或源连接超时。${Font_Suffix}"
            exit 1
        fi
    fi
    # 确保配置目录存在
    mkdir -p /etc/caddy
}

# --- 3. 域名解析检测优化版：增加循环重试机制 ---
check_domain() {
    while true; do
        # 1. 增加预设域名逻辑：如果变量不为空，则提供默认值选项
        if [[ -n "$PRESET_DOMAIN" ]]; then
            read -p "请输入您的解析域名后回车 [默认域名: $PRESET_DOMAIN]: " domain
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
        
        #echo -e "${Font_Cyan}本机 IPv4: $local_ipv4 | IPv6: $local_ipv6${Font_Suffix}"
        #echo -e "${Font_Cyan}本机 IPv4: $local_ipv4\n本机 IPv6: $local_ipv6${Font_Suffix}"
        echo -e "${Font_Cyan}本机 IPv4: $local_ipv4${Font_Suffix}"
        echo -e "${Font_Cyan}本机 IPv6: $local_ipv6${Font_Suffix}"
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
# --- 修正后的域名提取逻辑 ---
local domain=""
if [[ -f "/etc/caddy/Caddyfile" ]]; then
    domain=$(grep -oP '^[^#\s{]+' /etc/caddy/Caddyfile | head -n1 | tr -d ' ')
fi

# 如果 Caddyfile 不存在或没提到域名，则尝试从 Xray 配置或 IP 获取
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
    
    echo -e "${Font_Yellow}-----------------------------------------------${Font_Suffix}"
    read -p "按回车键返回主菜单"
}
# ------------------------------------------------ 2. 核心协议模块库 ------------------------------------------------
# 3.1 VLESS-REALITY-Vision 协议逻辑[cite: 5]
gen_vless_reality() {
    echo -e "${Font_Cyan}正在配置 VLESS-REALITY...${Font_Suffix}"
    mkdir -p $conf_dir
    
    # 1. 核心路径检测与修复
    local xray_bin="/usr/local/bin/xray"
    if [ ! -f "$xray_bin" ]; then
        xray_bin=$(command -v xray)
    fi

    if [ -z "$xray_bin" ]; then
        echo -e "${Font_Red}错误: 未检测到 Xray 核心，请确保执行了环境准备步骤。${Font_Suffix}"
        return 1
    fi

    # 2. 变量生成
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    
    # 使用绝对路径生成密钥对，并增加重试逻辑
    local keys=$($xray_bin x25519) 
    
    # 改进的提取逻辑：兼容不同版本的输出格式
    local priv_key=$(echo "$keys" | grep -i "Private" | awk -F': ' '{print $2}' | tr -d ' ')
    local pub_key=$(echo "$keys" | grep -i "Public" | awk -F': ' '{print $2}' | tr -d ' ')
    
    # 调试信息输出
    echo -e "${Font_Blue}调试：私钥为 [$priv_key]${Font_Suffix}"
    echo -e "${Font_Blue}调试：公钥为 [$pub_key]${Font_Suffix}"

    if [[ -z "$priv_key" || -z "$pub_key" ]]; then
        echo -e "${Font_Red}致命错误: 无法生成 REALITY 密钥对，请检查 Xray 是否正常。${Font_Suffix}"
        return 1
    fi

    local short_id=$(openssl rand -hex 8)
    local dest_server="www.microsoft.com" 
    
    # 将公钥写入文件供后续查询功能使用
    echo "$pub_key" > ${conf_dir}/pub.key
    
    # 3. 构建配置文件[cite: 1, 2]
    cat <<EOF > $config_path
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

    # 4. 重启服务[cite: 1, 2, 3]
    systemctl daemon-reload
    if systemctl restart xray; then
        echo -e "${Font_Green}服务重启成功！${Font_Suffix}"
    else
        # 最后的保底：如果服务单元真的不存在，尝试直接运行 (虽然不推荐，但可用于排查)
        echo -e "${Font_Yellow}警告: systemd 重启失败，正在尝试通过命令启动...${Font_Suffix}"
        pkill xray
        nohup $xray_bin run -c $config_path > /dev/null 2>&1 &
    fi
    
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

#####  2026/05/06，这是新增加的两个协议函数1，gen_vmess_ws
gen_vmess_ws() {
    mkdir -p $conf_dir
    check_domain  # 复用脚本已有的域名检测逻辑
    install_caddy # 确保 Caddy 已安装
    
    # 生成局部变量
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local path=$(openssl rand -hex 6)
    local port=10001
    
    # 关键：同步给展示函数使用的全局变量 (大写)
    UUID=$uuid
    WPATH=$path
    DOMAIN=$domain

    echo -e "${Font_Cyan}正在配置 VMess-WS-TLS (Caddy 反代)...${Font_Suffix}"

    # 1. 写入 Xray 配置文件
    cat <<EOF > $config_path
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

    # 2. 手动写入 Caddyfile
    cat <<EOF > /etc/caddy/Caddyfile
$DOMAIN {
    tls {
        protocols tls1.2 tls1.3
    }
    reverse_proxy /$WPATH 127.0.0.1:$port
}
EOF

    # 3. 重启服务
    systemctl restart xray caddy
    
    # 4. 调用您定义的展示函数
    show_vmess_ws_info
}

#####  2026/05/06，这是新增加的两个协议函数1，gen_vmess_ws
gen_vmess_grpc() {
    mkdir -p $conf_dir
    check_domain
    install_caddy
    
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local serviceName=$(openssl rand -hex 6)
    local port=10002
    
    # 同步全局变量
    UUID=$uuid
    WPATH=$serviceName  # VMess gRPC 的 ServiceName 通常对应展示逻辑里的 WPATH
    DOMAIN=$domain

    echo -e "${Font_Cyan}正在配置 VMess-gRPC-TLS (Caddy 反代)...${Font_Suffix}"

    # 1. 写入 Xray 配置文件
    cat <<EOF > $config_path
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

    # 2. 配置 Caddyfile (使用 h2c 转发 gRPC)
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

    systemctl restart xray caddy
    
    # 3. 调用您定义的展示函数
    show_vmess_grpc_info
}

#####  2026/05/06，这是新增加的两个协议函数 2，vmess_grpc,结束

# --- 4. 信息展示与统计模块 ---
show_reality_info() {
    local uuid=$1
    local pub_key=$2
    local short_id=$3
    local sni=$4
    
    # 强制获取 IPv4 地址[cite: 2]
    local ip=$(curl -4 -s ip.sb || curl -s http://ipv4.icanhazip.com)
    
    # 备注命名规范[cite: 1, 2]
    local ps_name="VLESS-REALITY_${sni}_$(date +%Y%m%d)"
    
    # 拼接完整链接，修复 pbk 为空的缺陷[cite: 2]
    local link="vless://$uuid@$ip:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$sni&fp=chrome&pbk=$pub_key&sid=$short_id&type=tcp#$ps_name"

    echo -e "${Font_Green}VLESS-REALITY 安装成功！${Font_Suffix}"
    echo -e "${Font_Magenta}===============================================${Font_Suffix}"
    echo -e "${Font_Cyan}地址 (IPv4):${Font_Suffix} $ip"
    echo -e "${Font_Cyan}公钥 (pbk):${Font_Suffix} $pub_key"
    echo -e "${Font_Cyan}ShortID:${Font_Suffix} $short_id"
    echo -e "${Font_Magenta}===============================================${Font_Suffix}"
    echo -e "${Font_Yellow}分享链接 (请确保完整复制):${Font_Suffix}"
    echo -e "$link"
    # 新增：在此处显示二维码
    show_qr_code "$link"
    echo -e "${Font_Magenta}===============================================${Font_Suffix}"
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
    local uuid=$1
    local domain=$2
    local serviceName=$3
    
    # 备注命名规范[cite: 1, 2]
    local ps_name="${domain}_$(date +%Y%m%d)"
    
    # 构建 VLESS-gRPC-TLS 分享链接[cite: 2]
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
    local uuid=$1
    local domain=$2
    local path=$3
    local ps_name="${domain}_$(date +%Y%m%d)"
    
    # 关键：path 需转义，且必须携带 sni
    local link="vless://$uuid@$domain:443?encryption=none&security=tls&type=xhttp&path=%2F$path&sni=$domain#$ps_name"

    echo -e "${Font_Green}VLESS-XHTTP-TLS 安装成功！${Font_Suffix}"
    echo -e "${Font_Magenta}===============================================${Font_Suffix}"
    echo -e "${Font_Cyan}域名:${Font_Suffix} $domain"
    echo -e "${Font_Cyan}UUID:${Font_Suffix} $uuid"
    echo -e "${Font_Cyan}路径:${Font_Suffix} /$path"
    echo -e "${Font_Cyan}模式:${Font_Suffix} auto (建议客户端手动选 auto)${Font_Suffix}"
    echo -e "${Font_Magenta}===============================================${Font_Suffix}"
    echo -e "${Font_Yellow}分享链接:${Font_Suffix}"
    echo -e "$link"
    show_qr_code "$link"
    echo -e "${Font_Magenta}===============================================${Font_Suffix}"
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
    # 【新增：在此处调用二维码展示函数】
    show_qr_code "$link"
    echo -e "${Font_Magenta}===============================================${Font_Suffix}"
}


# 2026/05/06，新增的 VMess WS 展示函数
# 生成二维码函数
display_config_board() {
    local p_name=$1
    local p_link=$2
    #clear
    echo -e "${Font_Green}————————————————————————————————————————————————————————————————${Font_Suffix}"
    echo -e "  协议类型    :  ${Font_Cyan}${p_name}${Font_Suffix}"
    echo -e "  地址 (Addr) :  ${Font_Cyan}${DOMAIN}${Font_Suffix}"
    echo -e "  端口 (Port) :  ${Font_Cyan}443${Font_Suffix}"
    echo -e "  用户ID(UUID):  ${Font_Cyan}${UUID}${Font_Suffix}"
    
    # 逻辑混淆：如果是 REALITY 则显示公钥，否则显示路径
    if [[ -n "$REALITY_PUB_KEY" && "$p_name" == *"REALITY"* ]]; then
        echo -e "  公钥 (PubKey): ${Font_Cyan}${REALITY_PUB_KEY}${Font_Suffix}"
    elif [[ -n "$WPATH" ]]; then
        echo -e "  路径 (Path) :  ${Font_Cyan}/${WPATH}${Font_Suffix}"
    fi
    
    echo -e "${Font_Green}————————————————————————————————————————————————————————————————${Font_Suffix}"
    echo -e "  分享链接: ${Font_Yellow}${p_link}${Font_Suffix}"
    echo -e "${Font_Green}————————————————————————————————————————————————————————————————${Font_Suffix}"
    
    # 调用你原有的二维码生成函数
    show_qr_code "$p_link"
}

# VMess WS 专用展示分发
# VMess WS 专用展示分发
show_vmess_ws_info() {
    # 确保变量不为空
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
    # 使用 base64 编码并处理换行符
    local v_link="vmess://$(echo -n "$vmess_json" | base64 | tr -d '\n')"
    
    # 调用看板函数
    display_config_board "VMess-WS-TLS" "$v_link"
}

# VMess gRPC 专用展示分发
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
    
    # 调用看板函数
    display_config_board "VMess-gRPC-TLS" "$v_link"
}

# 新增：二维码展示函数
show_qr_code() {
    local link=$1
    if command -v qrencode &> /dev/null; then
        echo -e "${Font_Cyan}手机客户端扫描二维码:${Font_Suffix}"
        echo "$link" | qrencode -t utf8
    else
        echo -e "${Font_Red}提示: qrencode 未安装，无法生成二维码。${Font_Suffix}"
    fi
}

# --- 4. 流量统计看板 ---
show_usage() {
    echo -e "${Font_Magenta}--- 流量统计看板 ---${Font_Suffix}"
    # 检查 vnstat 是否已安装
    if ! command -v vnstat &> /dev/null; then
        echo -e "${Font_Yellow}检测到 vnstat 未安装，正在尝试为您安装...${Font_Suffix}"
        apt-get update && apt-get install -y vnstat
        systemctl enable vnstat --now
        echo -e "${Font_Green}安装完成，请稍等片刻让数据开始收集。${Font_Suffix}"
    fi
    
    # 再次检查是否安装成功
    if command -v vnstat &> /dev/null; then
        vnstat -d && vnstat -m
    else
        echo -e "${Font_Red}错误: 无法安装 vnstat，请检查网络或源设置。${Font_Suffix}"
    fi
    read -p "按回车键返回主菜单"
}

# --- 5. 主菜单分发 ---
main_menu() {
    clear
    # --- 新增：实时状态监控 ---
# --- 新增：实时状态监控 ---
    echo -e "${Font_Magenta}================= 系统状态检查 ================${Font_Suffix}"
    
    # 1. 获取本机 IP
    # 使用 --connect-timeout 防止网络问题导致菜单卡顿
    local local_ip=$(curl -4 -s --connect-timeout 2 ip.sb || curl -s --connect-timeout 2 http://ipv4.icanhazip.com || echo "获取失败")
    echo -e "   本机 IP  : ${Font_Green}${local_ip}${Font_Suffix}"


    # 2. 检查当前安装的协议[cite: 1]
    if [[ -f $config_path ]]; then
        local current_proto="未知"
        if grep -q "realitySettings" $config_path; then
            current_proto="VLESS-REALITY"
        elif grep -q '"protocol": "trojan"' $config_path; then
            if grep -q '"network": "ws"' $config_path; then current_proto="Trojan-WS"; 
            else current_proto="Trojan-gRPC"; fi
        elif grep -q '"protocol": "vless"' $config_path; then
            local net=$(grep -m1 '"network":' $config_path | grep -oP '(?<="network": ")[^"]+')
            current_proto="VLESS-${net^^}" 
        fi
        echo -e "   当前协议 : ${Font_Green}${current_proto}${Font_Suffix}"
    else
        echo -e "   当前协议 : ${Font_Red}未配置${Font_Suffix}"
    fi

    # 3. 检查 Xray 服务状态
    if systemctl list-unit-files | grep -q "xray.service"; then
        if systemctl is-active --quiet xray; then
            echo -e "   Xray 服务: ${Font_Green}运行中${Font_Suffix}"
        else
            echo -e "   Xray 服务: ${Font_Yellow}已安装但停止${Font_Suffix}"
        fi
    else
        echo -e "   Xray 服务: ${Font_Red}未安装${Font_Suffix}"
    fi


    # 4. 检查 vnstat[cite: 1]
    systemctl is-active --quiet vnstat && echo -e "   流量统计 : ${Font_Green}监控中${Font_Suffix}" || echo -e "   流量统计 : ${Font_Red}未启动${Font_Suffix}"
    
    
    OS_NAME=$(grep "PRETTY_NAME" /etc/os-release | cut -d '"' -f 2 2>/dev/null || echo "Linux")
    echo -e "${Font_Red}===============================================${Font_Suffix}"
    echo -e "${Font_Red}   作者：linuxhobby，更新：2024/05/06   ${Font_Suffix}"
    echo -e "${Font_Red}   名称：install_xray 一键安装脚本    ${Font_Suffix}"
    echo -e "${Font_Red}   版本号：v1.0.05.06.15.21    ${Font_Suffix}"
    echo -e "${Font_Red}   适用环境：Debian12/13、Ubuntu25/26    ${Font_Suffix}"
    echo -e "${Font_Red}   当前系统：${Font_Suffix}${Font_Green}$OS_NAME    ${Font_Suffix}"
    echo -e "-----------------------------------------------"
    echo -e "${Font_Blue}  【1】 . 安装 VLESS-REALITY-Vision${Font_Suffix}   ${Font_Red}【推荐，最强隐蔽/不依赖域名】${Font_Suffix}"
    echo -e "${Font_Blue}  【2】 . 安装 VLESS-WS-TLS${Font_Suffix}           ${Font_Cyan}【CDN兼容/标准WebSocket】${Font_Suffix}"
    echo -e "${Font_Blue}  【3】 . 安装 VLESS-gRPC-TLS${Font_Suffix}         ${Font_Cyan}【低延迟/多路复用】${Font_Suffix}"
    echo -e "${Font_Blue}  【4】 . 安装 VLESS-XHTTP-TLS${Font_Suffix}        ${Font_Cyan}【流式传输/防指纹】${Font_Suffix}"
    echo -e "${Font_Blue}  【5】 . 安装 Trojan-WS-TLS${Font_Suffix}          ${Font_Cyan}【仿HTTPS/老牌稳定】${Font_Suffix}"
    echo -e "${Font_Blue}  【6】 . 安装 Trojan-gRPC-TLS${Font_Suffix}        ${Font_Cyan}【高效转发/适合游戏】${Font_Suffix}"
    echo -e "${Font_Blue}  【7】 . 安装 VMess-WS-TLS${Font_Suffix}           ${Font_Yellow}【广泛兼容/传统方案】${Font_Suffix}"
    echo -e "${Font_Blue}  【8】 . 安装 VMess-gRPC-TLS${Font_Suffix}         ${Font_Yellow}【兼容gRPC新特性】${Font_Suffix}"
    
    echo -e "-----------------------------------------------"
    echo -e "${Font_Magenta}  【c】 . 查看当前协议信息与链接${Font_Suffix}" 
    echo -e "${Font_Magenta}  【v】 . 查看流量统计 (vnstat)${Font_Suffix}"
    echo -e "${Font_Green}  【d】 . 卸载与清理${Font_Suffix}"
    echo -e "${Font_Yellow}  【q】 . 退出脚本${Font_Suffix}" 
    echo -e "-----------------------------------------------"
    read -p "请选择: " num

    case "$num" in
        1) preparation_stack; gen_vless_reality; echo -e "${Font_Yellow}安装完成，请复制上方链接后按回车键返回菜单...${Font_Suffix}"; read; exit 0 ;;
        2) preparation_stack; gen_vless_ws; echo -e "${Font_Yellow}安装完成，请复制上方链接后按回车键退出...${Font_Suffix}"; read; exit 0 ;;
        3) preparation_stack; gen_vless_grpc; echo -e "${Font_Yellow}安装完成，请复制上方链接后按回车键退出...${Font_Suffix}"; read; exit 0 ;;
        4) preparation_stack; gen_vless_xhttp; echo -e "${Font_Yellow}安装完成，请复制上方链接后按回车键退出...${Font_Suffix}"; read; exit 0 ;;
        5) preparation_stack; gen_trojan_ws; echo -e "${Font_Yellow}安装完成，请复制上方链接后按回车键退出...${Font_Suffix}"; read; exit 0 ;;
        6) preparation_stack; gen_trojan_grpc; echo -e "${Font_Yellow}安装完成，请复制上方链接后按回车键退出...${Font_Suffix}"; read; exit 0 ;;
        7) preparation_stack; gen_vmess_ws; echo -e "${Font_Yellow}安装完成，请复制上方链接后按回车键退出...${Font_Suffix}"; read; exit 0 ;;
        8) preparation_stack; gen_vmess_grpc; echo -e "${Font_Yellow}安装完成，请复制上方链接后按回车键退出...${Font_Suffix}"; read; exit 0 ;;
        d) 
read -p "确定要彻底卸载并清理环境吗？(y/n): " confirm
if [[ "$confirm" == "y" ]]; then
    echo -e "${Font_Yellow}>>> 开始清理服务与解除锁定...${Font_Suffix}"
    
    # 1. 停止服务并取消锁定
    systemctl stop xray caddy >/dev/null 2>&1
    systemctl disable xray caddy >/dev/null 2>&1
    apt-mark unhold xray caddy >/dev/null 2>&1

    # 2. 优先尝试官方脚本卸载
    if [[ -f "/usr/local/bin/xray" ]]; then
        echo -e "${Font_Yellow}>>> 调用官方脚本卸载 Xray 内核...${Font_Suffix}"
        curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh | bash -s -- remove >/dev/null 2>&1
    fi

    # 3. 使用 APT 彻底清理残余包
    echo -e "${Font_Yellow}>>> 正在通过包管理器移除残余组件...${Font_Suffix}"
    apt-get purge -y xray caddy vnstat >/dev/null 2>&1
    apt-get autoremove -y >/dev/null 2>&1

    # 4. 强制清理残留的服务文件和配置目录
    echo -e "${Font_Yellow}>>> 正在深度清理残留文件...${Font_Suffix}"
    rm -rf /etc/systemd/system/xray.service
    rm -rf /etc/systemd/system/xray@.service
    rm -rf /etc/systemd/system/xray.service.d
    rm -rf /usr/local/etc/xray
    rm -rf /etc/caddy
    
    # 5. 安全清理用户配置目录
    if [[ -n "$conf_dir" ]]; then
        rm -rf "$conf_dir"
    fi

    systemctl daemon-reload
    echo -e "${Font_Green}所有 Xray、Caddy 及相关配置已彻底清理完毕！${Font_Suffix}"
    read -p "按回车键返回主菜单"
fi
            
            main_menu ;;
        q) echo -e "${Font_Green}退出脚本。${Font_Suffix}"; exit 0 ;;
        c) check_current_protocol; main_menu ;; # 这个函数末尾已经有 read 了，不用加
        v) show_usage; main_menu ;;
        *) echo -e "${Font_Red}无效输入，请输入正确选项。${Font_Suffix}"; sleep 1; main_menu ;;
    esac
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_menu
fi