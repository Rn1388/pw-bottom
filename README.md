# pw-bottom

在 iStoreOS 上**一条命令装好 PassWall**，并加上 kiddin9（Kwrt）版才有的那条底栏：**国旗 + 出口 IP + 运营商 + 百度 / 淘宝 / 谷歌 / YouTube 连通性图标**。

- PassWall 用 [bcseputetto/Are-u-ok](https://github.com/bcseputetto/Are-u-ok) 发布的官方 `.run` 安装包，按系统版本和架构自动选择
- 底栏从 kiddin9 的 `luci-app-passwall` 包里单独移植，其他功能保持官方原样

## 适用

| 项 | 支持 |
| --- | --- |
| 系统 | iStoreOS **24.10（opkg）**、**25.12（apk）** |
| 架构 | x86_64、aarch64_generic、aarch64_cortex-a53、aarch64_cortex-a72 |
| PassWall | 官方版 luci-app-passwall（在 26.10.22 上测试） |

Kwrt 固件不需要这个脚本，直接 `opkg install luci-app-passwall`，kiddin9 源里的版本自带底栏。

## 一条命令

```sh
curl -fsSL https://raw.githubusercontent.com/Rn1388/pw-bottom/main/pw-bottom.sh | sh
```

GitHub raw 连不上时用 jsDelivr：

```sh
curl -fsSL https://cdn.jsdelivr.net/gh/Rn1388/pw-bottom@main/pw-bottom.sh | sh
```

脚本会自己判断该做什么：

| 这台机器的情况 | 脚本做的事 |
| --- | --- |
| 还没装 PassWall | 修软件源 → 下载对应版本的 `.run` → 安装 → 加底栏 |
| 已装官方版 PassWall | 只加底栏，不动已装的 PassWall |
| 已装 kiddin9 版 PassWall | 本身就有底栏，提示后退出 |

装完浏览器**强制刷新**（Mac：`Cmd+Shift+R`）PassWall 页面。

## 以后

第一次运行后，本机会留下 `/root/pw-bottom/apply.sh`。

| 命令 | 作用 |
| --- | --- |
| `/root/pw-bottom/apply.sh` | PassWall 升级后底栏消失了，跑这个加回来 |
| `/root/pw-bottom/apply.sh upgrade` | 从 Are-u-ok 下载最新 `.run`，升级 PassWall，再加底栏 |
| `/root/pw-bottom/apply.sh offline` | 不联网，用本机缓存的素材加底栏 |
| `/root/pw-bottom/apply.sh remove` | 去掉底栏，恢复官方原样 |

`apply.sh` 每次会先从本仓库拉取最新的脚本，拉不到就用本机副本。可以重复执行。

还没有 `apply.sh` 的机器，用 curl 也能带参数，注意写法是 `sh -s 参数`：

```sh
curl -fsSL https://raw.githubusercontent.com/Rn1388/pw-bottom/main/pw-bottom.sh | sh -s upgrade
```

## 网络不好时

路由器下载 GitHub 上约 80MB 的安装包可能很慢，有两个办法：

**用 GitHub 加速前缀**，脚本会把它加在 GitHub 下载地址前面：

```sh
curl -fsSL https://raw.githubusercontent.com/Rn1388/pw-bottom/main/pw-bottom.sh | GH_PROXY=https://你的加速地址/ sh
```

**在电脑上下载好 `.run`，传到路由器，用 `RUN` 指定**：

```sh
scp PassWall_26.10.22_aarch64_generic_all_sdk_25.12.run root@路由器IP:/tmp/
curl -fsSL https://raw.githubusercontent.com/Rn1388/pw-bottom/main/pw-bottom.sh | RUN=/tmp/PassWall_26.10.22_aarch64_generic_all_sdk_25.12.run sh
```

## 它做了什么

### 1. 修软件源

`.run` 里的安装脚本会先跑 `apk update` / `opkg update`，**只要有一个源报错就会中止**。所以脚本先把源修到一个错都没有：

- OpenWrt 官方源的镜像（比如 cernet、清华）不可用时，改成 `downloads.openwrt.org`。iStoreOS 25.12.5 新装后默认的镜像就经常没同步
- 其他失效或未签名的第三方源（比如 PassWall 的 SourceForge 源，会报 `UNTRUSTED signature`）注释掉，并打印出是哪一行
- 官方源本身的行不会被注释。修完还有错误就停下，不往下装

### 2. 安装 PassWall

从 `bcseputetto/Are-u-ok` 的 `iStoreOS_24.10` / `iStoreOS_25.12` 发布页，按架构找到 `PassWall_版本_架构_all_sdk_版本.run`，下载后执行。安装包自带 xray、sing-box、hysteria 等核心，版本和 PassWall 匹配。

### 3. 加底栏

- 从 kiddin9 的源（`dl.openwrt.ai`）下载最新的 `luci-app-passwall` 包，只取底栏用到的东西：`status_bottom.htm`、8 个站点图标、237 面国旗、控制器里的 4 个函数（`check_site`、`get_ip_geo_info`、`get_country_name`、`check_ip`）
- 只改官方的两个文件，各加一行：控制器加路由 `admin/services/passwall/ip`，并在末尾追加那 4 个函数（用 `-- >>> pw-bottom` / `-- <<< pw-bottom` 标记）；`global.lua` 在 footer 后加一行模板引用
- 用 `lua` 检查语法，**不通过就自动回滚**；官方文件结构变了、找不到插入位置时，**直接停止，不做改动**
- 加固了一处：`ip-api.com` 查不到结果时返回空值，不让接口报错

## 文件位置

```
/root/pw-bottom/
├── apply.sh            以后运行这个
├── pw-bottom.sh        脚本本机副本
├── status_bottom.htm   ┐
├── img/                │ 底栏素材缓存
├── flags/              │
├── check_ip.lua        ┘
└── source.txt          素材来自哪个 kiddin9 包
```

## 注意事项

- **底栏显示的是路由器本机的出口 IP**，由路由器访问 `http://ip-api.com/json/` 查得。路由器自身流量走代理时显示节点 IP，不走代理时显示宽带 IP
- 脚本依赖两个外部来源的文件命名和代码结构：Are-u-ok 的 `.run` 文件名、kiddin9 包里的底栏函数。对方改了的话，脚本会报错停下，不改动系统，这时需要更新脚本
- jsDelivr 有缓存，仓库更新后可能要过一段时间才同步，想立刻拿到新版就用 raw 地址
- 修软件源时被注释掉的第三方源，以后要用的话自己去 `/etc/apk/repositories.d/` 或 `/etc/opkg/` 里删掉行首的 `#`

## 卸载

```sh
/root/pw-bottom/apply.sh remove
rm -rf /root/pw-bottom
```

只去掉底栏和脚本，不卸载 PassWall。
