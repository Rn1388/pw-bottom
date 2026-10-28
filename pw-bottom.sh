#!/bin/sh
# pw-bottom.sh —— 给「官方版」PassWall 加上 kiddin9 版的底栏（国旗 / 出口 IP / 运营商 / 四站连通性）
#
# 适用：iStoreOS / OpenWrt 24.10（opkg）和 25.12（apk），x86_64 / aarch64 都行
#       PassWall 用 .run 或 apk/opkg 正常装好之后再跑
#
# 用法：sh pw-bottom.sh            安装底栏（可重复执行，PassWall 升级后再跑一次即可）
#       sh pw-bottom.sh offline    不联网，直接用 /root/pw-bottom 里的缓存素材
#       sh pw-bottom.sh remove     去掉底栏，恢复官方原样
#
# 原理：从 kiddin9 的 luci-app-passwall 包里只取底栏需要的东西——
#       status_bottom.htm、8 个站点图标、237 面国旗、控制器里的 4 个函数（check_site /
#       get_ip_geo_info / get_country_name / check_ip）——补进官方版；
#       另外只改两处：控制器加 1 行路由，global.lua 加 1 行模板引用。其他文件一律不碰。

R=${PWB_ROOT:-}                                  # 测试用的根目录前缀，正常使用留空
D=$R/root/pw-bottom                              # 素材缓存
L=$R/usr/lib/lua/luci
CTL=$L/controller/passwall.lua
GL=$L/model/cbi/passwall/client/global.lua
VIEW=$L/view/passwall/global
WWW=$R/www/luci-static/passwall
TMP=$R/tmp/pw-bottom.$$

ROUTE='entry({"admin", "services", appname, "ip"}, call("check_ip")).leaf = true'
TPL='m:appendTemplate("/global/status_bottom")'

say() { echo "[pw-bottom] $*"; }
die() { echo "[pw-bottom] 错误：$*" >&2; rm -rf "$TMP"; exit 1; }
refresh() {
	[ -n "$R" ] && return
	rm -rf /tmp/luci-*
	/etc/init.d/rpcd restart >/dev/null 2>&1
}

# 去掉本脚本打过的补丁（也兼容早先手工 apply.sh 打的、没有标记的版本）
unpatch() {
	sed -i '/^-- >>> pw-bottom$/,/^-- <<< pw-bottom$/d' "$CTL"
	sed -i '/call("check_ip")).leaf = true/d' "$CTL"
	if ! grep -q "call('check_ip')" "$CTL" && grep -q '^function check_site(' "$CTL"; then
		sed -i '/^function check_site(/,$d' "$CTL"      # 旧版 apply.sh 追加在文件末尾
	fi
	sed -i '/m:appendTemplate("\/global\/status_bottom")/d' "$GL"
}

[ -f "$CTL" ] && [ -f "$GL" ] || die "没找到 PassWall（$CTL），请先装好 luci-app-passwall"
command -v lua >/dev/null 2>&1 || die "缺少 lua"

# kiddin9 原版自带底栏，不需要补
if grep -q "call('check_ip')" "$CTL"; then
	say "这台的 PassWall 本身就是 kiddin9 版，自带底栏，不用补。"
	exit 0
fi

if [ "$1" = remove ]; then
	unpatch
	rm -f "$VIEW/status_bottom.htm"
	rm -rf "$WWW/img" "$WWW/flags"
	refresh
	say "已去掉底栏，PassWall 恢复官方原样。"
	exit 0
fi

mkdir -p "$TMP" "$D" || die "无法创建目录"

# ---------- 1. 取素材：联网下载 kiddin9 包，失败则用缓存 ----------
F=
if [ "$1" != offline ]; then
	command -v curl >/dev/null 2>&1 || die "缺少 curl（或用 offline 模式）"
	for U in \
		https://dl.openwrt.ai/packages-25.12/aarch64_generic/kiddin9/ \
		https://dl.openwrt.ai/packages-25.12/x86_64/kiddin9/ \
		https://dl.openwrt.ai/releases/24.10/packages/x86_64/kiddin9/ \
		https://dl.openwrt.ai/releases/24.10/packages/aarch64_generic/kiddin9/
	do
		F=$(curl -fsSL -m 20 "$U" 2>/dev/null | grep -oE 'luci-app-passwall_[^"<>]+_all\.ipk' | head -1)
		[ -n "$F" ] && curl -fsSL -m 120 -o "$TMP/pw.ipk" "$U$F" && break
		F=
	done

	if [ -n "$F" ]; then
		say "已下载 kiddin9 包：$F"
		X=$TMP/root
		mkdir -p "$TMP/ipk" "$X"
		tar -xzf "$TMP/pw.ipk" -C "$TMP/ipk" && tar -xzf "$TMP/ipk/data.tar.gz" -C "$X" \
			|| die "解包失败"
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
	else
		say "下载 kiddin9 包失败，改用本地缓存 $D"
	fi
fi

[ -f "$D/status_bottom.htm" ] && [ -f "$D/check_ip.lua" ] && [ -d "$D/flags" ] && [ -d "$D/img" ] \
	|| die "没有可用素材：下载失败，$D 里也没有缓存"
[ -f "$D/source.txt" ] && say "素材来源：$(cat "$D/source.txt")"

# ---------- 2. 打补丁 ----------
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
rm -rf "$TMP"
say "完成。浏览器强制刷新 PassWall 页面即可看到底栏。PassWall 升级后再跑一次本脚本。"
