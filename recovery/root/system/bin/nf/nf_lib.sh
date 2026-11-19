#!/system/bin/sh
# nf_lib.sh —— 自定义功能公共函数（红魔 11 Pro+ / sm88XX / TWRP 4.0）
#
# 2026-11-19 修复：本机所有分区都是 A/B 命名（boot_a / init_boot_a …），
# 之前脚本直接找 /dev/block/by-name/boot 这类裸名，一定找不到，
# 导致备份/还原/OTA 全部失败。现在统一走 nf_dev() 解析：
#   裸名 boot -> 当前槽 boot_a
#   已带槽位 boot_a -> 原样返回
# 找不到则返回 1，由调用方决定跳过还是报错。
#
# 2026-11-20 追加：nf_ts() 兜底时间。recovery 里 RTC 常常是 1970，
# 直接 date 出来的目录名会变成 BF1970…，改用 /sdcard 的 mtime 兜底。

# 日志落到 /sdcard，重启后不会丢（之前写 /tmp，一重启就没了，没法排查）
NF_LOG=${NF_LOG:-/sdcard/TWRP/nf.log}
[ -d /sdcard/TWRP ] || NF_LOG=/tmp/nf.log
# 一行同时送往：屏幕（GUI2 进度页实时读 stdout）、存档日志
# 注意：不要自己写 /tmp/recovery.log —— TWRP 执行命令时会把子进程 stdout
#       直接抓进 recovery.log，自己再写一遍就会每行重复两次。
nf_emit() {
    echo "$1"
    echo "$1" >>"$NF_LOG" 2>/dev/null
}

nf_say()  { t=$(date +%H:%M:%S 2>/dev/null); nf_emit "[$t] $*"; }
nf_die()  { nf_bad "$*"; exit 1; }

# —— 进度与结果标记 ——
nf_rule() { nf_emit "=================================================="; }
nf_title() { NF_TITLE="$*"; rm -f /sdcard/TWRP/nf_note.txt 2>/dev/null; nf_rule; nf_emit ">>> $*"; nf_rule; }
# 子脚本用 nf_note 说明这次到底做了多少，收尾时会被写进菜单行
nf_note() { echo "$*" >/sdcard/TWRP/nf_note.txt 2>/dev/null; }
# nf_step 当前 总数 描述  ->  >>> [3/6] 50% 备份 boot_a
nf_step() {
    i=$1; n=${2:-0}; shift 2; d=$*
    pct=0
    [ "$n" -gt 0 ] 2>/dev/null && pct=$((i * 100 / n))
    nf_emit ">>> [$i/$n] ${pct}%  $d"
}
nf_ok()   { nf_emit ">>> [成功] $*"; }
nf_bad()  { nf_emit ">>> [失败] $*"; }
nf_warn() { nf_emit ">>> [警告] $*"; }

# —— 无编译的屏幕反馈：把上次结果写回「进阶功能」菜单首行 ——
# 菜单页每次进入都会重新读 /sdcard/TWRP/nf_menu.conf，所以改这个文件，
# 下次进页面第一行就是上次的执行结论（实时进度条仍需重编译 GUI）。
NF_CONF=/sdcard/TWRP/nf_menu.conf

nf_default_conf() {
    cat <<'EOF'
安装 OTA 包|选 zip / payload.bin，再勾选要写入的分区|@ota
备份分区|勾选分区，存到 /sdcard/TWRP/BF日期时间|@backup
还原分区|浏览 /sdcard 任意文件夹，勾选镜像写回|@restore
一键进入 9008|切到 EDL 下载模式|/system/bin/sh /system/bin/nf/nf_gui.sh edl
关闭所有 Magisk 模组|给每个启用中的模组放 disable 标记|/system/bin/sh /system/bin/nf/nf_gui.sh magisk_off
一键 root|Magisk v31.1 补丁当前槽 init_boot 并写回|/system/bin/sh /system/bin/nf/nf_gui.sh magisk_on
导出恢复日志|把命令输出复制到 /sdcard|/system/bin/sh /system/bin/nf/nf_gui.sh log
EOF
}

# nf_report 动作名 成功|失败 补充说明
nf_report() {
    name=$1; res=$2; note=$3
    [ -d /sdcard/TWRP ] || return 0
    if [ -z "$note" ] && [ -f /sdcard/TWRP/nf_note.txt ]; then
        note=$(cat /sdcard/TWRP/nf_note.txt 2>/dev/null)
    fi
    printf '%s|%s|%s\n' "$name" "$res" "$note" >/sdcard/TWRP/nf_last.txt 2>/dev/null
    ts=$(nf_ts)
    hhmm=$(echo "$ts" | sed 's/.*\(..\)\(..\)\(..\)$/\1:\2:\3/' 2>/dev/null)
    [ -n "$hhmm" ] || hhmm=$ts
    row="上次：$name $res（$hhmm）|$note|@none"
    if [ -f "$NF_CONF" ]; then
        grep -v '^上次：' "$NF_CONF" >"$NF_CONF.tmp" 2>/dev/null
        { echo "$row"; cat "$NF_CONF.tmp" 2>/dev/null; } >"$NF_CONF" 2>/dev/null
    else
        { echo "$row"; nf_default_conf; } >"$NF_CONF" 2>/dev/null
    fi
    rm -f "$NF_CONF.tmp"
}

