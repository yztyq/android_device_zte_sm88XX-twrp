#!/system/bin/sh
# nf_backup.sh —— 按分区 dd 备份到 .img
# 用法: nf_backup.sh <分区名> [分区名...]
#       NF_DEST=/sdcard/xxx nf_backup.sh boot dtbo
NF=$(cd "$(dirname "$0")" && pwd); . "$NF/nf_lib.sh"

if [ $# -lt 1 ]; then
    nf_say "用法: nf_backup.sh <分区名> [分区名...]"
    nf_say "可用分区（by-name）:"
    for d in /dev/block/by-name/*; do
        printf "  %-22s %s\n" "$(basename "$d")" "$(nf_human "$(nf_size "$d")")"
    done
    exit 1
fi

DEST=${NF_DEST:-/sdcard/nf_backup/$(date +%Y%m%d-%H%M%S)}
mkdir -p "$DEST" || nf_die "无法创建目录 $DEST"

total=0
for p in "$@"; do
    [ -e "/dev/block/by-name/$p" ] || nf_die "分区不存在: $p"
    total=$(nf_add "$total" "$(nf_size "/dev/block/by-name/$p")")
done

free=$(nf_free "$DEST")
nf_say "目标目录 : $DEST"
nf_say "需要空间 : $(nf_human "$total")    可用: $(nf_human "$free")"
nf_ge "$free" "$total" || nf_die "存储空间不足，请先清理目标目录所在分区"

: >"$DEST/md5.txt"
for p in "$@"; do
    dev="/dev/block/by-name/$p"
    nf_say "== 备份 $p"
    dd if="$dev" of="$DEST/$p.img" bs=1M 2>/dev/null || nf_die "dd 读取失败: $p"
    sync
    size=$(stat -c %s "$DEST/$p.img" 2>/dev/null)
    md5=$(nf_md5 "$DEST/$p.img")
    nf_say "   $(nf_human "$size")  md5=$md5"
    echo "$p $size $md5" >>"$DEST/md5.txt"
done

nf_say "备份完成: $DEST"
