#!/bin/bash

# =================== BUG 修改记录 ====================
# 1、gemini版本
# 2、两个协议可用
#   1)VLESS-WS-TLS
#   4)VMess-WS-TLS
#
# ====================================================
# 将军自持版 V2ray_install.sh 更新日志
# 1. 2026/04/26，v1.0.0.0，支持17个协议全阵列，推荐以VLESS-WS-TLS协议安装，默认同步上海时区，集成 查看/新增/删除 管理逻辑，以及BBR和vnstat两个工具包。
# 2. 2026/04/27，新增 BBR 战略加速模块
# 3. 此版本经过 Debian12、Debian13、Ubuntu25、Ubuntu26 测试通过
# 4. 一键指令 wget -O install.sh https://raw.githubusercontent.com/linuxhobby/autoinstallv2ray/master/install.sh && chmod +x install.sh && ./install.sh
# ====================================================
# 防止最新版本的兼容性，指定v2ray和caddy经过测试稳定的版本，根据实际的升级，日后可以调整升级。
V2_VERSION="v5.49.0"     # 锁定 V2Ray 版本
CADDY_VERSION="2.11.2"    # 锁定 Caddy 版本

# 自定义路径
V2_DIR="/etc/v2ray"
V2_BIN="$V2_DIR/bin/v2ray"
V2_CONF="/etc/v2ray/config.json"
CADDY_FILE="/etc/caddy/Caddyfile"

# --- 核心颜色引擎 (采用安全格式化) ---
# 格式说明：\033[颜色代码m 代表开启；%s 是内容占位符；\033[0m 是重置符号，防止颜色污染后续文本
_white() { printf -- "\033[37m%s\033[0m\n" "$*"; }          # 白色：用于次要信息、常规正文或路径说明
_green() { printf -- "\033[32m%s\033[0m\n" "$*"; }          # 绿色：代表部署成功、服务开启或验证通过[cite: 1]
_red() { printf -- "\033[31m%s\033[0m\n" "$*"; }            # 红色：用于核心警告、错误提示或删除配置[cite: 1]
_yellow() { printf -- "\033[33m%s\033[0m\n" "$*"; }         # 黄色：代表正在处理、安装中或需注意的中间状态[cite: 1]
_blue() { printf -- "\033[34m%s\033[0m\n" "$*"; }           # 蓝色：用于展示具体的战略参数（如UUID、端口、域名）[cite: 1]
_magenta() { printf -- "\033[35m%s\033[0m\n" "$*"; }        # 品红：用于显示战术菜单标题或醒目的横幅[cite: 1]
_cyan() { printf -- "\033[36m%s\033[0m\n" "$*"; }           # 青色：用于用户输入提示（Prompt）或指令说明[cite: 1]
_gray() { printf -- "\033[90m%s\033[0m\n" "$*"; }           # 灰色：用于不重要的背景注释或系统底层日志[cite: 1]
_brown() { printf -- "\033[33m%s\033[0m\n" "$*"; }          # 棕色/暗黄：用于区分次级等待状态或辅助模块提醒[cite: 1]
_purple() { printf -- "\033[38;5;141m%s\033[0m\n" "$*"; }   # 亮紫色：256色高级模式，专门用于展示战略分享链接[cite: 1]

# --- 0. BBR 战略加速引擎 ---
enable_bbr() {
    clear
    _yellow "========== BBR 战略状态巡视 =========="
    if ! command -v sysctl >/dev/null 2>&1; then
        _red "错误：系统缺少 sysctl 指令，无法调控内核参数。"
        read -p "按回车键返回主菜单..." temp
        return
    fi
    local current_algo=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
    if [[ "$current_algo" == "bbr" ]]; then
        _green "检测结果：BBR 战略加速已处于开启状态。"
        _blue "当前内核算法: $current_algo"
        _green ">>> 报告将军：阵地带宽已在最优状态。"
    else
        _red "检测结果：BBR 尚未开启。"
        _yellow ">>> 正在尝试启动 BBR 开启程序..."
        grep -vE "net.core.default_qdisc|net.ipv4.tcp_congestion_control" /etc/sysctl.conf > /etc/sysctl.conf.bak
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf.bak
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf.bak
        mv -f /etc/sysctl.conf.bak /etc/sysctl.conf
        sysctl -p >/dev/null 2>&1
        local final_algo=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
        if [[ "$final_algo" == "bbr" ]]; then
            _green ">>> 部署成功！BBR 战略加速已全面开启。"
        else
            _red ">>> 部署异常：此内核可能不支持 BBR。"
        fi
    fi
    _yellow "======================================"
    read -p "按回车键返回主菜单..." temp
}

