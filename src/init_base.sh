#!/bin/bash

# ====================================================
# 将军自持版 V6.0 - 第一阶段：环境与官方核心自持
# 目标：合并 install/download/bbr，支持 Debian 12/13
# ====================================================

# 字体颜色定义 (精简 233boy 的定义)
_green() { echo -e "\033[32m$@\033[0m"; }
_red() { echo -e "\033[31m$@\033[0m"; }
_yellow() { echo -e "\033[33m$@\033[0m"; }

# 1. 环境初始化 (合并自 install.sh)
# 针对 Debian 12/13 优化，确保 base64/jq/python3 绝对就位
init_env() {
    _green ">>> 正在初始化 Debian 12/13 环境..."
    apt-get update -y
    apt-get install -y curl jq coreutils python3 python3-pip gawk grep unzip xz-utils
    
    # 检查 root 权限 (保留安全红线)
    [[ $EUID != 0 ]] && { _red "错误：必须使用 ROOT 用户运行。"; exit 1; }
    
    # 创建必要的目录结构
    mkdir -p /etc/v2ray/sh
    mkdir -p /etc/v2ray/bin
    mkdir -p /var/log/v2ray
}

# 2. 官方核心下载逻辑 (重构自 download.sh)
# 彻底废弃 233boy 的第三方 zip 包，直接从 V2fly 官方 GitHub 获取
fetch_v2ray_core() {
    _green ">>> 正在从官方源同步 V2Ray 核心..."
    
    # 自动识别系统架构 (x86_64 / arm64)
    local arch="64"
    [[ $(uname -m) == "aarch64" ]] && arch="arm64-v8a"
    
    # 获取官方最新版本号 (API 动态获取，解决 404 隐患)
    local latest_ver=$(curl -s https://api.github.com/repos/v2fly/v2ray-core/releases/latest | jq -r .tag_name)
    
    if [[ -z "$latest_ver" || "$latest_ver" == "null" ]]; then
        _red "获取版本失败，请检查网络（特别是访问 GitHub API 的能力）。"
        exit 1
    fi
    
    _yellow "检测到官方最新版本: $latest_ver"
    local dl_url="https://github.com/v2fly/v2ray-core/releases/download/${latest_ver}/v2ray-linux-${arch}.zip"
    
    # 下载并解压到自持目录
    curl -L -o /tmp/v2ray.zip "$dl_url"
    unzip -qo /tmp/v2ray.zip -d /etc/v2ray/bin/
    chmod +x /etc/v2ray/bin/v2ray
    
    _green "核心组件已成功部署至 /etc/v2ray/bin/"
}

# 3. 内置 BBR 优化 (合并自 bbr.sh)
# 针对 Debian 12/13 默认高版本内核，直接开启不再做复杂判断
enable_bbr() {
    _green ">>> 正在配置系统内核优化 (BBR)..."
    if ! sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
        sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p > /dev/null
        _green "BBR 加速已开启。"
    else
        _yellow "BBR 已经在运行中。"
    fi
}

# 4. 初始化主程序 (第一阶段集成测试)
main_stage1() {
    clear
    echo "==============================================="
    echo "       将军自持版 V6.0 环境部署阶段            "
    echo "==============================================="
    init_env
    fetch_v2ray_core
    enable_bbr
    _green "第一阶段：环境对齐与核心部署已完成。"
}

# 运行第一阶段
main_stage1