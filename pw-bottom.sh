#!/bin/sh
# pw-bottom.sh —— iStoreOS 上一条命令装好 PassWall，并加上 kiddin9 版的底栏
#                 （国旗 / 出口 IP / 运营商 / 百度淘宝谷歌 YouTube 连通性）
#
# 适用：iStoreOS 24.10（opkg）和 25.12（apk），x86_64 / aarch64_generic / a53 / a72
#
# 用法：curl -fsSL https://raw.githubusercontent.com/Rn1388/pw-bottom/main/pw-bottom.sh | sh
#
#   没装 PassWall：修软件源 → 从 bcseputetto/Are-u-ok 下载对应版本的 .run → 安装 → 加底栏
#   已装 PassWall：只加底栏（不会动已装的 PassWall）
#
#   带参数时用 | sh -s 参数，例如 | sh -s upgrade
#     upgrade   强制从 Are-u-ok 下载最新 .run 重装/升级 PassWall，再加底栏
#     bar       只加底栏（联网取素材）
#     offline   只加底栏，不联网，用 /root/pw-bottom 里的缓存
#     remove    去掉底栏，恢复官方原样
#
#   装好后本机留有 /root/pw-bottom/apply.sh，以后直接运行它，参数同上。
#
#   环境变量：
#     GH_PROXY=https://某个GitHub加速/   路由器直连 GitHub 太慢时，给 GitHub 下载地址加前缀
#     RUN=/tmp/xxx.run                   已经手动传了 .run 到路由器时，直接用它，不再下载
#     例：curl -fsSL ... | GH_PROXY=https://xxx/ sh
#
# 底栏原理：从 kiddin9 的 luci-app-passwall 包里只取底栏需要的东西——status_bottom.htm、
#   8 个站点图标、237 面国旗、控制器里的 4 个函数——补进官方版；只改两处：控制器加 1 行路由，
#   global.lua 加 1 行模板引用。改完用 lua 做语法检查，不通过自动回滚。

R=${PWB_ROOT:-}                                  # 测试用的根目录前缀，正常使用留空
D=$R/root/pw-bottom                              # 素材缓存 / 本机脚本
L=$R/usr/lib/lua/luci
CTL=$L/controller/passwall.lua
GL=$L/model/cbi/passwall/client/global.lua
VIEW=$L/view/passwall/global
WWW=$R/www/luci-static/passwall
REL=$R/etc/openwrt_release
APKD=$R/etc/apk/repositories.d
OPKD=$R/etc/opkg
TMP=$R/tmp/pw-bottom.$$

PWREPO=bcseputetto/Are-u-ok
SELF_URLS="https://raw.githubusercontent.com/Rn1388/pw-bottom/main/pw-bottom.sh https://cdn.jsdelivr.net/gh/Rn1388/pw-bottom@main/pw-bottom.sh"
OFFICIAL=https://downloads.openwrt.org/releases

ROUTE='entry({"admin", "services", appname, "ip"}, call("check_ip")).leaf = true'
TPL='m:appendTemplate("/global/status_bottom")'

MODE=${1:-auto}

say() { echo "[pw-bottom] $*"; }
die() { echo "[pw-bottom] 错误：$*" >&2; rm -rf "$TMP"; exit 1; }
refresh() {
	[ -n "$R" ] && return
	rm -rf /tmp/luci-*
	/etc/init.d/rpcd restart >/dev/null 2>&1
}

case "$MODE" in
	auto|upgrade|bar|offline|remove) ;;
	*) die "不认识的参数：$MODE（可用：upgrade / bar / offline / remove）" ;;
esac

mkdir -p "$TMP" "$D" || die "无法创建目录"

# ======================================================================
# 一、系统信息
# ======================================================================
[ -f "$REL" ] && . "$REL"
case "$DISTRIB_RELEASE" in
	24.10*) SDK=24.10 ;;
	25.12*) SDK=25.12 ;;
	*)      SDK= ;;
esac
case "$DISTRIB_ARCH" in
	x86_64)              PWARCH=x86_64 ;;
	aarch64_cortex-a53)  PWARCH=aarch64_a53 ;;
	aarch64_cortex-a72)  PWARCH=aarch64_a72 ;;
	aarch64_*)           PWARCH=aarch64_generic ;;
	*)                   PWARCH= ;;
esac
if command -v apk >/dev/null 2>&1 && [ -d "$APKD" ]; then PM=apk; else PM=opkg; fi

pw_installed() {
	if [ "$PM" = apk ]; then apk info -e luci-app-passwall >/dev/null 2>&1
	else opkg list-installed luci-app-passwall 2>/dev/null | grep -q luci-app-passwall; fi
}

