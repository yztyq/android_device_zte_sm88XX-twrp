#!/system/bin/sh
# nf_selftest.sh —— 在 TWRP 终端（root）里跑，一次性验证备份/还原/Magisk 补丁链路
# 用法: sh /tmp/nf/nf_selftest.sh
NF=/tmp/nf
. "$NF/nf_lib.sh"
LOG=/tmp/nf_selftest.log

{
    echo "==== nf selftest $(date) ===="
    echo "uid=$(id)"
    echo
    echo "---- 1) 分区识别 ----"
    for p in boot_a init_boot_a vendor_boot_a dtbo_a; do
        printf "  %-14s %s\n" "$p" "$(nf_human "$(nf_size "/dev/block/by-name/$p")")"
    done
    echo
    echo "---- 2) 备份 dtbo_a（写 /tmp/nf_selftest）----"
    NF_DEST=/tmp/nf_selftest sh "$NF/nf_backup.sh" dtbo_a
    echo
    echo "---- 3) 还原 dtbo_a（内容相同，安全）----"
    sh "$NF/nf_restore.sh" /tmp/nf_selftest/dtbo_a.img
    echo
    echo "---- 4) Magisk 补丁 init_boot（只生成，不写盘）----"
    sh "$NF/nf_magisk_install.sh" --dry
    echo
    echo "==== selftest done ===="
} >"$LOG" 2>&1

cat "$LOG"
