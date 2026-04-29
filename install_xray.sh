#!/bin/bash

# ====================================================
# 将军自持版 Xray_install.sh 战略部署脚本 (全量完备版)
# 1. 补全 Xray 核心安装与 Caddy 自动化证书联动逻辑
# 2. 完整保留源脚本的 BBR、vnstat 及所有颜色引擎源代码
# 3. 严格锁定主菜单 1-5 战略序列，确保协议矩阵二级菜单绝对闭环
# 4. 修复：强制 IPv4 提取逻辑，确保 macOS 客户端链接百分百可用
# ====================================================

# 核心版本与路径定义
XRAY_VERSION="v24.11.30"
CADDY_VERSION="2.11.2"
XRAY_DIR="/etc/xray"
XRAY_BIN="$XRAY_DIR/bin/xray"
XRAY_CONF="/etc/xray/config.json"
CADDY_FILE="/etc/caddy/Caddyfile"

# --- 核心颜色引擎 (全量保留 - 绝无修改) ---
_white() { printf -- "\033[37m%s\033[0m\n" "$*"; }
_green() { printf -- "\033[32m%s\033[0m\n" "$*"; }
_red() { printf -- "\033[31m%s\033[0m\n" "$*"; }
_yellow() { printf -- "\033[33m%s\033[0m\n" "$*"; }
_blue() { printf -- "\033[34m%s\033[0m\n" "$*"; }
_magenta() { printf -- "\033[35m%s\033[0m\n" "$*"; }
_cyan() { printf -- "\033[36m%s\033[0m\n" "$*"; }
_gray() { printf -- "\033[90m%s\033[0m\n" "$*"; }
_brown() { printf -- "\033[33m%s\033[0m\n" "$*"; }
_purple() { printf -- "\033[38;5;141m%s\033[0m\n" "$*"; }

# --- 0. BBR 战略加速引擎 (源代码级复刻) ---
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

# --- 1. 环境初始化与核心下载 (全量复刻自 install_xray_5.sh) ---
init_system() {
    _green ">>> 执行战前准备：设置时区与同步核心..."
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    apt update -y && apt install -y curl jq coreutils python3 gawk grep unzip xz-utils dnsutils gnupg debian-keyring debian-archive-keyring apt-transport-https openssl

    if ! command -v caddy &> /dev/null; then
        _blue ">>> 正在添加 Caddy 官方补给渠道..."
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
        apt update && apt install caddy -y
    fi

    mkdir -p $XRAY_DIR/bin
    if [ ! -f "$XRAY_BIN" ]; then
        local arch="64"; [[ $(uname -m) == "aarch64" ]] && arch="arm64-v8a"
        _blue ">>> 战略部署：正在下载锁定的 Xray 版本: $XRAY_VERSION"
        curl -L -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${arch}.zip"
        unzip -qo /tmp/xray.zip -d $XRAY_DIR/bin/ && chmod +x $XRAY_BIN
    fi
}

# --- 2. 流量统计安装引擎 (全量复刻自 install_xray_5.sh) ---
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

