#!/bin/bash

# ====================================================
# 将军自持版 V6.0 - 第三阶段：Caddy 自动化与链接生成
# 目标：实现自动 TLS 闭环与全协议链接算法
# ====================================================

# 路径定义
CADDY_BIN="/usr/bin/caddy"
CADDY_FILE="/etc/caddy/Caddyfile"

# --- 1. Caddy 极简部署 (重构自 caddy.sh) ---
# 233boy 使用了复杂的站点目录结构，我们简化为单一控制文件
install_caddy() {
    if ! command -v caddy &> /dev/null; then
        _green ">>> 正在从官方源安装 Caddy (自动化 TLS)..."
        apt install -y debian-keyring debian-archive-keyring apt-transport-https
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
        apt update && apt install caddy -y
    fi
}

setup_caddy_proxy() {
    local domain=$1
    local path=$2
    local port=$3

    _green ">>> 配置 Caddy 反向代理: $domain -> $port$path"
    cat > $CADDY_FILE <<EOF
$domain {
    tls your-email@example.com
    reverse_proxy $path 127.0.0.1:$port
    handle {
        root * /var/www/html
        file_server
    }
}
EOF
    systemctl restart caddy
}

# --- 2. 万能链接生成引擎 (重构自 help.sh，彻底解耦) ---
# 参数：$1:协议 $2:域名 $3:UUID $4:路径
get_share_link() {
    local proto=$(echo $1 | tr '[:upper:]' '[:lower:]')
    local domain=$2
    local uuid=$3
    local path=$4
    local ps="General_SelfHost_$(date +%m%d)"

    case $proto in
        vless)
            # VLESS 链接不需要 Base64
            echo "vless://${uuid}@${domain}:443?encryption=none&security=tls&type=ws&host=${domain}&path=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$path'))")#$ps"
            ;;
        vmess)
            # VMess 链接必须构造 JSON 后转 Base64
            local vmess_json=$(cat <<EOF
{"v":"2","ps":"$ps","add":"$domain","port":"443","id":"$uuid","aid":"0","net":"ws","type":"none","host":"$domain","path":"$path","tls":"tls"}
EOF
            )
            echo "vmess://$(echo -n $vm_json | base64 -w 0)"
            ;;
        trojan)
            echo "trojan://${uuid}@${domain}:443?security=tls&type=ws&host=${domain}&path=${path}#$ps"
            ;;
    esac
}

# --- 3. 最终流程闭环 ---
finalize_deployment() {
    echo "-----------------------------------------------"
    read -p "请输入您要绑定的解析域名: " target_domain
    
    # 假设已在第二阶段生成了配置
    # 这里从本地配置文件读取参数
    local proto=$(jq -r '.inbounds[0].protocol' /etc/v2ray/config.json)
    local uuid=$(jq -r '.inbounds[0].settings.clients[0].id // .inbounds[0].settings.clients[0].password' /etc/v2ray/config.json)
    local path=$(jq -r '.inbounds[0].streamSettings.wsSettings.path' /etc/v2ray/config.json)
    local port=$(jq -r '.inbounds[0].port' /etc/v2ray/config.json)

    install_caddy
    setup_caddy_proxy "$target_domain" "$path" "$port"
    
    _green ">>> 部署成功！您的分享链接为："
    get_share_link "$proto" "$target_domain" "$uuid" "$path"
    echo "-----------------------------------------------"
}