# --- 1. 环境初始化与时区校准 ---
init_system() {
    _green ">>> 执行战前准备：设置时区与同步核心..."
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    apt update -y && apt install -y curl jq coreutils python3 gawk grep unzip xz-utils dnsutils gnupg

    _green ">>> 正在配置防火墙，开放 80/443 战略端口..."
    if command -v ufw >/dev/null 2>&1; then
        ufw allow 80/tcp >/dev/null 2>&1
        ufw allow 443/tcp >/dev/null 2>&1
        ufw allow 443/udp >/dev/null 2>&1
    fi
    if command -v iptables >/dev/null 2>&1; then
        iptables -I INPUT -p tcp --dport 80 -j ACCEPT
        iptables -I INPUT -p tcp --dport 443 -j ACCEPT
        iptables -I INPUT -p udp --dport 443 -j ACCEPT
    fi
    
    if [[ "$IS_TLS" == "true" ]]; then
        unset MY_EMAIL
        printf -- "\033[31m请输入用于申请证书的邮箱，用于证书过期提醒（如不需要可直接【回车键】）: \033[0m\n"
        read -p "[默认: linuxhobby@tinkmail.me]: " input_email
        MY_EMAIL=${input_email:-"linuxhobby@tinkmail.me"}
        _blue ">>> 战略目标已锁定，证书邮箱: $MY_EMAIL"
    fi

    mkdir -p $V2_DIR/bin
    if [ ! -f "$V2_BIN" ]; then
        local arch="64"; [[ $(uname -m) == "aarch64" ]] && arch="arm64-v8a"
        _blue ">>> 战略部署：正在下载锁定的 V2Ray 版本: $V2_VERSION"
        curl -L -o /tmp/v2.zip "https://github.com/v2fly/v2ray-core/releases/download/${V2_VERSION}/v2ray-linux-${arch}.zip"
        unzip -qo /tmp/v2.zip -d $V2_DIR/bin/ && chmod +x $V2_BIN
    fi
}

# --- 2. 流量统计安装引擎 ---
install_vnstat() {
    if command -v vnstat &> /dev/null; then
        _green ">>> 报告将军：vnstat 流量统计模块已在运行中，无需重复部署。"
        printf -- "===============================================\n"
        read -p "按回车键返回主菜单..." temp
        return 
    fi

    _brown ">>> 正在开启 vnstat 战略流量统计部署..."
    _blue ">>> 正在从阵地补给站获取 vnstat..."
    apt update && apt install -y vnstat

    local interface=$(ip route get 8.8.8.8 2>/dev/null | grep -Po '(?<=dev )(\S+)' | head -1)
    if [ -z "$interface" ]; then
        interface=$(ls /sys/class/net | grep -v lo | head -1)
    fi
    _blue ">>> 锁定监控网卡: $interface"

    if [ -f "/etc/vnstat.conf" ]; then
        sed -i "s/^Interface .*/Interface \"$interface\"/" /etc/vnstat.conf
    fi

    vnstat -u -i "$interface" >/dev/null 2>&1
    systemctl enable vnstat >/dev/null 2>&1
    systemctl restart vnstat >/dev/null 2>&1

    _green ">>> 部署成功！"
    _red "使用指令说明:"
    _purple " - vnstat -d : 查看每日流量"
    _purple " - vnstat -m : 查看每月流量"
    _purple " - vnstat -i $interface : 查看每日/月流量"
    _purple " - vnstat -l : 实时流量监控"
    printf -- "------------------------------------\n"
    read -p "按回车键返回主菜单..." temp
}