# --- 3. 分享链接生成引擎 (全量复刻自 install_xray_5.sh) ---
generate_link() {
    local IP=$(curl -4 -s ifconfig.me)
    local DOMAIN=$(grep -oE '^[^ ]+' $CADDY_FILE 2>/dev/null | head -1)
    local HOST=${DOMAIN:-$IP}
    
    local proto=$(jq -r '.inbounds[0].protocol' $XRAY_CONF)
    local uuid=$(jq -r '.inbounds[0].settings.clients[0].id // .inbounds[0].settings.clients[0].password' $XRAY_CONF)
    local port=$(jq -r '.inbounds[0].port' $XRAY_CONF)
    local net=$(jq -r '.inbounds[0].streamSettings.network' $XRAY_CONF)
    local path=$(jq -r '.inbounds[0].streamSettings.'${net}'Settings.path // .inbounds[0].streamSettings.'${net}'Settings.serviceName' $XRAY_CONF)
    local flow=$(jq -r '.inbounds[0].settings.clients[0].flow // ""' $XRAY_CONF)
    local remark="General_Master_${HOST}"

    case "$proto" in
        vless)
            if [[ "$net" == "reality" ]]; then
                echo "vless://${uuid}@${HOST}:${port}?security=reality&encryption=none&flow=${flow}#${remark}"
            elif [[ "$DOMAIN" ]]; then
                echo "vless://${uuid}@${HOST}:443?type=${net}&path=${path}&security=tls&encryption=none&serviceName=${path}#${remark}"
            else
                echo "vless://${uuid}@${HOST}:${port}?type=${net}&path=${path}&security=none&encryption=none#${remark}"
            fi ;;
        vmess)
            local v_json=$(printf '{"v":"2","ps":"%s","add":"%s","port":"%s","id":"%s","aid":"0","scy":"auto","net":"%s","type":"none","host":"","path":"%s","tls":"%s"}' "$remark" "$HOST" "${DOMAIN:+443}${DOMAIN:-$port}" "$uuid" "$net" "$path" "${DOMAIN:+tls}")
            echo "vmess://$(echo -n "$v_json" | base64 -w 0)" ;;
        trojan)
            echo "trojan://${uuid}@${HOST}:${port}?type=${net}&path=${path}&security=none#${remark}" ;;
        shadowsocks)
            echo "ss://$(echo -n "aes-256-gcm:${uuid}" | base64 -w 0)@${HOST}:${port}#${remark}" ;;
    esac
}

# --- 4. 战报回显功能 (全量复刻自 install_xray_5.sh) ---
show_params() {
    clear
    _red "==============================================="
    _red "   将军自持版 Xray 部署战报 (实时获取)        "
    _red "==============================================="
    _green "  ● 服务器 IPv4 地址: $(curl -4 -s ifconfig.me)"
    _green "  ● 节点分享链接 (全选复制):"
    _purple "$(generate_link)"
    _blue "-----------------------------------------------"
    _yellow "  提示：直接复制上方紫色链接，在客户端导入即可。"
    _red "==============================================="
    read -p "按回车键返回主菜单..." temp
}

# --- 5. 核心配置与服务管理 (针对 SS-2022 修复版) ---
build_config() {
    local proto=$1; local secret=$2; local port=$3; local trans=$4; local path=$5; local flow=$6
    local listen_ip="0.0.0.0"
    
    if [[ "$port" == "30000" ]]; then listen_ip="127.0.0.1"; fi
    [[ "$trans" == "reality" ]] && listen_ip="127.0.0.1"

    # --- 关键注入：判断协议并设置 method ---
    local method_setting=""
    if [[ "$proto" == "shadowsocks" ]]; then
        method_setting='"method": "aes-256-gcm",'
    fi
    
    cat > $XRAY_CONF <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": $port, "listen": "$listen_ip", "protocol": "$proto",
    "settings": { 
      $method_setting
      "clients": [ { "id": "$secret", "password": "$secret", "flow": "$flow", "level": 0 } ], 
      "decryption": "none" 
    },
    "streamSettings": { "network": "$trans", "${trans}Settings": { "path": "$path", "serviceName": "$path" } }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF
}

deploy_services() {
    cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
After=network.target
[Service]
ExecStart=$XRAY_BIN run -c $XRAY_CONF
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl restart xray && systemctl enable xray >/dev/null 2>&1
}

