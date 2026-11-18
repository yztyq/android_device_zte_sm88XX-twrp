#!/system/bin/sh
# nf_gui.sh —— 给 TWRP 界面按钮用的非交互入口（无 stdin、无提示）
# 用法: nf_gui.sh <ota|backup|restore [目录]|edl|magisk_off|magisk_on|log>
NF=$(cd "$(dirname "$0")" && pwd)
. "$NF/nf_lib.sh"

TWRP_DIR=/sdcard/TWRP
KEY_PARTS="boot init_boot vendor_boot dtbo recovery"

find_payload() {
    for p in /sdcard/payload.bin /sdcard/ota/payload.bin /sdcard/Download/payload.bin \
             /data/media/0/payload.bin "$TWRP_DIR"/payload.bin; do
        [ -f "$p" ] && { echo "$p"; return; }
    done
    return 1
}

latest_backup() {
    latest=""
    for d in "$TWRP_DIR"/BF*; do
        [ -d "$d" ] && latest=$d
    done
    echo "$latest"
}

case "$1" in
ota)
    NF_PDG=${NF_PDG:-$NF/payload-dumper-go}
    [ -x "$NF_PDG" ] || nf_die "缺 payload-dumper-go: $NF_PDG"
    payload=$(find_payload) || nf_die "没找到 payload.bin，请放到 /sdcard/payload.bin"
    nf_say "== payload: $payload"
    list=$("$NF_PDG" -l "$payload" 2>/dev/null | awk '{print $1}')
    [ -n "$list" ] || nf_die "payload 解析失败（文件损坏或不是 OTA 包）"
    parts=""
    skipped=""
    for p in $list; do
        if [ -e "/dev/block/by-name/$p" ]; then
            parts="$parts $p"
        else
            skipped="$skipped $p"
        fi
    done
    [ -n "$parts" ] || nf_die "包里没有可直写的物理分区"
    nf_say "== 可写分区:$parts"
    [ -n "$skipped" ] && nf_say "== 跳过（逻辑分区）:$skipped"
    sh "$NF/nf_ota.sh" "$payload" $parts
    ;;
backup)
    # BF + 年月日时分秒，例如 BF20261118163851
    DEST="$TWRP_DIR/BF$(date +%Y%m%d%H%M%S)"
    nf_say "== 备份到 $DEST"
    NF_DEST="$DEST" sh "$NF/nf_backup.sh" $KEY_PARTS
    ;;
restore)
    dir=$2
    [ -n "$dir" ] || dir=$(latest_backup)
    [ -d "$dir" ] || nf_die "备份目录不存在: ${dir:-$TWRP_DIR/BF* 下没有任何备份}"
    nf_say "== 使用备份 $dir"
    files=""
    for f in "$dir"/*.img; do
        [ -f "$f" ] || continue
        p=$(basename "$f" .img)
        [ -e "/dev/block/by-name/$p" ] && files="$files $f"
    done
    [ -n "$files" ] || nf_die "备份里没有可写回的分区镜像"
    sh "$NF/nf_restore.sh" $files
    ;;
edl)
    nf_say "== 切到 9008（EDL）"
    sh "$NF/nf_edl.sh" --yes
    ;;
magisk_off)
    nf_say "== 关闭所有 Magisk 模组"
    sh "$NF/nf_magisk_off.sh" --yes
    ;;
magisk_on)
    nf_say "== 一键 root：Magisk v31.1 修补当前槽 init_boot"
    sh "$NF/nf_magisk_install.sh" --flash
    ;;
log)
    nf_say "== 导出恢复日志"
    dst="/sdcard/recovery-$(date +%Y%m%d-%H%M%S).log"
    if [ -f /tmp/recovery.log ]; then
        cat /tmp/recovery.log >"$dst" || nf_die "写入 $dst 失败"
        nf_say "已保存 $dst ($(nf_human "$(stat -c %s "$dst")"))"
    else
        nf_die "/tmp/recovery.log 不存在"
    fi
    ;;
*)
    nf_say "用法: nf_gui.sh <ota|backup|restore [目录]|edl|magisk_off|magisk_on|log>"
    exit 1
    ;;
esac

nf_say "== 结束（exit 0）"
exit 0
