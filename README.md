# 介绍 (最后更新：2026/04/28)
第1版：2026/04/26，以v2ray为内核，支持6中协议矩阵。  
第2版：2026/05/01，以xray为内核，支持6中协议矩阵。  

建议使用debian12/13系统，或Ubuntu25/26。  
目前脚本已经通过测试的系统：**Debian12/13**，**ubuntu25/26**。  
脚本界面展示：  
<img width="502" height="434" alt="image" src="https://github.com/user-attachments/assets/5bf2c390-9457-4691-a6e4-0886c77e4b46" />

## 安装之前......您需要
* **1台带公网IPv4/ipv6的VPS服务器**
* **1个域名**（也可能不要）
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
wget -O install_xray.sh https://raw.githubusercontent.com/linuxhobby/autoinstallv2ray/master/install_xray.sh && chmod +x install_xray.sh && ./install_xray.sh
```
安装v2ra内核，请执行：
```
wget -O install_v2ray.sh https://raw.githubusercontent.com/linuxhobby/autoinstallv2ray/master/install_v2ray.sh && chmod +x install_v2ray.sh && ./install_v2ray.sh
```

---
## 1. 脚本总结
本脚本为个人兴趣所作，非商业化、非营利性的业余之作“**快速部署脚本**”。
因为我个人一般使用Debian作为底座平台，所以本测试主要在debian平台上。

**核心优势：**
1. **深度适配**：完美适配Debian、Ubuntu系统，自动处理多种错误的冗余操作。
2. **核心导向**：脚本中没有太多复杂功能，非必要功能一律不要，仅保留最强悍的配置引擎。
3. **阵地清理**：集成的 **删除所有配置（选项 3）** 功能具备联动销毁机制，在撤除部署时会一并清除 Caddy 反代设置，确保系统阵地的绝对洁净。

## 2. 逻辑重构：从“流程化”转向“模块化”
* **代码解耦**：本脚本将核心逻辑的实现**函数化**。
    * 分为：环境初始化 (`init_system`)、配置生成 (`build_config`)、服务部署 (`deploy_services`) 及链接生成 (`get_link`)。
    * **战术意义**：当需要扩充更多种新协议时，仅需在 `case` 逻辑中追加参数，无需变动底层安装架构。
* **交互简化**：尽量采用自动化，最大限度削减了冗余的询问过程，脚本更加实用。
    * 通过自动生成 UUID 和随机路径 (`WPATH`) 减少人工操作。
    * 仅在涉及 TLS 域名验证等关键节点时才触发交互，提升了部署效率。

---

## 3. 功能精简与聚焦
* **剔除杂质**：没有推广信息、广告以及复杂的第三方统计插件，确保脚本纯净、安全。
* **环境预设**：强制同步 **上海时区**，毕竟这个脚本也只有大陆才会用到。
* **依赖优化**：舍弃了复杂的跨发行版兼容性检测，精准聚焦于 **Debian/Ubuntu** 环境。
* **性能优势**：利用 `apt` 快速调用 `jq`、`curl` 与 `caddy`，确保存储开销最小化。

---

## 4. 脚本特点

| 维度 | 特点 |
| :--- | :--- |
| **反向代理** | 使用 **Caddy**，配置极简且实现证书自动申领 |
| **减少供应链** | 全部采用直接到 **xray/v2ray** 和 **Caddy** 官方库拉去资源，减少供应链 ，增加安全可靠性|
| **协议多样性** | 目前支持 **多个协议全阵列**，涵盖 gRPC、H2 等前沿变体，但是可方便添加和删减，不需要修改太多代码 |
| **标识习惯** | 自动注入 **域名 + 日期** (如 `domain_0425`)，便于快速识别 |
| **系统侵入性** | 路径标准化为 `/etc/v2ray`，由 `systemd` 原生管理 |
| **链接生成** | 调用 **Python3 (urllib.parse)**，确保特殊字符下的绝对兼容 |

---

作者签名：人生若只如初见

