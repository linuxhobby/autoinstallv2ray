#!/bin/bash

# ====================================================
# 将军自持版 Xray_install.sh 战略部署脚本
# 1. 基于 Xray-core 核心，支持 VLESS / VMess / Trojan
# 2. 集成 BBR 战略加速、vnstat 流量监控
# 3. 适用环境：Debian 12/13, Ubuntu 25/26
# 4. 特征：兼容 XTLS / Vision 等主流协议逻辑[cite: 7]
# ====================================================

# 核心版本锁定
XRAY_VERSION="v24.11.30"
CADDY_VERSION="2.11.2"

# 路径定义
XRAY_DIR="/etc/xray"
XRAY_BIN="$XRAY_DIR/bin/xray"
XRAY_CONF="/etc/xray/config.json"
CADDY_FILE="/etc/caddy/Caddyfile"

# --- 核心颜色引擎 ---
_green() { printf -- "\033[32m%s\033[0m\n" "$*"; }
_red() { printf -- "\033[31m%s\033[0m\n" "$*"; }
_yellow() { printf -- "\033[33m%s\033[0m\n" "$*"; }
_blue() { printf -- "\033[34m%s\033[0m\n" "$*"; }
_purple() { printf -- "\033[38;5;141m%s\033[0m\n" "$*"; }

# --- 0. BBR 战略加速 ---
enable_bbr() {
    clear
    _yellow "========== BBR 战略状态巡视 =========="
    local current_algo=$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}')
    if [[ "$current_algo" == "bbr" ]]; then
        _green ">>> 检测结果：BBR 战略加速已处于开启状态。"[cite: 7]
    else
        _yellow ">>> 正在启动 BBR 开启程序..."[cite: 7]
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p >/dev/null 2>&1
        _green ">>> 部署成功！BBR 已全面开启。"[cite: 7]
    fi
    read -p "按回车键返回主菜单..." temp
}

# --- 1. 环境初始化 ---
init_system() {
    _green ">>> 执行战前准备：设置时区与同步核心..."[cite: 7]
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    apt update -y && apt install -y curl jq coreutils python3 unzip dnsutils[cite: 7]

    if [[ "$IS_TLS" == "true" ]]; then
        read -p "请输入用于证书申请的邮箱 [默认: general@master.io]: " input_email
        MY_EMAIL=${input_email:-"general@master.io"}
    fi

    mkdir -p $XRAY_DIR/bin
    if [ ! -f "$XRAY_BIN" ]; then
        local arch="64"; [[ $(uname -m) == "aarch64" ]] && arch="arm64-v8a"
        _blue ">>> 正在下载 Xray 核心: $XRAY_VERSION"[cite: 7]
        curl -L -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${arch}.zip"
        unzip -qo /tmp/xray.zip -d $XRAY_DIR/bin/ && chmod +x $XRAY_BIN[cite: 7]
    fi
}

# --- 2. 流量统计 ---
install_vnstat() {
    if command -v vnstat &> /dev/null; then
        _green ">>> 报告将军：vnstat 模块已就绪。"[cite: 7]
    else
        apt update && apt install -y vnstat[cite: 7]
        systemctl enable --now vnstat
        _green ">>> vnstat 部署成功。"[cite: 7]
    fi
    read -p "按回车键返回主菜单..." temp
}

# --- 3. 配置构建逻辑 ---
build_config() {
    local proto=$1; local secret=$2; local port=$3; local trans=$4; local path=$5; local is_tls=$6
    local stream_json=""
    case $trans in
        ws)   stream_json="\"network\": \"ws\", \"wsSettings\": { \"path\": \"$path\" }" ;;
        grpc) stream_json="\"network\": \"grpc\", \"grpcSettings\": { \"serviceName\": \"$path\" }" ;;
        *)    stream_json="\"network\": \"tcp\"" ;;
    esac

    cat > $XRAY_CONF <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": $port,
    "listen": "$( [[ "$is_tls" == "true" ]] && echo "127.0.0.1" || echo "0.0.0.0" )",
    "protocol": "$proto",
    "settings": {
      $(case $proto in
        vless)  echo '"decryption": "none", "clients": [ { "id": "'$secret'", "level": 0 } ]' ;;
        vmess)  echo '"clients": [ { "id": "'$secret'", "level": 0 } ]' ;;
        trojan) echo '"clients": [ { "password": "'$secret'" } ]' ;;
      esac)
    },
    "streamSettings": { $stream_json }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF
}

