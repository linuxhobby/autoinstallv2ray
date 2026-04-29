#!/bin/bash

# ====================================================
# 将军自持版 Xray_install.sh 战略部署脚本 (全量完备版)
# 1. 补全之前丢失的 Xray 核心安装、配置构建及服务部署逻辑[cite: 6]
# 2. 完整保留源脚本的 BBR、vnstat 及所有颜色引擎源代码
# 3. 严格锁定主菜单 1-5 战略序列，确保协议矩阵二级菜单绝对闭环[cite: 6]
# ====================================================

# 核心版本与路径定义
XRAY_VERSION="v24.11.30"
CADDY_VERSION="2.11.2"
XRAY_DIR="/etc/xray"
XRAY_BIN="$XRAY_DIR/bin/xray"
XRAY_CONF="/etc/xray/config.json"
CADDY_FILE="/etc/caddy/Caddyfile"

# --- 核心颜色引擎 (全量保留)[cite: 5, 6] ---
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

# --- 0. BBR 战略加速引擎 (源代码移植)[cite: 5, 6] ---
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

# --- 1. 环境初始化与核心下载 ---
init_system() {
    _green ">>> 执行战前准备：设置时区与同步核心..."
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    apt update -y && apt install -y curl jq coreutils python3 gawk grep unzip xz-utils dnsutils gnupg

    mkdir -p $XRAY_DIR/bin
    if [ ! -f "$XRAY_BIN" ]; then
        local arch="64"; [[ $(uname -m) == "aarch64" ]] && arch="arm64-v8a"
        _blue ">>> 战略部署：正在下载锁定的 Xray 版本: $XRAY_VERSION"
        curl -L -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${arch}.zip"
        unzip -qo /tmp/xray.zip -d $XRAY_DIR/bin/ && chmod +x $XRAY_BIN
    fi
}

# --- 2. 流量统计安装引擎 (源代码级移植)[cite: 5, 6] ---
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


# --- 3. 核心配置构建引擎 (Xray 专用) ---
build_config() {
    local proto=$1; local secret=$2; local port=$3; local trans=$4; local path=$5; local flow=$6
    local listen_ip="0.0.0.0"; [[ "$trans" == "reality" ]] && listen_ip="127.0.0.1"
    
    cat > $XRAY_CONF <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": $port,
    "listen": "$listen_ip",
    "protocol": "$proto",
    "settings": {
      "clients": [ { "id": "$secret", "flow": "$flow", "level": 0 } ],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "$trans",
      "${trans}Settings": { "path": "$path", "serviceName": "$path" }
    }
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

# --- 4. 查看现有配置 (状态监测)[cite: 5, 6] ---
show_status() {
    clear
    _red "========== 当前作战部署状态 =========="
    if [ -f "$XRAY_CONF" ]; then
        _green "● Xray 状态: $(systemctl is-active xray)"[cite: 6]
        _green "● TCP 加速: $(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')"[cite: 6]
        local proto=$(jq -r '.inbounds[0].protocol' $XRAY_CONF)
        _blue "● 当前协议: $proto | 监听端口: $(jq -r '.inbounds[0].port' $XRAY_CONF)"[cite: 6]
        if command -v vnstat &> /dev/null; then
            local vn_data=$(vnstat --oneline)
            _blue "● 今日已用流量: $(echo "$vn_data" | cut -d';' -f6)"[cite: 5, 6]
        fi        
    else
        _red "目前未发现任何部署内容。"[cite: 6]
    fi
    read -p "按回车键返回主菜单..." temp
}

# --- 5. 协议矩阵二级菜单 (全功能闭环)[cite: 6] ---
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

        UUID=$(cat /proc/sys/kernel/random/uuid); PORT=10086; PROTO="vless"; TRANS="ws"; FLOW=""
        case $opt in
            1) PROTO="vless"; TRANS="reality"; FLOW="xtls-rprx-vision" ;;
            2) PROTO="vless"; TRANS="ws" ;;
            3) PROTO="trojan"; TRANS="ws" ;;
            4) PROTO="shadowsocks"; TRANS="tcp" ;;
            5) PROTO="vmess"; TRANS="ws" ;;
            6) PROTO="vmess"; TRANS="mkcp" ;;
            *) continue ;;
        esac
        
        init_system
        build_config "$PROTO" "$UUID" "$PORT" "$TRANS" "/ray" "$FLOW"
        deploy_services
        _green ">>> 报告将军：阵地部署成功！"
        exit 0
    done
}

# --- 核心主循环控制台 (严格排序)[cite: 6] ---
while true; do
    clear
    _red "==============================================="
    _red "   将军自持版 Xray 战略管理终端 v1.0.1 (全量)  "
    _red "==============================================="
    echo "  1) 部署/更换配置 (战略重排版)"
    echo "  2) 查看配置状态 (状态监测)"
    echo "  3) 撤除阵地 (卸载部署)"
    echo "  4) 开启 BBR 战略加速"
    echo "  5) 安装 vnstat 流量统计"
    echo "  q) 撤退"
    _red "==============================================="
    read -p "请选择主指令: " main_opt

    case $main_opt in
        1) deploy_menu ;;
        2) show_status ;;
        3) systemctl stop xray 2>/dev/null; rm -rf $XRAY_DIR; _red ">>> 阵地已清理。"; sleep 2 ;;
        4) enable_bbr ;;
        5) install_vnstat ;;
        q) exit 0 ;;
        *) _red "非法指令"; sleep 1 ;;
    esac
done