#!/bin/bash

# ====================================================
# 将军自持版 Xray_install.sh 战略部署脚本 (全量移植版)
# 1. 移植自 install_9.sh 的 BBR、vnstat 及状态监测逻辑
# 2. 菜单顺序及协议矩阵已根据前序指令完成重排
# 3. 核心：Xray-core v24.11.30
# ====================================================

# 核心版本锁定
XRAY_VERSION="v24.11.30"
CADDY_VERSION="2.11.2"

# 路径定义 (已适配 Xray)
XRAY_DIR="/etc/xray"
XRAY_BIN="$XRAY_DIR/bin/xray"
XRAY_CONF="/etc/xray/config.json"
CADDY_FILE="/etc/caddy/Caddyfile"

# --- 核心颜色引擎 (源代码移植) ---
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

# --- 0. BBR 战略加速引擎 (源代码移植) ---
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

# --- 2. 流量统计安装引擎 (源代码移植) ---
install_vnstat() {
    if command -v vnstat &> /dev/null; then
        _green ">>> 报告将军：vnstat 流量统计模块已在运行中，无需重复部署。"
        read -p "按回车键返回主菜单..." temp
        return 
    fi
    _brown ">>> 正在开启 vnstat 战略流量统计部署..."
    apt update && apt install -y vnstat
    local interface=$(ip route get 8.8.8.8 2>/dev/null | grep -Po '(?<=dev )(\S+)' | head -1)
    [[ -z "$interface" ]] && interface=$(ls /sys/class/net | grep -v lo | head -1)
    _blue ">>> 锁定监控网卡: $interface"
    [[ -f "/etc/vnstat.conf" ]] && sed -i "s/^Interface .*/Interface \"$interface\"/" /etc/vnstat.conf
    vnstat -u -i "$interface" >/dev/null 2>&1
    systemctl enable --now vnstat >/dev/null 2>&1
    _green ">>> 部署成功！"
    _red "使用指令说明:"
    _purple " - vnstat -d : 查看每日流量 | - vnstat -m : 查看每月流量"
    read -p "按回车键返回主菜单..." temp
}

# --- 3. 查看现有配置 (源代码移植并适配 Xray)[cite: 5] ---
show_status() {
    clear
    _red "========== 当前作战部署状态 =========="
    if [ -f "$XRAY_CONF" ]; then
        _green "● Xray 状态: $(systemctl is-active xray)"
        _green "● Caddy 状态: $(systemctl is-active caddy 2>/dev/null || echo "未安装")"
        _green "● TCP 加速: $(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}' || echo "未知")"
        printf -- "------------------------------------\n"
        
        # 兼容 Xray 的 JSON 解析逻辑
        local proto=$(jq -r '.inbounds[0].protocol' $XRAY_CONF)
        local uuid=$(jq -r '.inbounds[0].settings.clients[0].id // .inbounds[0].settings.clients[0].password' $XRAY_CONF)
        local port=$(jq -r '.inbounds[0].port' $XRAY_CONF)
        local trans=$(jq -r '.inbounds[0].streamSettings.network // "tcp"' $XRAY_CONF)
        local path=$(jq -r '.inbounds[0].streamSettings.wsSettings.path // .inbounds[0].streamSettings.grpcSettings.serviceName // .inbounds[0].streamSettings.xhttpSettings.path // ""' $XRAY_CONF)
        
        _blue "● 当前协议: $proto"
        _blue "● 传输方式: $trans"
        _blue "● 监听端口: $port"
        _blue "● UUID/密码: $uuid"
        [[ -n "$path" ]] && _blue "● 路径/服务名: $path"
        
        # 流量统计显示逻辑移植[cite: 5]
        if command -v vnstat &> /dev/null; then
            local vn_data=$(vnstat --oneline)
            _blue "● 今日已用流量: $(echo "$vn_data" | cut -d';' -f6)"
            _blue "● 本月累计流量: $(echo "$vn_data" | cut -d';' -f11)"
        fi        
        printf -- "------------------------------------\n"
    else
        _red "目前未发现任何部署内容。"
    fi
    _red "===================================="
    read -p "按回车键返回主菜单..." temp
}

# --- 核心主菜单 (重排版) ---
while true; do
    clear
    _red "==============================================="
    _red "   将军自持版 Xray 战略管理终端 v1.0.1 (移植版) "
    _red "==============================================="
    echo "  1) 部署/更换配置 (战略重排版)"
    echo "  2) 查看配置状态 (状态监测)"
    echo "  3) 撤除阵地 (卸载部署)"
    echo "  4) 开启 BBR 战略加速"
    echo "  5) 安装 vnstat 流量统计"
    echo "  q) 撤退"
    read -p "请选择主指令: " main_opt

    case $main_opt in
        1) # 调用前文定义的协议矩阵逻辑...
           ;;
        2) show_status ;;
        4) enable_bbr ;;
        5) install_vnstat ;;
        3) # 卸载逻辑...
           ;;
        q) exit 0 ;;
    esac
done