# --- 2. 查看现有配置 ---
show_status() {
    clear
    _red "========== 当前作战部署状态 =========="
    if [ -f "$V2_CONF" ]; then
        local os_info="未知系统"
        if [ -f /etc/os-release ]; then
            os_info=$(grep "PRETTY_NAME" /etc/os-release | cut -d '"' -f 2)
        fi
        _green "● V2Ray 状态: $(systemctl is-active v2ray)"
        _green "● Caddy 状态: $(systemctl is-active caddy 2>/dev/null || echo "未安装")"
        _green "● TCP 加速: $(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}' || echo "未知")"
        printf -- "------------------------------------\n"
        
        local proto=$(jq -r '.inbounds[0].protocol' $V2_CONF)
        local uuid=$(jq -r '.inbounds[0].settings.clients[0].id // .inbounds[0].settings.clients[0].password' $V2_CONF)
        local port=$(jq -r '.inbounds[0].port' $V2_CONF)
        local trans=$(jq -r '.inbounds[0].streamSettings.network // "tcp"' $V2_CONF)
        local path=$(jq -r '.inbounds[0].streamSettings.wsSettings.path // .inbounds[0].streamSettings.grpcSettings.serviceName // ""' $V2_CONF)
        local domain=$(grep -oP '^\s*\K[a-zA-Z0-9.-]+(?=\s*{)' $CADDY_FILE 2>/dev/null | head -n1)
        
        _blue "● 当前协议: $proto"
        _blue "● 传输方式: $trans"
        _blue "● 监听端口: $port"
        _blue "● UUID/密码: $uuid"
        [[ -n "$path" ]] && _blue "● 路径/服务名: $path"
        _blue "● 系统时间: $(date)"
        _blue "● 系统版本: $os_info"
        # --- 流量统计显示模块 ---
        if command -v vnstat &> /dev/null; then
            local vn_data=$(vnstat --oneline)
            local traffic_today=$(echo "$vn_data" | cut -d';' -f6)
            local traffic_month=$(echo "$vn_data" | cut -d';' -f11)
            _blue "● 今日已用流量: $traffic_today"
            _blue "● 本月累计流量: $traffic_month"
        fi        
        printf -- "------------------------------------\n"
        _purple "● 战略分享链接:"
        local current_link=$(get_link "$proto" "$uuid" "$domain" "$path" "$trans" "true")
        _red "$current_link"
        printf -- "------------------------------------\n"
    else
        _red "目前未发现任何部署内容。"
    fi
    _red "===================================="
    read -p "按回车键返回主菜单..." temp
}

# --- 3. 核心构建引擎 ---
build_config() {
    local proto=$1; local secret=$2; local port=$3; local trans=$4; local path=$5; local is_tls=$6
    local stream_json=""
    case $trans in
        ws)   stream_json="\"network\": \"ws\", \"wsSettings\": { \"path\": \"$path\" }" ;;
        grpc) stream_json="\"network\": \"grpc\", \"grpcSettings\": { \"serviceName\": \"$path\" }" ;;
        h2)   stream_json="\"network\": \"h2\", \"httpSettings\": { \"path\": \"$path\" }" ;;
        mkcp) stream_json="\"network\": \"kcp\", \"kcpSettings\": { \"header\": { \"type\": \"none\" } }" ;;
        quic) stream_json="\"network\": \"quic\", \"quicSettings\": { \"header\": { \"type\": \"none\" } }" ;;
        *)    stream_json="\"network\": \"tcp\"" ;;
    esac
    cat > $V2_CONF <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": $port,
    "listen": "$( [[ "$is_tls" == "true" ]] && echo "127.0.0.1" || echo "0.0.0.0" )",
    "protocol": "$proto",
    "settings": {
      $(case $proto in
        vless)       echo '"decryption": "none", "clients": [ { "id": "'$secret'", "level": 0 } ]' ;;
        vmess)       echo '"clients": [ { "id": "'$secret'", "level": 0 } ]' ;;
        trojan)      echo '"clients": [ { "password": "'$secret'" } ]' ;;
        shadowsocks) echo '"method": "aes-256-gcm", "password": "'$secret'"' ;;
        socks)       echo '"auth": "noauth", "udp": true' ;;
      esac)
    },
    "streamSettings": { $stream_json }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF
}

