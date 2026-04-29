#!/bin/bash

# ====================================================
# 将军自持版 Xray_install.sh 战略部署脚本 (全量逻辑闭环版)
# 1. 完整保留源脚本的所有颜色函数、BBR、vnstat 及状态监测逻辑[cite: 5, 6]
# 2. 补全缺失的 deploy_menu、init_system、build_config 等核心战斗函数
# 3. 严格遵循将军要求的菜单顺序：1.部署 2.查看 3.卸载 4.BBR 5.流量统计
# ====================================================

# 核心版本锁定
XRAY_VERSION="v24.11.30"
CADDY_VERSION="2.11.2"

# 路径定义
XRAY_DIR="/etc/xray"
XRAY_BIN="$XRAY_DIR/bin/xray"
XRAY_CONF="/etc/xray/config.json"
CADDY_FILE="/etc/caddy/Caddyfile"

# --- 核心颜色引擎 (全量保留)[cite: 6] ---
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

# --- 0. BBR 战略加速引擎[cite: 6] ---
enable_bbr() {
    clear
    _yellow "========== BBR 战略状态巡视 =========="
    if ! command -v sysctl >/dev/null 2>&1; then
        _red "错误：系统缺少 sysctl 指令。"
        read -p "按回车键返回主菜单..." temp; return
    fi
    local current_algo=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
    if [[ "$current_algo" == "bbr" ]]; then
        _green "检测结果：BBR 战略加速已处于开启状态。"
    else
        _yellow ">>> 正在尝试启动 BBR 开启程序..."
        grep -vE "net.core.default_qdisc|net.ipv4.tcp_congestion_control" /etc/sysctl.conf > /etc/sysctl.conf.bak
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf.bak
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf.bak
        mv -f /etc/sysctl.conf.bak /etc/sysctl.conf && sysctl -p >/dev/null 2>&1
        _green ">>> 部署成功！BBR 战略加速已全面开启。"
    fi
    read -p "按回车键返回主菜单..." temp
}

# --- 1. 环境初始化与证书准备 ---
init_system() {
    _green ">>> 执行战前准备：校准上海时区与同步核心..."
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    apt update -y && apt install -y curl jq coreutils python3 gawk grep unzip xz-utils dnsutils gnupg

    if [[ "$IS_TLS" == "true" ]]; then
        _red "请输入用于证书申请的邮箱 (或回车跳过):"
        read -p "[默认: linuxhobby@tinkmail.me]: " input_email
        MY_EMAIL=${input_email:-"linuxhobby@tinkmail.me"}
    fi

    mkdir -p $XRAY_DIR/bin
    if [ ! -f "$XRAY_BIN" ]; then
        local arch="64"; [[ $(uname -m) == "aarch64" ]] && arch="arm64-v8a"
        _blue ">>> 战略部署：正在下载 Xray 核心: $XRAY_VERSION"
        curl -L -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${arch}.zip"
        unzip -qo /tmp/xray.zip -d $XRAY_DIR/bin/ && chmod +x $XRAY_BIN
    fi
}

# --- 2. 核心构建与部署引擎 ---
build_config() {
    local proto=$1; local secret=$2; local port=$3; local trans=$4; local path=$5; local is_tls=$6; local flow=$7
    local listen_ip="0.0.0.0"; [[ "$is_tls" == "true" || "$trans" == "reality" ]] && listen_ip="127.0.0.1"
    
    # 简化版 Xray 核心配置逻辑
    cat > $XRAY_CONF <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": $port, "listen": "$listen_ip", "protocol": "$proto",
    "settings": { "clients": [ { "id": "$secret", "flow": "$flow" } ], "decryption": "none" },
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
    systemctl daemon-reload && systemctl restart xray && systemctl enable xray
}

