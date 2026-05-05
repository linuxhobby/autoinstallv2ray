## 如果发现BUG，请在这里告诉我！  
### [BUG反馈] （https://github.com/linuxhobby/xray-v2ray-install/issues/1）
# 介绍 (最后更新：2026/05/04)
* 第1版：2026/04/26，以v2ray为内核，支持6中协议矩阵。  
* 第2版：2026/05/01，以xray为内核，支持6中协议矩阵。  

建议使用debian12/13系统，或Ubuntu25/26。  
目前脚本已经通过测试的系统：**Debian12/13**，**ubuntu25/26**。  
脚本界面展示：  
<img width="392" height="504" alt="image" src="https://github.com/user-attachments/assets/6aa6fb72-4618-4b8a-bbce-f03e2201761c" />


## 安装之前......您需要
* **1台带公网IPv4/ipv6的VPS服务器**
* **1个域名**（也可以不要）
    * 如果使用VLESS-REALITY-Vision，可以不需要域名。
    * 在域名管理后台，把域名与IP之间做好解析设置，A记录。

## 一键下载安装 
如果没有安装wget，先安装wget
```
apt update
apt install wget -y
```
**推荐** 安装xray内核，请执行下面代码，本版本相关内核版本：xray：v26.3.27，caddy：v2.8.4
```
wget -O install_xray.sh https://raw.githubusercontent.com/linuxhobby/xray-v2ray-install/master/install_xray.sh && chmod +x install_xray.sh && ./install_xray.sh
```
安装v2ra内核，请执行：
```
wget -O install_v2ray.sh https://raw.githubusercontent.com/linuxhobby/xray-v2ray-install/master/install_v2ray.sh && chmod +x install_v2ray.sh && ./install_v2ray.sh
```

# 两个脚本对比

 `install_v2ray.sh` 和 `install_xray.sh` 两个脚本均支持Debian、Ubuntu系统，其他系统没有测试过，估计也测试不通，因为脚本使用apt指令安装软件包、兼容性。

## 1. 核心架构对比

| 维度 | `install_v2ray.sh` | `install_xray.sh` |
| :--- | :--- | :--- |
| **核心内核** | V2Ray Core (v5.49.0) | Xray Core (26.3.27) |
| **反向代理** | Caddy v2.11.2 | Caddy v2.8.4 |
| **主要定位** | 经典、成熟、稳定的协议环境 | 高性能、前沿抗封锁技术栈 |
| **加密技术** | 传统 TLS 证书依赖 | 支持 REALITY 无证书伪装技术 |

## 2. 协议支持矩阵

`install_xray.sh` 提供了更现代化的协议选择，特别是在对抗高强度检测方面具有优势。

* **通用支持**：两者均支持 VLESS/VMess/Trojan 搭配 WebSocket (WS) 或 gRPC。
* **Xray 独有增强**：
    * **VLESS-REALITY-Vision**：目前最先进的方案，消除 TLS 指纹，无需购买域名。
    * **VLESS-XHTTP**：新型传输协议，进一步提升伪装深度。
    * **流控优化**：支持 XTLS 的 Vision 流控。

## 3. 安装与逻辑增强

### 3.1 环境预检
* **V2Ray 脚本**：基础的域名解析 (dig/host) 检查。
* **Xray 脚本**：更强大的预检逻辑。支持 IPv4/IPv6 双栈检测，并集成了 `apt-get` 锁定解除机制（针对 `apt-mark hold`），有效防止因系统后台更新导致的安装冲突。

### 3.2 系统安全
* **Xray 脚本**：在配置过程中强制管理 `ufw` 防火墙，并自动配置 SSH 端口白名单，安全性更高。
* **V2Ray 脚本**：仅对业务端口进行简单的开放处理。

## 4. 易用性与交互功能

| 功能 | `install_v2ray.sh` | `install_xray.sh` |
| :--- | :--- | :--- |
| **实时状态** | 基础菜单显示 | 自动显示 IP、协议类型、服务及流量监控状态 |
| **二维码导出** | 不支持 | **集成 qrencode**，安装后直接终端扫码导入 |
| **分享链接** | 纯文本输出 | 优化后的文本链接 + 二维码 |
| **流量统计** | 需进入二级菜单查看 | 主界面直观展示 vnstat 运行状态 |

## 5. 卸载与清理机制

* **V2Ray 脚本**：提供基础的配置和二进制文件删除。
* **Xray 脚本**：执行**深度清理**逻辑。不仅删除配置文件，还会调用官方 `install-release.sh` 移除内核，清理 `systemd` 残余服务单元，并自动执行 `apt autoremove` 保持系统纯净。

---

## 结论与建议

### 🚀 移动端推荐使用 `install_xray.sh`
如果您追求：
1. **免域名方案**（使用 REALITY）。
2. **手机端快速配制**（使用二维码）。
3. **更强的系统兼容性**（自动处理 apt 锁定）。

### 🛡️ 电脑端推荐使用 `install_v2ray.sh`
如果您追求：
1. **传统环境的极度兼容性**。
2. **特定的 Caddy 2.11 版本特性**。

---
*报告生成时间：2026-05-05*

作者签名：人生若只如初见

