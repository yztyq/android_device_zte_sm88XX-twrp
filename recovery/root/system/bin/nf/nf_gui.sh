#!/system/bin/sh
# nf_gui.sh —— 给 TWRP 界面按钮用的非交互入口（无 stdin、无提示）
# 用法:
#   nf_gui.sh ota <zip|payload.bin> [分区名...]   安装 OTA，只写指定的物理分区
#   nf_gui.sh backup [分区名...]                  备份（不给分区则用默认组合）
#   nf_gui.sh restore <目录> [img名...]           从目录还原（不给 img 则全部）
#   nf_gui.sh edl | magisk_off | magisk_on | log
#
# 2026-11-19 v3：分区名支持裸名（boot），由 nf_dev() 自动补当前槽；
#               备份/还原全流程带 MD5 校对。
# 2026-11-20 v4：修 backup/restore 的子命令被当成参数（shift 缺失）；
#               目录名改用 nf_ts() 兜底时间。
NF=$(cd "$(dirname "$0")" && pwd)
. "$NF/nf_lib.sh"

# 统一收尾：无论成功失败都在日志里留一条明确结论（界面「执行完毕」之外的可查证据）
NF_START=$(date +%s 2>/dev/null)
nf_trap() {
    rc=$?
    end=$(date +%s 2>/dev/null)
    sec=0
    [ -n "$NF_START" ] && [ -n "$end" ] && sec=$((end - NF_START))
    nf_rule
    if [ "$rc" -eq 0 ]; then
        nf_ok "全部完成，用时 ${sec} 秒"
        nf_report "${NF_TITLE:-操作}" "成功" "用时 ${sec} 秒"
    else
        nf_bad "未完成（退出码 $rc），用时 ${sec} 秒"
        nf_report "${NF_TITLE:-操作}" "失败" "退出码 $rc，用时 ${sec} 秒"
    fi
    nf_emit ">>> 日志文件: $NF_LOG"
    nf_rule
}
trap nf_trap EXIT

TWRP_DIR=/sdcard/TWRP
KEY_PARTS="boot init_boot vendor_boot dtbo recovery vbmeta"

payload_from() {
    src=$1
    case "$src" in
        *.zip)
            W=/tmp/nf_payload
            rm -rf "$W"; mkdir -p "$W" || return 1
            nf_say "== 从 zip 取 payload.bin"
            unzip -o -q "$src" payload.bin -d "$W" || return 1
            [ -f "$W/payload.bin" ] || return 1
            echo "$W/payload.bin"
            ;;
        *)
            [ -f "$src" ] || return 1
            echo "$src"
            ;;
    esac
}

case "$1" in
ota)
    src=$2
    shift 2 2>/dev/null
    [ $# -ge 0 ] || shift
    [ -n "$src" ] || nf_die "没有指定 OTA 文件"
    nf_title "安装 OTA 包"
    nf_step 1 3 "检查 OTA 文件: $(basename "$src")"
    payload=$(payload_from "$src") || nf_die "取 payload.bin 失败: $src"
    nf_say "== payload: $payload"
    nf_step 2 3 "解包并写入分区"
    if [ $# -ge 1 ]; then
        sh "$NF/nf_ota.sh" "$payload" "$@"
    else
        sh "$NF/nf_ota.sh" "$payload"
    fi
    nf_step 3 3 "OTA 写入结束"
    ;;
backup)
    shift
    if [ $# -ge 1 ]; then
        parts="$*"
    else
        parts="$KEY_PARTS"
    fi
    DEST="$TWRP_DIR/BF$(nf_ts)"
    nf_title "备份分区"
    nf_say "== 备份到 $DEST"
    nf_step 1 2 "准备目录与空间检查"
    NF_DEST="$DEST" sh "$NF/nf_backup.sh" $parts
    nf_step 2 2 "备份与 MD5 校对结束"
    ;;
restore)
    dir=$2
    shift 2 2>/dev/null
    [ -n "$dir" ] || nf_die "没有指定备份目录"
    [ -d "$dir" ] || nf_die "目录不存在: $dir"
    nf_title "还原分区"
    nf_say "== 使用备份 $dir"
    if [ $# -ge 1 ]; then
        files=""
        for n in "$@"; do
            # 依次尝试：原样、补 .img、按当前槽换真实名（boot -> boot_a.img）
            cand=""
            for c in "$n" "${n%.img}.img"; do
                [ -f "$dir/$c" ] && { cand="$dir/$c"; break; }
            done
            if [ -z "$cand" ]; then
                dev=$(nf_dev "$n")
                [ -n "$dev" ] && cand="$dir/$(basename "$dev").img"
            fi
            if [ -f "$cand" ]; then
                files="$files $cand"
            else
                nf_say "[跳过] 目录里没有: $n"
            fi
        done
        [ -n "$files" ] || nf_die "目录里没有选中的镜像"
    else
        files=""
        for f in "$dir"/*.img; do
            [ -f "$f" ] && files="$files $f"
        done
        [ -n "$files" ] || nf_die "目录里没有任何 .img"
    fi
    sh "$NF/nf_restore.sh" $files
    ;;
edl)
    nf_title "进入 9008（EDL）下载模式"
    nf_step 1 1 "写入重启标志并跳转 EDL"
    sh "$NF/nf_edl.sh" --yes
    ;;
magisk_off)
    nf_title "关闭所有 Magisk 模组"
    sh "$NF/nf_magisk_off.sh" --yes
    ;;
magisk_on)
    nf_title "一键 root（Magisk v31.1 修补当前槽 init_boot）"
    nf_step 1 5 "定位当前槽与 init_boot 分区"
    sh "$NF/nf_magisk_install.sh" --flash
    ;;
log)
    nf_title "导出恢复日志"
    dst="/sdcard/recovery-$(nf_ts).log"
    if [ -f /tmp/recovery.log ]; then
        cat /tmp/recovery.log >"$dst" || nf_die "写入 $dst 失败"
        nf_say "已保存 $dst ($(nf_human "$(stat -c %s "$dst")"))"
    else
        nf_die "/tmp/recovery.log 不存在"
    fi
    ;;
*)
    nf_say "用法: nf_gui.sh <ota <文件> [分区]|backup [分区]|restore <目录> [img]|edl|magisk_off|magisk_on|log>"
    exit 1
    ;;
esac

nf_say "== 结束（exit 0）"
exit 0