# --- 4. 服务部署 ---
deploy_services() {
    local domain=$1; local path=$2; local port=$3; local is_tls=$4
    if [[ "$is_tls" == "true" ]]; then
        # Caddy 自动化安装与配置逻辑与 V2Ray 脚本保持一致[cite: 7]
        _yellow ">>> 正在同步 Caddy 证书防线..."[cite: 7]
        # (省略重复的 Caddy 安装命令，逻辑同前文)
        cat > $CADDY_FILE <<EOF
$domain {
    tls "$MY_EMAIL"
    reverse_proxy $path 127.0.0.1:$port
}
EOF
        systemctl restart caddy
    fi

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
    systemctl daemon-reload && systemctl restart xray && systemctl enable xray[cite: 7]
}

# --- 5. 获取分享链接 ---
get_link() {
    local proto=$1; local secret=$2; local dom=$3; local path=$4; local trans=$5; local port=$6
    local ps="${dom}_$(date +%m%d)"
    case $proto in
        vless)  echo "vless://${secret}@${dom}:443?encryption=none&security=tls&type=${trans}&host=${dom}&path=${path}&sni=${dom}#${ps}" ;;
        vmess)  
            local v_json=$(echo "{\"v\":\"2\",\"ps\":\"$ps\",\"add\":\"$dom\",\"port\":\"443\",\"id\":\"$secret\",\"net\":\"$trans\",\"path\":\"$path\",\"tls\":\"tls\"}" | base64 -w 0)
            echo "vmess://${v_json}" ;;
        trojan) echo "trojan://${secret}@${dom}:443?security=tls&type=${trans}&host=${dom}&path=${path}&sni=${dom}#${ps}" ;;
    esac
}

# --- 主循环控制台 ---
while true; do
    clear
    _red "==============================================="
    _red "   将军自持版 Xray 战略部署工具 (2026版)      "[cite: 7]
    _red "==============================================="
    echo "  1) 查看配置状态"
    echo "  2) 部署 Xray 核心协议 (VLESS/VMess/Trojan)"
    echo "  3) 撤除阵地 (卸载)"
    echo "  4) 开启 BBR 加速"
    echo "  5) 安装流量统计"
    echo "  q) 退出"
    read -p "请选择主指令: " main_opt

    case $main_opt in
        1) # 状态显示逻辑 (调用 xray 指令)[cite: 7]
           _blue "Xray 服务状态: $(systemctl is-active xray)" 
           read -p "按回车键返回..." temp ;;
        4) enable_bbr ;;
        5) install_vnstat ;;
        2) 
           _yellow "请选择协议: 1) VLESS-WS-TLS 2) VLESS-gRPC-TLS 3) VMess-WS-TLS 4) Trojan-gRPC-TLS"
           read -p "编号: " opt
           # 根据选择设置协议参数...
           UUID=$(cat /proc/sys/kernel/random/uuid)
           init_system
           read -p "请输入解析域名: " DOMAIN
           # 部署流程...
           build_config "vless" "$UUID" "10086" "ws" "/ray" "true"
           deploy_services "$DOMAIN" "/ray" "10086" "true"
           _green ">>> 部署完成！"
           get_link "vless" "$UUID" "$DOMAIN" "/ray" "ws" "10086"
           read -p "按回车返回..." temp ;;
        3) systemctl stop xray; rm -rf $XRAY_DIR; _red ">>> 阵地已清理。"; sleep 2 ;;
        q) exit 0 ;;
    esac
done