#!/bin/zsh
#
# 重启到 Windows：只把“下一次启动”设为 Windows，然后正常重启。
# 从 Windows 再次重启后，会自动回到默认的 macOS。
#
# 用法：
#   重启到 Windows.command            设置一次性启动 Windows 并重启
#   重启到 Windows.command --check    只做检查，不改启动项、不重启
#   重启到 Windows.command --cancel   撤销还没生效的一次性启动设置
#   重启到 Windows.command --prepare  只设置一次性启动，不询问、不重启（供 App 调用）
#
# 日志：~/Library/Logs/reboot-to-windows.log

setopt no_unset pipe_fail

MODE="${1:-}"
LOG_FILE="$HOME/Library/Logs/reboot-to-windows.log"
LOADER_SUBPATH="EFI/Microsoft/Boot/bootmgfw.efi"
# 除 Apple 的 efi-boot-next 外，bless 和 OpenCore 也可能使用这两处的 BootNext
BOOT_NEXT_VARS=(
	efi-boot-next
	efi-boot-next-data
	8BE4DF61-93CA-11D2-AA0D-00E098032B8C:BootNext
	4D1FDA02-38C7-4A6A-9CC6-4BCCA8B30102:BootNext
)

# 从“重启到 Windows.app”启动时已经是 root，不需要再 sudo
if (( EUID == 0 )); then
	SUDO=()
	SUDO_N=()
else
	SUDO=(/usr/bin/sudo)
	SUDO_N=(/usr/bin/sudo -n)
fi

ESP_DEVICE=""
ESP_UUID=""
ESP_MOUNT_POINT=""
ESP_MOUNTED_BY=""   # 空 = 不是本脚本挂载的；diskutil / msdos = 退出时需要卸载

log() {
	print -r -- "$(/bin/date '+%F %T') [${MODE:-run}] $*" >> "$LOG_FILE" 2>/dev/null
}

say() {
	print -r -- "$*"
	log "$*"
}

fail() {
	print -ru2 -- "错误：$1"
	log "错误：$1"
	if [[ -t 0 ]]; then
		print -n "按回车键退出。"
		read -r
	fi
	exit 1
}

# pl <plist 文本> <键路径>：读取一个字符串值，不存在时返回非 0
pl() {
	/usr/bin/plutil -extract "$2" raw -o - - <<< "$1" 2>/dev/null
}

need_admin() {
	(( EUID == 0 )) && return
	print "需要管理员密码来挂载 Windows 的 EFI 分区并修改启动项。"
	/usr/bin/sudo -v || fail "没有取得管理员权限。"
}

unmount_esp() {
	case $ESP_MOUNTED_BY in
		(diskutil)
			$SUDO_N /usr/sbin/diskutil unmount "$ESP_DEVICE" >/dev/null 2>&1 || return 1
			;;
		(msdos)
			$SUDO_N /sbin/umount "$ESP_MOUNT_POINT" >/dev/null 2>&1 || return 1
			/bin/rmdir "$ESP_MOUNT_POINT" 2>/dev/null
			;;
	esac
	ESP_MOUNTED_BY=""
}

cleanup() {
	unmount_esp || log "警告：退出时无法卸载 $ESP_DEVICE"
}

trap cleanup EXIT
trap 'print; exit 130' INT TERM HUP

# 只读挂载 $ESP_DEVICE，结果写入 ESP_MOUNT_POINT / ESP_MOUNTED_BY
mount_esp() {
	local info mount_point
	info=$(/usr/sbin/diskutil info -plist "$ESP_DEVICE") || return 1
	mount_point=$(pl "$info" MountPoint)
	if [[ -n $mount_point ]]; then
		ESP_MOUNT_POINT=$mount_point
		return 0
	fi

	if $SUDO /usr/sbin/diskutil mount readOnly nobrowse "$ESP_DEVICE" >/dev/null 2>&1; then
		ESP_MOUNTED_BY=diskutil
		ESP_MOUNT_POINT=$(pl "$(/usr/sbin/diskutil info -plist "$ESP_DEVICE")" MountPoint)
		[[ -n $ESP_MOUNT_POINT ]] && return 0
		return 1
	fi

	# diskutil 挂不上时（例如 FAT 卷被标记为“脏”），直接用 mount_msdos 只读挂载
	mount_point=$(/usr/bin/mktemp -d /private/tmp/reboot-to-windows.XXXXXX) || return 1
	if $SUDO /sbin/mount_msdos -o rdonly,nobrowse "/dev/$ESP_DEVICE" "$mount_point" >/dev/null 2>&1; then
		ESP_MOUNTED_BY=msdos
		ESP_MOUNT_POINT=$mount_point
		return 0
	fi
	/bin/rmdir "$mount_point" 2>/dev/null
	return 1
}

# 找出所有“同时有 EFI 分区和 Microsoft 数据分区”的物理硬盘，
# 不依赖 Windows 分区是否已挂载、卷名叫什么、硬盘编号是多少。
find_candidates() {
	local list disk content prefix esp esp_uuid has_windows i j
	CANDIDATES=()
	list=$(/usr/sbin/diskutil list -plist physical) || return 1
	for (( i = 0; ; i++ )); do
		disk=$(pl "$list" "AllDisksAndPartitions.$i.DeviceIdentifier") || break
		esp="" esp_uuid="" has_windows=0
		for (( j = 0; ; j++ )); do
			prefix="AllDisksAndPartitions.$i.Partitions.$j"
			content=$(pl "$list" "$prefix.Content") || break
			case $content in
				(EFI)
					if [[ -z $esp ]]; then
						esp=$(pl "$list" "$prefix.DeviceIdentifier")
						esp_uuid=$(pl "$list" "$prefix.DiskUUID")
					fi
					;;
				("Microsoft Basic Data")
					has_windows=1
					;;
			esac
		done
		if (( has_windows )) && [[ -n $esp && -n $esp_uuid ]]; then
			CANDIDATES+=("$esp $esp_uuid")
		fi
	done
}