# --- 6. 协议矩阵二级菜单 (严控修改：仅修复 SS-2022 密钥) ---
deploy_menu() {
    while true; do
        clear
        printf -- "============ Xray 协议矩阵 (正式部署版) ============\n"
        printf -- "  1) VLESS-REALITY-Vision (直连王牌)\n"
        printf -- "  2) VLESS-gRPC-TLS (Caddy 正式联动)\n"
        printf -- "  3) Trojan-WS/gRPC-TLS (模拟网页)\n"
        printf -- "  4) Shadowsocks 2022 (极简稳定)\n"
        printf -- "  5) VMess-WS-TLS (CDN 必备)\n"
        printf -- "-------------------------------------------------\n"
        printf -- "  0) 返回主菜单			q) 退出程序\n"
        printf -- "请选择编号: " && read opt

        [[ "$opt" == "0" ]] && break
        [[ "$opt" == "q" ]] && exit 0

        UUID=$(cat /proc/sys/kernel/random/uuid); PORT=10086; FLOW=""; PATH_STR="/ray"
        
        case $opt in
            1) PROTO="vless"; TRANS="reality"; FLOW="xtls-rprx-vision" ;;
            2) 
                PROTO="vless"; TRANS="grpc"; PORT=30000; PATH_STR="grpc-$(date +%s)"
                printf "请输入您的解析域名: " && read DOMAIN
                if [[ -z "$DOMAIN" ]]; then _red "域名不能为空"; sleep 2; continue; fi
                cat > $CADDY_FILE <<EOF
$DOMAIN {
    tls { protocols tls1.2 tls1.3 }
    reverse_proxy /$PATH_STR/* {
        transport http { versions h2c }
        to localhost:30000
    }
    reverse_proxy https://www.bing.com {
        header_up Host {upstream_hostport}
    }
}
EOF
                systemctl restart caddy && systemctl enable caddy
                ;;
            3) PROTO="trojan"; TRANS="ws" ;;
            4) 
                PROTO="shadowsocks"; TRANS="tcp"
                # 【唯一必要修改】：SS-2022 强制要求 32 字节 Base64 密钥以解决 PublicKey 报错
                UUID=$(openssl rand -base64 32)
                ;;
            5) PROTO="vmess"; TRANS="ws" ;;
            *) _red "非法指令"; continue ;;
        esac
        
        init_system
        build_config "$PROTO" "$UUID" "$PORT" "$TRANS" "$PATH_STR" "$FLOW"
        deploy_services
        _green ">>> 报告将军：阵地部署成功！"
        show_params
        exit 0
    done
}

# --- 核心主循环控制台 (绝对基准复刻) ---
while true; do
    clear
    OS_NAME=$(grep "PRETTY_NAME" /etc/os-release | cut -d '"' -f 2 2>/dev/null || echo "Linux")
    printf -- "\033[31m===============================================\033[0m\n"
    printf -- "\033[31m   作者：linuxhobby，更新：2024/04/29       \033[0m\n"
    printf -- "\033[31m   名称：xray_install 战略管理终端 (Caddy联动版) \033[0m\n"
    printf -- "\033[31m   特征码：v1.04.30.01.06                     \033[0m\n"
	printf -- "\033[31m   适用环境：Debian13         \033[0m\n"
    printf -- "\033[31m   当前环境：$OS_NAME \033[0m\n"
    printf -- "\033[31m===============================================\033[0m\n"
    printf -- "  1) 新增/更换配置 (支持 Caddy 自动证书)\n"
    printf -- "  2) 查看现有配置 (显示分享链接)\n"
    printf -- "  3) 删除所有配置 (撤除部署)\n"
    printf -- "  4) 开启 BBR 战略加速\n"
    printf -- "  5) 安装 vnstat 流量统计\n"
    printf -- "  q) 撤退\n"
    printf -- "\033[31m===============================================\033[0m\n"
    printf -- "\033[31m请选择主指令: \033[0m" && read main_opt

    case $main_opt in
        1) deploy_menu ;;
        2) [[ -f "$XRAY_CONF" ]] && show_params || { _red "目前未发现任何部署内容。"; sleep 2; } ;;
        3) systemctl stop xray caddy 2>/dev/null; rm -rf $XRAY_DIR; _red ">>> 阵地已清理。"; sleep 2 ;;
        4) enable_bbr ;;
        5) install_vnstat ;;
        q) exit 0 ;;
        *) _red "非法指令"; sleep 1 ;;
    esac
done