deploy_services() {
    local domain=$1; local path=$2; local port=$3; local is_tls=$4
    if [[ "$is_tls" == "true" ]]; then
        if ! command -v caddy &> /dev/null; then
            _yellow ">>> 正在构筑 Caddy 证书防线 (版本: $CADDY_VERSION)..."
            rm -f /etc/apt/sources.list.d/caddy*
            apt update && apt install -y debian-keyring debian-archive-keyring apt-transport-https
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
            echo "deb [signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" | tee /etc/apt/sources.list.d/caddy-stable.list
            apt update && apt install -y caddy=${CADDY_VERSION}
            apt-mark hold caddy
        fi
        
        if ! getent group caddy >/dev/null; then groupadd --system caddy; fi
        if ! id -u caddy >/dev/null 2>&1; then
            useradd --system --gid caddy --create-home --home-dir /var/lib/caddy --shell /usr/sbin/nologin --comment "Caddy web server" caddy
        fi

        mkdir -p /etc/caddy /var/lib/caddy
        chown -R caddy:caddy /etc/caddy /var/lib/caddy
        
        cat > $CADDY_FILE <<EOF
$domain {
    tls "$MY_EMAIL"
    reverse_proxy $path 127.0.0.1:$port
}
EOF
        systemctl daemon-reload
        systemctl restart caddy
    fi
    cat > /etc/systemd/system/v2ray.service <<EOF
[Unit]
Description=V2Ray Service
After=network.target
[Service]
ExecStart=$V2_BIN run -c $V2_CONF
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl restart v2ray && systemctl enable v2ray
}

get_link() {
    local proto=$1; local secret=$2; local dom=$3; local path=$4; local trans=$5; local is_tls=$6
    local ps_prefix="$dom"
    [[ -z "$dom" ]] && ps_prefix=$(curl -s ipv4.icanhazip.com)
    local ps="${ps_prefix}_$(date +%m%d)"    
    local path_enc=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$path'))")
    if [[ "$is_tls" == "true" ]]; then
        case $proto in
            vless)  echo "vless://${secret}@${dom}:443?encryption=none&security=tls&type=${trans}&host=${dom}&path=${path_enc}#${ps}" ;;
            vmess)
                local v_json=$(cat <<EOF
{"v":"2","ps":"$ps","add":"$dom","port":"443","id":"$secret","aid":"0","net":"$trans","type":"none","host":"$dom","path":"$path","tls":"tls"}
EOF
                )
                echo "vmess://$(echo -n "$v_json" | base64 -w 0)" ;;
            trojan) echo "trojan://${secret}@${dom}:443?security=tls&type=${trans}&host=${dom}&path=${path_enc}#${ps}" ;;
        esac
    fi
}

