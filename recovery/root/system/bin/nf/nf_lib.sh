#!/system/bin/sh
# nf_lib.sh —— 自定义功能公共函数（红魔 11 Pro+ / sm88XX / TWRP 4.0）

NF_LOG=${NF_LOG:-/tmp/nf.log}

nf_say() { echo "$*"; echo "$*" >>"$NF_LOG" 2>/dev/null; }
nf_die() { nf_say "[错误] $*"; exit 1; }

nf_byname() { echo "/dev/block/by-name/$1"; }

nf_slot() {
    s=$(getprop ro.boot.slot_suffix)
    [ -n "$s" ] || s=_a
    echo "$s"
}

# 分区字节数：blockdev → sysfs → /proc/partitions 依次兜底
nf_size() {
    sz=$(blockdev --getsize64 "$1" 2>/dev/null)
    if [ -n "$sz" ] && [ "$sz" -gt 0 ] 2>/dev/null; then echo "$sz"; return; fi
    real=$(readlink -f "$1" 2>/dev/null)
    nb=$(basename "$real")
    sec=$(cat "/sys/class/block/$nb/size" 2>/dev/null)
    if [ -n "$sec" ]; then echo $((sec * 512)); return; fi
    awk -v n="$nb" '$4==n {print $3*1024; exit}' /proc/partitions 2>/dev/null
}

nf_human() {
    awk -v b="$1" 'BEGIN{split("B KB MB GB TB",u," ");i=1;while(b>=1024&&i<5){b/=1024;i++}printf "%.1f%s",b,u[i]}'
}

nf_free() {
    df -k "$1" 2>/dev/null | tail -1 | awk '{print $4*1024}'
}

nf_md5() { md5sum "$1" 2>/dev/null | cut -d' ' -f1; }

# 大数比较（sh 的 [ ] 是 32 位，几 GB 会溢出，统一交给 awk）
nf_ge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a >= b)}'; }
nf_add() { awk -v s="$1" -v n="$2" 'BEGIN{printf "%.0f", s + n}'; }

# /data 是否已解密可用
nf_data_ready() {
    [ -d /data/media/0 ] && [ -d /data/adb ] && return 0
    [ -d /data/adb ] && return 0
    mount | grep -q " /data " && return 0
    return 1
}
