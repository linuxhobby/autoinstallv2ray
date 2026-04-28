#!/bin/bash

# 1. 定义带有时间戳的动态 URL，破解 GitHub CDN 缓存
URL="https://raw.githubusercontent.com/linuxhobby/auto-install-v2ray/master/install.sh?v=$(date +%s)"

_yellow() { printf -- "\033[33m%s\033[0m\n" "$*"; }

_yellow ">>> 正在清理旧版残余..."
rm -f install.sh*
rm -f install_v2.sh*

_yellow ">>> 正在从阵地抓取最新战略脚本..."
# 2. 增加 --tries 和 --timeout 确保在弱网下重试，并强制不使用服务器缓存
wget --no-cache --no-check-certificate --tries=3 --timeout=15 -O install.sh "$URL"

if [ $? -eq 0 ]; then
    chmod +x install.sh
    _yellow ">>> 抓取成功，立即执行部署..."
    ./install.sh
else
    printf -- "\033[31m[错误] 无法连接到 GitHub，请检查网络或代理设置。\033[0m\n"
    exit 1
fi