#!/system/bin/sh
# nf_restore.sh —— 把 .img 写回对应分区（按文件名推断分区名）
# 用法: nf_restore.sh <img文件> [img文件...]
#   例: nf_restore.sh /sdcard/nf_backup/xxx/boot.img
NF=$(cd "$(dirname "$0")" && pwd); . "$NF/nf_lib.sh"

if [ $# -lt 1 ]; then
    nf_say "用法: nf_restore.sh <img文件> [img文件...]（文件名=分区名，如 boot.img）"
    exit 1
fi

# 第一遍：全部校验，任何一条不过都不写
for f in "$@"; do
    [ -f "$f" ] || nf_die "文件不存在: $f"
    p=$(basename "$f" .img)
    dev="/dev/block/by-name/$p"
    [ -e "$dev" ] || nf_die "按文件名推断的分区不存在: $p"
    isize=$(stat -c %s "$f")
    psize=$(nf_size "$dev")
    nf_ge "$psize" "$isize" || nf_die "$p 镜像 $(nf_human "$isize") 大于分区 $(nf_human "$psize")，拒绝写入"
    nf_say "校验通过: $p  $(nf_human "$isize") -> 分区 $(nf_human "$psize")"
done

# 第二遍：写入
for f in "$@"; do
    p=$(basename "$f" .img)
    dev="/dev/block/by-name/$p"
    nf_say "== 还原 $p"
    dd if="$f" of="$dev" bs=1M conv=fsync 2>/dev/null || nf_die "写入失败: $p"
    sync
    nf_say "   写入完成（$(nf_human "$(stat -c %s "$f")")）"
done

nf_say "还原完成，请重启到系统验证"