pending_next_boot() {
	local var
	for var in $BOOT_NEXT_VARS; do
		/usr/sbin/nvram "$var" >/dev/null 2>&1 && return 0
	done
	return 1
}

cancel_next_boot() {
	local var found=()
	for var in $BOOT_NEXT_VARS; do
		/usr/sbin/nvram "$var" >/dev/null 2>&1 && found+=("$var")
	done
	if (( ! $#found )); then
		say "当前没有待生效的一次性启动设置，无需撤销。"
		exit 0
	fi
	need_admin
	for var in $found; do
		$SUDO /usr/sbin/nvram -d "$var" || fail "无法删除启动变量 $var。"
	done
	say "已撤销一次性启动设置，下次启动将进入默认系统。"
	exit 0
}

# 像苹果菜单里的“重新启动…”一样正常重启：各应用有机会提示保存文档
request_restart() {
	local script='tell application "loginwindow" to «event aevtrest»'
	local user uid
	if (( EUID == 0 )); then
		user=$(/usr/bin/stat -f %Su /dev/console)
		uid=$(/usr/bin/stat -f %u /dev/console)
		[[ -n $user && $user != root ]] || return 1
		/bin/launchctl asuser "$uid" /usr/bin/sudo -u "$user" /usr/bin/osascript -e "$script" >/dev/null 2>&1
	else
		/usr/bin/osascript -e "$script" >/dev/null 2>&1
	fi
}

# 以 root 身份（从 .app）运行时，别让日志文件变成 root 所有
if (( EUID == 0 )) && : >> "$LOG_FILE" 2>/dev/null; then
	/usr/sbin/chown "$(/usr/bin/stat -f %u:%g "$HOME")" "$LOG_FILE" 2>/dev/null
fi

case $MODE in
	("" | --check | --prepare) ;;
	(--cancel) cancel_next_boot ;;
	(*)
		print -u2 "用法：${0:t} [--check | --cancel | --prepare]"
		exit 2
		;;
esac

log "---- 开始 ----"

find_candidates || fail "无法读取磁盘列表。"
(( $#CANDIDATES )) || fail "没有找到装有 Windows 的硬盘（需要同时有 EFI 分区和 Microsoft 数据分区）。"

need_admin

for candidate in $CANDIDATES; do
	ESP_DEVICE=${candidate%% *}
	ESP_UUID=${candidate#* }
	if ! mount_esp; then
		log "无法只读挂载 $ESP_DEVICE，跳过"
		continue
	fi
	[[ -f "$ESP_MOUNT_POINT/$LOADER_SUBPATH" ]] && break
	log "$ESP_DEVICE 上没有 Windows Boot Manager，跳过"
	unmount_esp
	ESP_DEVICE="" ESP_MOUNT_POINT=""
done

[[ -n $ESP_MOUNT_POINT ]] || fail "检查了 ${(j:、:)${CANDIDATES%% *}}，都没能找到可用的 Windows Boot Manager（$LOADER_SUBPATH）。"

WINDOWS_LOADER="$ESP_MOUNT_POINT/$LOADER_SUBPATH"
say "Windows EFI 分区：$ESP_DEVICE（$ESP_UUID）"
say "Windows 启动文件：$WINDOWS_LOADER"
pending_next_boot && say "注意：当前已经有一个待生效的一次性启动设置。"

if [[ $MODE == --check ]]; then
	say "检查通过；没有修改启动项，也不会重启。"
	exit 0
fi

if [[ $MODE != --prepare ]]; then
	ANSWER=""
	print -n "确定仅下一次启动进入 Windows，并立即重启吗？[y/N] "
	read -r ANSWER
	if [[ $ANSWER != [yY] ]]; then
		say "已取消。"
		exit 0
	fi
fi

BLESS_OUTPUT=$($SUDO /usr/sbin/bless --mount "$ESP_MOUNT_POINT" --file "$WINDOWS_LOADER" --setBoot --nextonly --verbose 2>&1)
BLESS_STATUS=$?
log "bless 输出：$BLESS_OUTPUT"
if (( BLESS_STATUS != 0 )); then
	print -ru2 -- "$BLESS_OUTPUT"
	fail "无法把 Windows Boot Manager 设为下一次启动目标。"
fi

# 确认写进 NVRAM 的确实是这块 EFI 分区上的 Windows，而不只是“有个值”
NEXT_BOOT=$(/usr/sbin/nvram efi-boot-next 2>/dev/null)
log "efi-boot-next：$NEXT_BOOT"
if [[ ${(U)NEXT_BOOT} != *${(U)ESP_UUID}* && ${(L)NEXT_BOOT} != *bootmgfw.efi* ]]; then
	fail "启动变量没有按预期写入；为安全起见，本次不重启。可加 --cancel 参数运行此脚本清除，详细记录：$LOG_FILE"
fi

unmount_esp || log "警告：无法卸载 $ESP_DEVICE，重启时系统会自动卸载"

say "已设置：下一次启动进入 Windows。"
[[ $MODE == --prepare ]] && exit 0

if request_restart; then
	say "正在重启……如有未保存的文档，请在弹出的窗口中处理。"
	exit 0
fi

fail "启动项已设置，但无法自动发起重启。请从苹果菜单手动重启；如果不想进入 Windows 了，运行此脚本并加上 --cancel 参数即可撤销。"
