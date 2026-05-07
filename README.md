## 📥 一键安装
如果没有安装wget，请先安装
```
apt update && apt install wget -y
```
然后执行：
```bash
wget -O install.sh https://raw.githubusercontent.com/linuxhobby/xray-v2ray-install/refs/heads/main/install.sh \
&& chmod +x install.sh \
&& ./install.sh
```

---
# 🚀 Xray 一键安装脚本

> 基于 **Xray + Caddy** 的多协议一键部署脚本，支持 Reality / WS / gRPC / XHTTP / Trojan / VMess 等主流方案

---

*最后更新：2026-05-05*

## 📢 BUG 反馈

如果你发现任何问题，欢迎提交：

【反馈BUG】👉 https://github.com/linuxhobby/xray-v2ray-install/issues/1

---

## 📖 项目介绍

本脚本用于快速部署 Xray 服务端，集成 Caddy 自动配置 TLS，支持多种主流协议，开箱即用。

✔ 自动化安装  
✔ 自动申请 HTTPS 证书  
✔ 多协议一键切换  
✔ 极简交互操作  

---

## 🖥 推荐系统，已测试
- ✅ Debian 12 / 13  
- ✅ Ubuntu 25 / 26  

---

## 🖼 脚本界面展示

<img width="392" height="504" src="https://github.com/user-attachments/assets/6aa6fb72-4618-4b8a-bbce-f03e2201761c" />

---

## ⚠️ 安装前准备

### 1️⃣ VPS 服务器
- 一台带公网 IPv4 或 IPv6 的服务器

### 2️⃣ 域名（可选）
- 配置 A 记录解析到服务器 IP

📌 VLESS-REALITY 协议无需域名



---

## ✨ 功能特性

- 一键安装 Xray + Caddy
- 自动申请 TLS 证书
- 自动生成配置
- 自动输出分享链接
- 多协议支持

---

## 🔗 支持协议

- VLESS-REALITY（推荐）
- VLESS-WS-TLS
- VLESS-gRPC-TLS
- VLESS-XHTTP-TLS
- Trojan-WS-TLS
- Trojan-gRPC-TLS
- VMess-WS-TLS
- VMess-gRPC-TLS

---

## 📡 架构

客户端 → TLS → Caddy → Xray

---

## ❌ 卸载

运行脚本选择卸载即可

---

## ⚖️ 免责声明

仅供学习研究。

---

## ✍️ 作者

人生若只如初见
