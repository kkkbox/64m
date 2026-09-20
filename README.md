# 64m

以下是为您整理的针对该脚本的**常用快捷命令**（适用于安装了该脚本的 Alpine 系统）：

### 1. 一键安装命令

直接在终端复制并运行以下命令即可全新安装：

```bash
wget https://raw.githubusercontent.com/kkkbox/64m/main/sb_install.sh -O sb_install.sh && sh sb_install.sh

```

---

### 2. 服务管理命令

你可以直接使用 OpenRC 的 `service` 命令来管理 sing-box 后台服务：

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



---

### 3. 查看分享链接

如果安装后忘记了链接，随时可以通过以下命令再次查看：

```bash
cat /root/singbox/share-link.txt

```

---

### 4. 彻底删除 / 卸载命令

如果你想完全清理掉 sing-box 及其所有配置文件和开机启动项，可以运行以下命令：

```bash
service sing-box stop
rc-update del sing-box default
rm -rf /etc/init.d/sing-box /root/singbox /swapfile

```

*(注：如果之前创建了 `/swapfile` 虚拟内存且不需要了，可以运行 `swapoff /swapfile` 后再执行上面的一键删除命令)*
