-- 重启到 Windows：仅下一次启动进入 Windows，从 Windows 再次重启后自动回到 macOS。
--
-- 需要管理员权限的部分（挂载 EFI、bless、核对 NVRAM）交给内置脚本的 --prepare 模式；
-- 重启则由本 App 以当前用户身份发起，和苹果菜单里的“重新启动…”一样，应用有机会保存文档。

property appTitle : "重启到 Windows"

on run
	activate
	set helperPath to POSIX path of (path to resource "reboot-to-windows.command")

	try
		display dialog "电脑将仅在下一次启动时进入 Windows。" & return & "从 Windows 再次重启后，会自动回到 macOS。" with title appTitle buttons {"取消", "重启到 Windows"} default button "重启到 Windows" cancel button "取消" with icon (path to resource "applet.icns")
	on error number -128
		return
	end try

	try
		runHelper(helperPath, "--prepare")
	on error errorMessage number errorNumber
		if errorNumber is not -128 then display alert "无法设置下一次启动 Windows" message errorMessage as critical
		return
	end try

	try
		tell application "loginwindow" to «event aevtrest»
	on error errorMessage
		set answer to button returned of (display alert "已设置下一次启动 Windows，但无法自动重启" message "请从苹果菜单选择“重新启动…”。如果不想进入 Windows 了，可以撤销这次设置。" & return & return & errorMessage buttons {"撤销设置", "好"} default button "好")
		if answer is "撤销设置" then cancelNextBoot(helperPath)
	end try
end run

on cancelNextBoot(helperPath)
	try
		runHelper(helperPath, "--cancel")
		display alert "已撤销" message "下次启动将进入默认系统。"
	on error errorMessage number errorNumber
		if errorNumber is not -128 then display alert "撤销失败" message errorMessage as critical
	end try
end cancelNextBoot

-- 以 root 运行内置脚本；传入 HOME，让日志写到当前用户的 ~/Library/Logs
on runHelper(helperPath, flag)
	set command to "/usr/bin/env HOME=" & quoted form of (system attribute "HOME") & " /bin/zsh " & quoted form of helperPath & " " & flag & " </dev/null"
	do shell script command with prompt "“重启到 Windows”需要管理员权限来设置下一次启动的系统。" with administrator privileges
end runHelper
