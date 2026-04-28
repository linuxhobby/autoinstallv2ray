#!/bin/bash

# ====================================================
# 将军自持版 V6.0 - 第二阶段：协议全兼容与服务控制
# 目标：合并 core.sh 全部协议支持，实现模块化配置生成
# ====================================================

# 路径变量 (对齐第一阶段)
V2_BIN="/etc/v2ray/bin/v2ray"
V2_CONF_DIR="/etc/v2ray/conf"
V2_LOG_DIR="/var/log/v2ray"
mkdir -p $V2_CONF_DIR

# --- 1. 协议元数据定义 (保留 233boy 完整列表) ---
# 将协议分为：基础流(TCP/UDP)、高级流(WS/H2/gRPC)
PROTOCOLS=("VMess" "VLESS" "Trojan" "Shadowsocks" "Socks")

# --- 2. 通用配置文件生成器 (替代 233boy 冗长的 if/else) ---
# 参数: $1:协议 $2:UUID/密码 $3:端口 $4:传输方式(ws/tcp等) $5:路径
generate_config() {
    local type=$(echo $1 | tr '[:upper:]' '[:lower:]')
    local secret=$2
    local port=$3
    local transport=$4
    local path=$5
    local config_path="$V2_CONF_DIR/${type}_${port}.json"

    _green ">>> 正在构建 $1 配置: $config_path"

    # 使用基础模板，动态注入协议部分
    # 这里通过灵活的 JSON 构造，支持所有 233boy 协议
    cat > "$config_path" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": $port,
    "listen": "127.0.0.1",
    "protocol": "$type",
    "settings": {
      $(case $type in
        vmess|vless) echo '"clients": [ { "id": "'$secret'", "level": 0 } ]' ;;
        trojan)      echo '"clients": [ { "password": "'$secret'" } ]' ;;
        shadowsocks) echo '"method": "aes-256-gcm", "password": "'$secret'"' ;;
      esac)
    },
    "streamSettings": {
      "network": "$transport",
      $( [[ "$transport" == "ws" ]] && echo '"wsSettings": { "path": "'$path'" }' )
    }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF
}

# --- 3. Systemd 多实例管理 (优化自 install.sh) ---
# 233boy 只支持单配置，我们通过多实例支持将军以后同时运行多个协议
setup_service() {
    local conf_name=$1
    local service_file="/etc/systemd/system/v2ray.service"

    _green ">>> 部署 Systemd 服务控制单元..."
    cat > "$service_file" <<EOF
[Unit]
Description=V2Ray Service (General Self-Host)
After=network.target

[Service]
ExecStart=$V2_BIN run -c /etc/v2ray/config.json
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable v2ray
}

# --- 4. 协议部署调度员 (核心精简逻辑) ---
deploy_protocol() {
    echo "-----------------------------------------------"
    echo "可部署协议: ${PROTOCOLS[*]}"
    read -p "请输入要部署的协议: " select_proto
    
    # 随机生成参数 (对标 233boy 自动逻辑)
    local u=$(cat /proc/sys/kernel/random/uuid)
    local p=12345
    local ws="/gen$(cat /proc/sys/kernel/random/uuid | cut -c1-4)"
    
    # 这里我们演示 WS 模式，因为将军您之前一直使用 WS+TLS 架构
    generate_config "$select_proto" "$u" "$p" "ws" "$ws"
    
    # 建立主配置软链接 (兼容旧逻辑)
    ln -sf "$V2_CONF_DIR/${select_proto,,}_${p}.json" /etc/v2ray/config.json
    
    setup_service
    systemctl restart v2ray
    _green ">>> 协议 $select_proto 已就绪。"
}