# 写完之后回读比对：分区 ≤ 256MB 才做（大分区跳过，避免双倍 IO）
# 用法: nf_check_part <显示名> <分区设备> <字节数> <源md5> <动作词>
#   打印一行结论，一致返回 0，不一致返回 1（调用方据此累加 bad 计数）
nf_check_part() {
    _nm=$1; _dev=$2; _sz=$3; _want=$4; _act=$5
    _got=""
    if nf_ge 268435456 "$_sz"; then
        _blk=$((_sz / 1048576))
        [ "$_blk" -gt 0 ] || _blk=1
        dd if="$_dev" of=/tmp/nf_chk.img bs=1M count=$_blk 2>/dev/null
        _got=$(nf_md5 /tmp/nf_chk.img)
        rm -f /tmp/nf_chk.img
    fi
    if [ -z "$_got" ]; then
        nf_ok "$_nm $_act完成 $(nf_human "$_sz") md5=$_want（大分区，跳过回读）"
        return 0
    fi
    if [ "$_got" = "$_want" ]; then
        nf_ok "$_nm $_act完成 $(nf_human "$_sz") md5=$_want 回读一致"
        return 0
    fi
    nf_bad "$_nm $_act完成但回读不一致 期望=$_want 实际=$_got"
    return 1
}

# 当前槽：优先级 getprop ro.boot.slot_suffix → /proc/cmdline → ro.boot.slot → 默认 _a
# 输出 "<槽后缀> <来源>"，nf_slot 只取前半段。
nf_slot_pair() {
    s=$(getprop ro.boot.slot_suffix 2>/dev/null)
    [ -n "$s" ] && { echo "$s getprop"; return; }
    s=$(tr ' ' '\n' < /proc/cmdline 2>/dev/null | grep '^androidboot.slot_suffix=' | head -1 | cut -d= -f2)
    [ -n "$s" ] && { echo "$s cmdline"; return; }
    b=$(getprop ro.boot.slot 2>/dev/null)
    [ -n "$b" ] && { echo "_$b ro.boot.slot"; return; }
    echo "_a default"
}

nf_slot() { nf_slot_pair | cut -d' ' -f1; }

# 当前时间 YYYYMMDDHHMMSS；RTC 不可信（1990 年前 / 系统年份明显早于 2024）时
# 用 /sdcard 或 /data/media/0 的 mtime 兜底，保证备份目录名有意义。
nf_ts() {
    d=$(date +%Y%m%d%H%M%S 2>/dev/null)
    y=$(echo "$d" | cut -c1-4)
    case "$y" in
        19*|200[0-9]*|201[0-9]*)
            for src in /sdcard /data/media/0 /; do
                m=$(stat -c %y "$src" 2>/dev/null)
                [ -n "$m" ] || continue
                t=$(echo "$m" | awk '{split($1,a,"-"); echo a[1] a[2] a[3] $2}' | tr -d ':')
                case "$t" in
                    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) d=$t; break ;;
                esac
            done
            ;;
    esac
    echo "$d"
}

# 解析分区设备节点（自动补当前槽后缀，也支持裸名/函数外的 _a _b）
nf_dev() {
    name=$1
    if [ -e "/dev/block/by-name/$name" ]; then
        echo "/dev/block/by-name/$name"
        return 0
    fi
    slot=$(nf_slot)
    if [ -e "/dev/block/by-name/$name$slot" ]; then
        echo "/dev/block/by-name/$name$slot"
        return 0
    fi
    other=_a
    [ "$slot" = "_a" ] && other=_b
    if [ -e "/dev/block/by-name/$name$other" ]; then
        echo "/dev/block/by-name/$name$other"
        return 0
    fi
    return 1
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

# 列出可备份的物理分区（含槽位，排除杂项）
nf_list_parts() {
    for d in /dev/block/by-name/*; do
        n=$(basename "$d")
        case "$n" in
            ALIGN_TO_128K_*|cdt|ddr|devinfo|dpm|efisp|fsg|fsc|fs_bkup|apdp|apdpb|connsec|frp|misc|persist*|rawdump|secdata|xbl*) continue ;;
        esac
        [ -e "$d" ] && echo "$n"
    done
}