# --- 主循环控制台 ---
while true; do
    clear
    OS_NAME=$(grep "PRETTY_NAME" /etc/os-release | cut -d '"' -f 2 2>/dev/null || echo "Linux")
    printf -- "\033[31m===============================================\033[0m\n"
    printf -- "\033[31m   作者：linuxhobby，更新：2024/04/29       \033[0m\n"
    printf -- "\033[31m   名称：v2ray_install 战略管理终端v1.0       \033[0m\n"
    printf -- "\033[31m   特征码：人生若只如初见v1.0.0.5                     \033[0m\n"
    printf -- "\033[31m   适用环境：Debian12/13、Ubuntu25/26         \033[0m\n"
    printf -- "\033[31m   当前环境：$OS_NAME \033[0m\n" 
    printf -- "\033[31m===============================================\033[0m\n"
    printf -- "  1) 查看现有配置 (状态监测)\n"
    printf -- "  2) 新增/更换配置 (支持17个协议阵列)\n"
    printf -- "  3) 删除所有配置 (撤除部署)\n"
    printf -- "  4) 开启 BBR 战略加速\n"
    printf -- "  5) 安装 vnstat 流量统计\n"
    printf -- "  q) 撤退\n"
    printf -- "\033[31m===============================================\033[0m\n"
    printf -- "\033[31m请选择主指令: \033[0m" && read main_opt

    case $main_opt in
        1) show_status ;;
        4) enable_bbr ;;
        5) install_vnstat ;;
        3) 
            clear
            _red "========== 撤除部署：消灭敌人 =========="
            if [ -f "$V2_CONF" ]; then
                current_proto=$(jq -r '.inbounds[0].protocol' $V2_CONF)
                current_uuid=$(jq -r '.inbounds[0].settings.clients[0].id // .inbounds[0].settings.clients[0].password' $V2_CONF)
                current_port=$(jq -r '.inbounds[0].port' $V2_CONF)
                current_trans=$(jq -r '.inbounds[0].streamSettings.network // "tcp"' $V2_CONF)
                current_path=$(jq -r '.inbounds[0].streamSettings.wsSettings.path // .inbounds[0].streamSettings.grpcSettings.serviceName // ""' $V2_CONF)
                current_domain=$(grep -oP '^\s*\K[a-zA-Z0-9.-]+(?=\s*{)' $CADDY_FILE 2>/dev/null | head -n1)
                
                _blue "● 当前协议: $current_proto"
                _blue "● 传输方式: $current_trans"
                _blue "● 监听端口: $current_port"
                _blue "● UUID/密码: $current_uuid"
                [[ -n "$current_path" ]] && _blue "● 路径/服务名: $current_path"           
                
                printf -- "------------------------------------\n"
                _red "● 战略分享链接:"
                current_link=$(get_link "$current_proto" "$current_uuid" "$current_domain" "$current_path" "$current_trans" "true")
                _purple "$current_link"
                printf -- "------------------------------------\n"
                _red "警告：此操作将彻底销毁以上所有部署！【直接enter】默认不删除！"
                printf -- "\033[31m确定执行撤除指令？(yes/no): \033[0m" && read confirm_del
                if [[ "$confirm_del" == "yes" ]]; then
                    systemctl stop v2ray caddy 2>/dev/null
                    rm -rf $V2_DIR
                    rm -f $CADDY_FILE
                    _red ">>> 报告将军阁下：阵地已清理完毕。"
                    read -p "按回车键返回主菜单..." temp
                fi
            else
                _blue "提示：敌人已经全部消灭，目前阵地空置，无需撤除。"
                read -p "按回车键返回主菜单..." temp
            fi
            ;;
        2)
            while true; do
                clear
                printf -- "========== 协议战术矩阵 (v2ray_install) ==========\n"
                printf -- "\033[1;31m  1) VLESS-WS-TLS       [王牌：最稳且支持CDN]【推荐】\033[0m\n"
                printf -- "  2) VLESS-gRPC-TLS     [极速：抗封锁性能优异]\n"
                printf -- "  3) VLESS-H2-TLS       [高效：Web 伪装传输变体]\n"
                printf -- "  4) VMess-WS-TLS       [经典：平稳支持CDN中转]\n"
                printf -- "  5) VMess-gRPC-TLS     [全能：多路复用响应快]\n"
                printf -- "  6) VMess-H2-TLS       [稳健：通过 H2 协议伪装]\n"
                printf -- "  7) VMess-TCP          [基础：无伪装，延迟最低]\n"
                printf -- "  8) VMess-mKCP         [强力：UDP加速抗丢包]\n"
                printf -- "  9) VMess-QUIC         [抗断：移动网络连接稳定]\n"
                printf -- " 10) Trojan-gRPC-TLS    [极低延迟：模拟网页流量]\n"
                printf -- " 11) Trojan-WS-TLS      [均衡：传统Trojan结合WS]\n"
                printf -- " 12) Trojan-H2-TLS      [隐蔽：H2 加持网页模拟]\n"
                printf -- " 13) Shadowsocks        [极致轻量：路由器首选]\n"
                printf -- " 14) Shadowsocks-WS     [灵活：SS 加入 WS 传输]\n"
                printf -- " 15) Shadowsocks-QUIC   [抗封：SS 结合 QUIC 传输]\n"
                printf -- " 16) Socks-TCP          [原始：无加密内网测试]\n"
                printf -- " 17) Socks-WS           [兼容：Socks 结合 WS 转发]\n"
                printf -- "-----------------------------------------------\n"
                printf -- "  0) 返回主菜单        q) 退出程序\n"
                printf -- "===============================================\n"
                printf -- "\033[31m请选择协议指令: \033[0m" && read opt
                if [[ -z "$opt" ]] || ! [[ "$opt" =~ ^[0-9]+$ ]] || [ "$opt" -lt 1 ] || [ "$opt" -gt 17 ]; then
                    [[ "$opt" == "0" ]] && break
                    [[ "$opt" == "q" ]] && exit 0
                    _red "警告：非法指令！请重新输入 1-17 之间的数字。"
                    sleep 2
                    continue
                fi
                
                UUID=$(cat /proc/sys/kernel/random/uuid); WPATH="/ray$(cat /proc/sys/kernel/random/uuid | cut -c1-4)"
                DOMAIN=""; IS_TLS="false"; PROTO="vless"; TRANS="ws"; PORT=10086
                case $opt in
                    1) PROTO="vless"; TRANS="ws"; IS_TLS="true" ;;
                    2) PROTO="vless"; TRANS="grpc"; IS_TLS="true" ;;
                    3) PROTO="vless"; TRANS="h2"; IS_TLS="true" ;;
                    4) PROTO="vmess"; TRANS="ws"; IS_TLS="true" ;;
                    5) PROTO="vmess"; TRANS="grpc"; IS_TLS="true" ;;
                    6) PROTO="vmess"; TRANS="h2"; IS_TLS="true" ;;
                    7) PROTO="vmess"; TRANS="tcp"; PORT=12345 ;;
                    8) PROTO="vmess"; TRANS="mkcp"; PORT=12345 ;;
                    9) PROTO="vmess"; TRANS="quic"; PORT=12345 ;;
                    10) PROTO="trojan"; TRANS="grpc"; IS_TLS="true" ;;
                    11) PROTO="trojan"; TRANS="ws"; IS_TLS="true" ;;
                    12) PROTO="trojan"; TRANS="h2"; IS_TLS="true" ;;
                    13) PROTO="shadowsocks"; TRANS="tcp"; PORT=12345; UUID="pass$(date +%s)" ;;
                    14) PROTO="shadowsocks"; TRANS="ws"; IS_TLS="true"; UUID="pass$(date +%s)" ;;
                    15) PROTO="shadowsocks"; TRANS="quic"; PORT=12345; UUID="pass$(date +%s)" ;;
                    16) PROTO="socks"; TRANS="tcp"; PORT=12345 ;;
                    17) PROTO="socks"; TRANS="ws"; IS_TLS="true" ;;
                esac

                init_system

                if [[ "$IS_TLS" == "true" ]]; then
                    while true; do
                        printf -- "\033[31m请输入解析域名: \033[0m" && read DOMAIN
                        [[ -z "$DOMAIN" ]] && { _red "域名不能为空"; continue; }
                        resolved_ip=$(dig +short "$DOMAIN" || host "$DOMAIN" | awk '/has address/ { print $4 }' | head -n1)
                        public_ip=$(curl -s ipv4.icanhazip.com)
                        if [[ "$resolved_ip" == "$public_ip" ]]; then
                            _green "解析一致：$public_ip，可以发起进攻！"; break
                        else
                            _red "解析不匹配或未生效。"; printf -- "\033[31m强制部署？(y/n): \033[0m" && read force_run
                            [[ "$force_run" == "y" ]] && break
                        fi
                    done
                fi
                build_config "$PROTO" "$UUID" "$PORT" "$TRANS" "$WPATH" "$IS_TLS"
                deploy_services "$DOMAIN" "$WPATH" "$PORT" "$IS_TLS"
                _green "==============================================="
                _blue " 协议: $PROTO | 传输: $TRANS"
                _blue " 地址: ${DOMAIN:-$(curl -s ipv4.icanhazip.com)}"
                _blue " UUID/密码: $UUID"
                _blue "-----------------------------------------------"
                SHARE_LINK=$(get_link "$PROTO" "$UUID" "$DOMAIN" "$WPATH" "$TRANS" "$IS_TLS")
                [[ -n "$SHARE_LINK" ]] && printf -- "\033[1;32m${SHARE_LINK}\033[0m\n"
                _green "==============================================="
                exit 0 
            done
            ;;
        q) exit 0 ;;
    esac
done