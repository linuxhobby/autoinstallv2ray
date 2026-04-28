# 介绍 (最后更新：2026/04/28)
 
本项目forked自233boy，对233boy的一键安装脚本做了完全的重构与合并，做了大量代码精简。

## 一键下载安装 
如果没有安装wget，先安装wget
```
apt update
apt install wget
```
然后执行  
```
wget -O install.sh https://raw.githubusercontent.com/linuxhobby/auto-install-v2ray/master/install.sh && chmod +x install.sh && ./install.sh
```
---

## 1. 逻辑重构：从“流程化”转向“模块化”
* **代码解耦**：原脚本多采用长流程线性嵌套，本脚本将核心逻辑的实现**函数化**。
    * 拆分为：环境初始化 (`init_system`)、配置生成 (`build_config`)、服务部署 (`deploy_services`) 及链接生成 (`get_link`)。
    * **战术意义**：当需要扩充第 18、19 种新协议时，仅需在 `case` 逻辑中追加参数，无需变动底层安装架构。
* **交互简化**：大幅度削减了冗余的询问过程。
    * 通过自动生成 UUID 和随机路径 (`WPATH`) 减少人工操作。
    * 仅在涉及 TLS 域名验证等关键节点时才触发交互，提升了部署效率。

---

## 2. 功能精简与聚焦
* **剔除杂质**：彻底去除了常见的推广信息、广告以及复杂的第三方统计插件，确保脚本纯净、安全。
* **环境预设**：强制同步 **上海时区**，毕竟这个脚本也只有大陆才会用到。
* **依赖优化**：舍弃了复杂的跨发行版兼容性检测，精准聚焦于 **Debian/Ubuntu** 环境。
    * 利用 `apt` 快速调用 `jq`、`curl` 与 `caddy`，确保存储开销最小化。

---

## 3. 核心维度对比矩阵

| 维度 | 233boy 脚本 | 本将军自持版 (当前脚本) |
| :--- | :--- | :--- |
| **反向代理** | 采用 Nginx (配置较重) | 切换为 **Caddy**，配置极简且实现证书自动申领 |
| **减少供应链** | 233boy有部分固定配置 | 切换为全部采用 **v2ray** 和 **Caddy** 的官方拉去资源，减少供应链 |
| **协议多样性** | 聚焦于主流的17种固定组合协议 | 保持**17 协议全阵列**，涵盖 gRPC、H2 等前沿变体，但是可方便添加和删减，不需要修改太多代码 |
| **标识习惯** | 节点名多为随机字符 | 自动注入 **域名 + 日期** (如 `domain_0425`)，便于快速识别 |
| **系统侵入性** | 包含较多自定义变量与复杂路径 | 路径标准化为 `/etc/v2ray`，由 `systemd` 原生管理 |
| **链接生成** | 依赖脚本内嵌的简单 Base64 逻辑 | 调用 **Python3 (urllib.parse)**，确保特殊字符下的绝对兼容 |

---

## 4. 战术差异总结

233boy 脚本更倾向于面向大众的“**通用全能包**”，带有较强的新手引导属性；本脚本则是自定义的身定制版“**快速部署模板**”。

**核心优势：**
1. **深度适配**：完美契合您的命名习惯与时区需求。
2. **核心导向**：剥离所有非必要功能，仅保留最强悍的配置引擎。
3. **阵地清理**：集成的 **资产清查（选项 3）** 功能具备联动销毁机制，在撤除部署时会一并清除 Caddy 反代设置，确保系统阵地的绝对洁净。

---

原233boy的脚本贴点： 
# 特点

- 快速安装
- 超级好用
- 零学习成本
- 自动化 TLS
- 简化所有流程
- 屏蔽 BT
- 屏蔽中国 IP
- 使用 API 操作
- 兼容 V2Ray 命令
- 强大的快捷参数
- 支持所有常用协议
- 一键添加 Shadowsocks
- 一键添加 VMess-(TCP/mKCP/QUIC)
- 一键添加 VMess-(WS/H2/gRPC)-TLS
- 一键添加 VLESS-(WS/H2/gRPC)-TLS
- 一键添加 Trojan-(WS/H2/gRPC)-TLS
- 一键添加 VMess-(TCP/mKCP/QUIC) 动态端口
- 一键启用 BBR
- 一键更改伪装网站
- 一键更改 (端口/UUID/密码/域名/路径/加密方式/SNI/动态端口/等...)
- 还有更多...

