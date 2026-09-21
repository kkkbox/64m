
# Alpine 64MB VPS sing-box (VLESS-Reality) 一键搭建脚本

专为 **64M 小内存** 的 Alpine Linux 系统（支持 i686/386 或 amd64 架构）深度优化的 `sing-box` (VLESS-Reality) 一键搭建与内存调优脚本。

---

## 💡 特性与优化

1. **极致省内存（防 OOM）**：
* 自动检测系统 Swap，若无则自动创建 128MB 虚拟内存，防止安装或解压时发生 OOM 崩溃。
* 针对 Go 语言运行时强制注入低内存限制环境变量（`GOGC=20`、`GOMEMLIMIT=20MiB`），让 `sing-box` 在极小内存下也能稳定运行。


2. **纯 POSIX Shell 编写**：兼容 Alpine 默认的 `ash` 解释器，无需安装沉重的 `bash`。
3. **完美适配新版语法**：兼容最新版本 `sing-box` 的配置文件结构（避免了 `server_options` 等废弃字段导致的崩溃问题）。
4. **轻量依赖**：仅需基础工具（`wget`、`tar`、`gcompat`、`jq`、`xxd`），自动适配架构。

---

## 🚀 快速开始（一键安装）

在你的 Alpine VPS 终端中直接运行以下命令：

```bash
wget https://raw.githubusercontent.com/kkkbox/64m/main/sb_install.sh -O sb_install.sh && sh sb_install.sh

```

---

## 🛠️ 常用管理命令

安装完成后，可以通过标准的 OpenRC 命令来管理后台服务：

* **查看运行状态**：
```bash
service sing-box status

```


* **启动服务**：
```bash
service sing-box start

```


* **停止服务**：
```bash
service sing-box stop

```


* **重启服务**：
```bash
service sing-box restart

```


* **查看客户端分享链接**：
```bash
cat /root/singbox/share-link.txt

```



---

## 🗑️ 彻底卸载与清理

如果你需要完全移除 `sing-box` 及其所有残留文件：

```bash
service sing-box stop
rc-update del sing-box default
rm -rf /etc/init.d/sing-box /root/singbox

```

 

*(注：如果之前创建了 `/swapfile` 虚拟内存且不需要了，可以运行 `swapoff /swapfile` 后再执行上面的一键删除命令)*