# ======================================================================
# 二、修软件源：让 apk/opkg update 一个错都没有（.run 里的安装脚本要求这一点）
# ======================================================================
# apk：输出 "WARNING: updating and opening <url>: <原因>" 的就是失败的源
apk_bad() {
	apk update 2>&1 | sed -n 's|^WARNING: updating and opening \(https*://[^ ]*\): .*|\1|p'
}
# opkg：输出 "*** Failed to download the package list from <url>/Packages.gz"
opkg_bad() {
	opkg update 2>&1 | sed -n 's|^\*\*\* Failed to download the package list from \(https*://[^ ]*\)/Packages\.gz.*|\1|p'
}
fix_sources() {
	say "检查软件源（$PM）..."
	if [ "$PM" = apk ]; then
		BAD=$(apk_bad)
		[ -z "$BAD" ] && { say "软件源正常"; return 0; }
		if echo "$BAD" | grep -q '/openwrt/releases/'; then
			say "OpenWrt 官方源的镜像不可用，改成 downloads.openwrt.org"
			sed -i -E "s|https?://[^/]+/openwrt/releases|$OFFICIAL|" "$APKD/distfeeds.list"
		fi
		BAD=$(apk_bad)
		for u in $BAD; do
			for f in "$APKD"/*.list; do
				[ "$(basename "$f")" = distfeeds.list ] && continue   # 官方源不注释
				grep -q "^$u\$" "$f" || continue
				sed -i "s|^$u\$|# &|" "$f"
				say "已注释失效或未签名的源：$u（在 $(basename "$f")）"
			done
		done
		BAD=$(apk_bad)
	else
		BAD=$(opkg_bad)
		[ -z "$BAD" ] && { say "软件源正常"; return 0; }
		if echo "$BAD" | grep -q '/openwrt/releases/'; then
			say "OpenWrt 官方源的镜像不可用，改成 downloads.openwrt.org"
			sed -i -E "s|https?://[^/]+/openwrt/releases|$OFFICIAL|" "$OPKD/distfeeds.conf"
		fi
		BAD=$(opkg_bad)
		for u in $BAD; do
			for f in "$OPKD"/*.conf; do
				[ "$(basename "$f")" = distfeeds.conf ] && continue   # 官方源不注释
				grep -q "^src/gz [^ ]* $u\$" "$f" || continue
				sed -i "s|^src/gz [^ ]* $u\$|# &|" "$f"
				say "已注释失效的源：$u（在 $(basename "$f")）"
			done
		done
		BAD=$(opkg_bad)
	fi
	[ -z "$BAD" ] && { say "软件源已修好"; return 0; }
	echo "$BAD" | sed 's/^/    仍然失败：/'
	die "软件源还有错误，PassWall 的安装脚本会因此中止。请检查路由器能否上网后重试"
}

# ======================================================================
# 三、从 Are-u-ok 下载并安装 PassWall
# ======================================================================
install_passwall() {
	[ -n "$R" ] && die "测试模式下不执行安装"
	grep -qi kwrt "$REL" 2>/dev/null && \
		die "这是 Kwrt 固件，请直接 opkg install luci-app-passwall（kiddin9 源的版本自带底栏）"
	[ -n "$SDK" ] || die "只支持 iStoreOS 24.10 / 25.12，这台是 ${DISTRIB_RELEASE:-未知版本}"
	[ -n "$PWARCH" ] || die "不支持的架构：${DISTRIB_ARCH:-未知}"
	command -v curl >/dev/null 2>&1 || die "缺少 curl"

	fix_sources

	if [ -n "$RUN" ]; then
		[ -f "$RUN" ] || die "RUN 指定的文件不存在：$RUN"
		say "使用本地安装包：$RUN"
		PKG=$RUN
	else
		TAG=iStoreOS_$SDK
		PAT="PassWall_[0-9][^\"/<> ]*_${PWARCH}_all_sdk_${SDK}\.run"
		say "查找 $PWREPO 里 $TAG / $PWARCH 的 PassWall 安装包..."
		N=$(curl -fsSL -m 30 "https://api.github.com/repos/$PWREPO/releases/tags/$TAG" 2>/dev/null \
			| grep -oE "$PAT" | sort -u | tail -1)
		[ -n "$N" ] || N=$(curl -fsSL -m 30 "${GH_PROXY}https://github.com/$PWREPO/releases/expanded_assets/$TAG" 2>/dev/null \
			| grep -oE "$PAT" | sort -u | tail -1)
		[ -n "$N" ] || die "没找到对应的安装包。网络问题的话可以试试：| GH_PROXY=https://某个加速/ sh"

		FREE=$(df -k /tmp 2>/dev/null | awk 'NR==2 {print $4}')
		[ -n "$FREE" ] && [ "$FREE" -lt 250000 ] && die "/tmp 剩余空间不足 250MB（剩 ${FREE}KB）"

		PKG=$TMP/$N
		say "下载 $N（约 80MB，慢的话请耐心等）..."
		curl -fL --retry 3 -m 900 -o "$PKG" \
			"${GH_PROXY}https://github.com/$PWREPO/releases/download/$TAG/$N" \
			|| die "下载失败。可以设置 GH_PROXY 加速，或在电脑上下载后传到路由器，用 RUN=/路径 指定"
	fi

	say "开始安装 PassWall..."
	sh "$PKG" || say "安装脚本返回了错误，下面检查是否装上"
	pw_installed || die "PassWall 没有装上，请看上面的输出"
	[ -z "$RUN" ] && rm -f "$PKG"
	say "PassWall 安装完成"
}

# ======================================================================
# 四、底栏
# ======================================================================
unpatch() {
	sed -i '/^-- >>> pw-bottom$/,/^-- <<< pw-bottom$/d' "$CTL"
	sed -i '/call("check_ip")).leaf = true/d' "$CTL"
	if ! grep -q "call('check_ip')" "$CTL" && grep -q '^function check_site(' "$CTL"; then
		sed -i '/^function check_site(/,$d' "$CTL"      # 早先手工 apply.sh 追加在文件末尾、无标记的版本
	fi
	sed -i '/m:appendTemplate("\/global\/status_bottom")/d' "$GL"
}

fetch_bar_assets() {
	F=
	command -v curl >/dev/null 2>&1 || { say "缺少 curl，改用本地缓存"; return; }
	for U in \
		https://dl.openwrt.ai/packages-25.12/aarch64_generic/kiddin9/ \
		https://dl.openwrt.ai/packages-25.12/x86_64/kiddin9/ \
		https://dl.openwrt.ai/releases/24.10/packages/x86_64/kiddin9/ \
		https://dl.openwrt.ai/releases/24.10/packages/aarch64_generic/kiddin9/
	do
		F=$(curl -fsSL -m 20 "$U" 2>/dev/null | grep -oE 'luci-app-passwall_[^"<>]+_all\.ipk' | head -1)
		[ -n "$F" ] && curl -fsSL -m 120 -o "$TMP/pw.ipk" "$U$F" 2>/dev/null && break
		F=
	done
	[ -n "$F" ] || { say "下载 kiddin9 包失败，改用本地缓存 $D"; return; }

	say "已下载 kiddin9 包：$F"
	X=$TMP/root
	mkdir -p "$TMP/ipk" "$X"
	tar -xzf "$TMP/pw.ipk" -C "$TMP/ipk" && tar -xzf "$TMP/ipk/data.tar.gz" -C "$X" || die "解包失败"
	KL=$X/usr/lib/lua/luci
	KC=$KL/controller/passwall.lua
	[ -f "$KL/view/passwall/global/status_bottom.htm" ] \
		|| die "这一版 kiddin9 包里已经没有底栏模板了，脚本需要更新"

	: > "$TMP/check_ip.lua"
	for fn in check_site get_ip_geo_info get_country_name check_ip; do
		awk -v f="$fn" '$0 ~ "^function " f "\\(" {p=1} p {print} p && /^end/ {exit}' "$KC" > "$TMP/fn"
		[ -s "$TMP/fn" ] || die "kiddin9 包里找不到函数 $fn，脚本需要更新"
		cat "$TMP/fn" >> "$TMP/check_ip.lua"
	done
	# 加固：ip-api.com 查不到时返回空值而不是让接口报错
	sed -i \
		-e 's|local info = json.parse(result)$|local info = json.parse(result or "") or {}|' \
		-e 's|string.lower(info.countryCode)|string.lower(info.countryCode or "un")|' \
		"$TMP/check_ip.lua"

	rm -rf "$D/img" "$D/flags"
	cp "$KL/view/passwall/global/status_bottom.htm" "$D/" &&
	cp -r "$X/www/luci-static/passwall/img" "$X/www/luci-static/passwall/flags" "$D/" &&
	cp "$TMP/check_ip.lua" "$D/check_ip.lua" &&
	echo "$F" > "$D/source.txt" || die "写入缓存失败"
}

apply_bar() {
	[ -f "$D/status_bottom.htm" ] && [ -f "$D/check_ip.lua" ] && [ -d "$D/flags" ] && [ -d "$D/img" ] \
		|| die "没有可用的底栏素材：下载失败，$D 里也没有缓存"
	[ -f "$D/source.txt" ] && say "底栏素材来源：$(cat "$D/source.txt")"

	cp "$CTL" "$TMP/ctl.bak" && cp "$GL" "$TMP/gl.bak" || die "备份失败"
	rollback() { cp "$TMP/ctl.bak" "$CTL"; cp "$TMP/gl.bak" "$GL"; }

	unpatch
	grep -q 'appname, "hide"}, call("hide_menu")' "$CTL" \
		|| { rollback; die "官方控制器结构变了，找不到插入路由的位置（hide_menu），没有改动"; }
	grep -q 'm:appendTemplate("/global/footer")' "$GL" \
		|| { rollback; die "官方 global.lua 结构变了，找不到 footer 模板行，没有改动"; }

	sed -i "/appname, \"hide\"}, call(\"hide_menu\")/a $ROUTE" "$CTL"
	{ echo "-- >>> pw-bottom"; cat "$D/check_ip.lua"; echo "-- <<< pw-bottom"; } >> "$CTL"
	sed -i "/m:appendTemplate(\"\/global\/footer\")/a $TPL" "$GL"

	lua -e "assert(loadfile('$CTL')); assert(loadfile('$GL'))" 2>"$TMP/lua.err" \
		|| { rollback; cat "$TMP/lua.err" >&2; die "语法检查没通过，已回滚，PassWall 不受影响"; }

	mkdir -p "$VIEW" "$WWW"
	cp "$D/status_bottom.htm" "$VIEW/"
	rm -rf "$WWW/img" "$WWW/flags"
	cp -r "$D/img" "$D/flags" "$WWW/"
	refresh
	say "底栏已加上"
}

# 在本机留一份脚本和 apply.sh
install_local() {
	if [ -f "$0" ] && grep -q 'pw-bottom' "$0" 2>/dev/null; then
		cp "$0" "$D/pw-bottom.sh.new"
	else
		for u in $SELF_URLS; do
			curl -fsSL -m 20 -o "$D/pw-bottom.sh.new" "$u" 2>/dev/null && break
		done
	fi
	if [ -s "$D/pw-bottom.sh.new" ] && grep -q 'pw-bottom' "$D/pw-bottom.sh.new"; then
		mv "$D/pw-bottom.sh.new" "$D/pw-bottom.sh"
	else
		rm -f "$D/pw-bottom.sh.new"
	fi
	[ -f "$D/pw-bottom.sh" ] || { say "提示：没能在本机保存脚本，以后请继续用 curl 命令运行"; return; }
	cat > "$D/apply.sh" << EOF
#!/bin/sh
# PassWall 升级后运行本文件，重新加上底栏。
# 参数：（无）/ upgrade / bar / offline / remove，含义见 $D/pw-bottom.sh 开头
D=$D
if [ "\$1" != offline ]; then
	for u in $SELF_URLS; do
		curl -fsSL -m 20 -o "\$D/pw-bottom.sh.new" "\$u" 2>/dev/null && grep -q pw-bottom "\$D/pw-bottom.sh.new" \\
			&& mv "\$D/pw-bottom.sh.new" "\$D/pw-bottom.sh" && break
	done
	rm -f "\$D/pw-bottom.sh.new"
fi
exec sh "\$D/pw-bottom.sh" "\$@"
EOF
	chmod +x "$D/apply.sh"
}

# ======================================================================
# 主流程
# ======================================================================
say "系统：${DISTRIB_DESCRIPTION:-未知}，架构 ${DISTRIB_ARCH:-未知}，包管理 $PM"

if [ "$MODE" = upgrade ]; then
	install_passwall
elif [ "$MODE" = auto ] && ! pw_installed && [ ! -f "$CTL" ]; then
	say "没检测到 PassWall，先安装"
	install_passwall
fi

[ -f "$CTL" ] && [ -f "$GL" ] || die "没找到 PassWall（$CTL）"
command -v lua >/dev/null 2>&1 || die "缺少 lua"

if grep -q "call('check_ip')" "$CTL"; then
	say "这台的 PassWall 是 kiddin9 版，本身自带底栏，不用补。"
	rm -rf "$TMP"; exit 0
fi

if [ "$MODE" = remove ]; then
	unpatch
	rm -f "$VIEW/status_bottom.htm"
	rm -rf "$WWW/img" "$WWW/flags"
	refresh
	rm -rf "$TMP"
	say "已去掉底栏，PassWall 恢复官方原样。"
	exit 0
fi

[ "$MODE" = offline ] || fetch_bar_assets
apply_bar
rm -rf "$TMP"
install_local
say "完成。浏览器强制刷新 PassWall 页面即可。"
say "以后 PassWall 升级后底栏会消失，运行：/root/pw-bottom/apply.sh"