# 设计理念

设计理念为：**高效率，超快速，极易用**

脚本基于作者的自身使用需求，以 **多配置同时运行** 为核心设计

并且专门优化了，添加、更改、查看、删除、这四项常用功能

你只需要一条命令即可完成 添加、更改、查看、删除、等操作

例如，添加一个配置仅需不到 1 秒！瞬间完成添加！其他操作亦是如此！

脚本的参数非常高效率并且超级易用，请掌握参数的使用

# 脚本说明

[V2Ray 一键安装脚本](https://github.com/233boy/v2ray/wiki/V2Ray%E4%B8%80%E9%94%AE%E5%AE%89%E8%A3%85%E8%84%9A%E6%9C%AC)

# 搭建教程

[V2Ray搭建详细图文教程](https://github.com/233boy/v2ray/wiki/V2Ray%E6%90%AD%E5%BB%BA%E8%AF%A6%E7%BB%86%E5%9B%BE%E6%96%87%E6%95%99%E7%A8%8B)

# 帮助

使用: `v2ray help`

```
V2Ray script v4.21 by 233boy
Usage: v2ray [options]... [args]...

基本:
   v, version                                      显示当前版本
   ip                                              返回当前主机的 IP
   get-port                                        返回一个可用的端口

一般:
   a, add [protocol] [args... | auto]              添加配置
   c, change [name] [option] [args... | auto]      更改配置
   d, del [name]                                   删除配置**
   i, info [name]                                  查看配置
   qr [name]                                       二维码信息
   url [name]                                      URL 信息
   log                                             查看日志
   logerr                                          查看错误日志

更改:
   dp, dynamicport [name] [start | auto] [end]     更改动态端口
   full [name] [...]                               更改多个参数
   id [name] [uuid | auto]                         更改 UUID
   host [name] [domain]                            更改域名
   port [name] [port | auto]                       更改端口
   path [name] [path | auto]                       更改路径
   passwd [name] [password | auto]                 更改密码
   type [name] [type | auto]                       更改伪装类型
   method [name] [method | auto]                   更改加密方式
   seed [name] [seed | auto]                       更改 mKCP seed
   new [name] [...]                                更改协议
   web [name] [domain]                             更改伪装网站

进阶:
   dns [...]                                       设置 DNS
   dd, ddel [name...]                              删除多个配置**
   fix [name]                                      修复一个配置
   fix-all                                         修复全部配置
   fix-caddyfile                                   修复 Caddyfile
   fix-config.json                                 修复 config.json

管理:
   un, uninstall                                   卸载
   u, update [core | sh | dat | caddy] [ver]       更新
   U, update.sh                                    更新脚本
   s, status                                       运行状态
   start, stop, restart [caddy]                    启动, 停止, 重启
   t, test                                         测试运行
   reinstall                                       重装脚本

测试:
   client [name]                                   显示用于客户端 JSON, 仅供参考
   debug [name]                                    显示一些 debug 信息, 仅供参考
   gen [...]                                       同等于 add, 但只显示 JSON 内容, 不创建文件, 测试使用
   genc [name]                                     显示用于客户端部分 JSON, 仅供参考
   no-auto-tls [...]                               同等于 add, 但禁止自动配置 TLS, 可用于 *TLS 相关协议
   xapi [...]                                      同等于 v2ray api, 但 API 后端使用当前运行的 V2Ray 服务

其他:
   bbr                                             启用 BBR, 如果支持
   bin [...]                                       运行 V2Ray 命令, 例如: v2ray bin help
   api, convert, tls, run, uuid  [...]             兼容 V2Ray 命令
   h, help                                         显示此帮助界面

谨慎使用 del, ddel, 此选项会直接删除配置; 无需确认
反馈问题) https://github.com/233boy/v2ray/issues
文档(doc) https://233boy.com/v2ray/v2ray-script/
```
