#!/system/bin/sh
# nf_magisk_off.sh —— 关闭所有 Magisk 模组（给每个模组目录放 disable 文件）
# 用法: nf_magisk_off.sh [--yes]
NF=$(cd "$(dirname "$0")" && pwd); . "$NF/nf_lib.sh"

MODDIR=/data/adb/modules
[ -d "$MODDIR" ] || nf_die "$MODDIR 不存在，/data 未解密或本机未装 Magisk"

if [ "$1" != "--yes" ]; then
    n=0
    for d in "$MODDIR"/*; do
        [ -d "$d" ] || continue
        [ -f "$d/disable" ] && continue
        n=$((n + 1))
        nf_say "  待关闭: $(basename "$d")"
    done
    nf_say "共 $n 个启用中的模组。确认请加 --yes：nf_magisk_off.sh --yes"
    exit 0
fi

n=0
for d in "$MODDIR"/*; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    case "$name" in
        modules_update|*.tmp) continue ;;
    esac
    touch "$d/disable" || nf_say "[警告] 无法写入 $name/disable"
    n=$((n + 1))
    nf_say "已关闭: $name"
done

sync
nf_say "共关闭 $n 个模组，重启到系统后生效"
nf_say "重新启用某个模组：删掉 /data/adb/modules/<模组名>/disable 即可"
