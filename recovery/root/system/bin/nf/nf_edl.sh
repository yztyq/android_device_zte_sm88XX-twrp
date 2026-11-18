#!/system/bin/sh
# nf_edl.sh —— 一键进 9008（EDL）
# 用法: nf_edl.sh [--yes]
NF=$(cd "$(dirname "$0")" && pwd); . "$NF/nf_lib.sh"

if [ "$1" != "--yes" ]; then
    nf_say "确认进 9008 模式？设备会直接掉到 EDL，需要用 QFIL/9008 工具操作。"
    nf_say "确认请加 --yes：nf_edl.sh --yes"
    exit 1
fi

nf_say "3 秒后进入 EDL…"
sleep 3
sync

# 逐级尝试：reboot 带 reason → init 的 powerctl → 内核 reboot reason 文件
reboot edl
sleep 2
setprop sys.powerctl reboot,edl
sleep 2
echo edl > /proc/sys/kernel/boot_reason 2>/dev/null
sleep 2

nf_say "常规方式没生效，改用 QC 的 EDL 触发：把设备回落到 fastboot 后再 fastboot oem edl"
setprop sys.powerctl reboot,bootloader