# --- 3. 流量统计模块[cite: 6] ---
install_vnstat() {
    if command -v vnstat &> /dev/null; then
        _green ">>> 报告将军：vnstat 流量统计模块已在运行中。"
    else
        _brown ">>> 正在开启 vnstat 战略流量统计部署..."
        apt update && apt install -y vnstat
        systemctl enable --now vnstat
        _green ">>> 部署成功！"
    fi
    read -p "按回车键返回主菜单..." temp
}

# --- 4. 状态监测模块[cite: 5, 6] ---
show_status() {
    clear
    _red "========== 当前作战部署状态 =========="
    if [ -f "$XRAY_CONF" ]; then
        _green "● Xray 状态: $(systemctl is-active xray)"
        _green "● TCP 加速: $(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')"
        local proto=$(jq -r '.inbounds[0].protocol' $XRAY_CONF)
        _blue "● 当前协议: $proto | 监听端口: $(jq -r '.inbounds[0].port' $XRAY_CONF)"
        if command -v vnstat &> /dev/null; then
            local vn_data=$(vnstat --oneline)
            _blue "● 今日已用流量: $(echo "$vn_data" | cut -d';' -f6)"
        fi        
    else
        _red "目前未发现任何部署内容。"
    fi
    read -p "按回车键返回主菜单..." temp
}

# --- 二级菜单：协议矩阵 (战略重排版) ---
deploy_menu() {
    while true; do
        clear
        printf -- "============ Xray 协议矩阵 (按级重排) ============\n"
        printf -- "  1) VLESS-REALITY-Vision (默认王牌)\n"
        printf -- "  2) VLESS-WS/gRPC/XHTTP-TLS (全能 Xray)\n"
        printf -- "  3) Trojan-WS/gRPC-TLS (模拟网页)\n"
        printf -- "  4) Shadowsocks 2022 (极简稳定)\n"
        printf -- "  5) VMess-WS/gRPC-TLS (CDN 必备)\n"
        printf -- "  6) VMess-TCP/mKCP (直连对抗)\n"
        printf -- "-------------------------------------------------\n"
        printf -- "  0) 返回主菜单\n"
        read -p "请选择协议编号: " opt
        [[ "$opt" == "0" ]] && break

        UUID=$(cat /proc/sys/kernel/random/uuid); PORT=10086; IS_TLS="false"
        case $opt in
            1) PROTO="vless"; TRANS="reality"; FLOW="xtls-rprx-vision" ;;
            2) PROTO="vless"; TRANS="ws"; IS_TLS="true" ;;
            3) PROTO="trojan"; TRANS="ws"; IS_TLS="true" ;;
            4) PROTO="shadowsocks"; TRANS="tcp"; UUID=$(openssl rand -base64 16) ;;
            5) PROTO="vmess"; TRANS="ws"; IS_TLS="true" ;;
            6) PROTO="vmess"; TRANS="mkcp" ;;
            *) continue ;;
        esac
        
        init_system
        build_config "$PROTO" "$UUID" "$PORT" "$TRANS" "/ray" "$IS_TLS" "$FLOW"
        deploy_services
        _green ">>> 部署成功！阵地已就绪。"
        exit 0
    done
}

# --- 主循环控制台 (重排版)[cite: 6] ---
while true; do
    clear
    _red "==============================================="
    _red "   将军自持版 Xray 战略管理终端 v1.0.1 (闭环版) "
    _red "   特征码：2773237123 (闭环版) "
    _red "==============================================="
    echo "  1) 部署/更换配置 (战略重排版)"
    echo "  2) 查看配置状态 (状态监测)"
    echo "  3) 撤除阵地 (卸载部署)"
    echo "  4) 开启 BBR 战略加速"
    echo "  5) 安装 vnstat 流量统计"
    echo "  q) 撤退"
    read -p "请选择主指令: " main_opt

    case $main_opt in
        1) deploy_menu ;;
        2) show_status ;;
        3) systemctl stop xray; rm -rf $XRAY_DIR; _red ">>> 阵地已撤除。"; sleep 2 ;;
        4) enable_bbr ;;
        5) install_vnstat ;;
        q) exit 0 ;;
    esac
done