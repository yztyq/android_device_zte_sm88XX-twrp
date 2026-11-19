#!/system/bin/sh
# nf_restore.sh —— 把 .img 写回对应分区（文件名推断分区名，自动补槽位）
# 用法: nf_restore.sh <img文件> [img文件...]
# 写前比对 md5.txt，写后回读校验，全程报告结果
NF=$(cd "$(dirname "$0")" && pwd); . "$NF/nf_lib.sh"

if [ $# -lt 1 ]; then
    nf_say "用法: nf_restore.sh <img文件> [img文件...]（文件名=分区名）"
    exit 1
fi

# 同一目录里若有 md5.txt，用来核对源文件完整性
MD5FILE="$(dirname "$1")/md5.txt"

# 第一遍：全部校验，任何一条不过都不写
for f in "$@"; do
    [ -f "$f" ] || nf_die "文件不存在: $f"
    p=$(basename "$f" .img)
    dev=$(nf_dev "$p")
    [ -n "$dev" ] || nf_die "按文件名推断的分区不存在: $p"
    isize=$(stat -c %s "$f")
    psize=$(nf_size "$dev")
    nf_ge "$psize" "$isize" || nf_die "$p 镜像 $(nf_human "$isize") 大于分区 $(nf_human "$psize")，拒绝写入"
    md5=$(nf_md5 "$f")
    expect=""
    [ -f "$MD5FILE" ] && expect=$(awk -v n="$p" '$1==n {print $3}' "$MD5FILE")
    if [ -n "$expect" ]; then
        if [ "$expect" = "$md5" ]; then
            nf_say "校验通过: $p  $(nf_human "$isize")  md5 与清单一致 [OK]"
        else
            nf_die "$p 的 md5 与清单不符（文件=$md5 清单=$expect），拒绝写入"
        fi
    else
        nf_say "校验通过: $p  $(nf_human "$isize")  （无清单，md5=$md5）"
    fi
done

# 第二遍：写入 + 回读校验
bad=0
n=$#
i=0
for f in "$@"; do
    i=$((i + 1))
    p=$(basename "$f" .img)
    dev=$(nf_dev "$p")
    isize=$(stat -c %s "$f")
    srcmd5=$(nf_md5 "$f")
    nf_step "$i" "$n" "正在还原 $p -> $(basename "$dev")"
    dd if="$f" of="$dev" bs=1M conv=fsync 2>/dev/null || nf_die "写入失败: $p"
    sync
    nf_check_part "$p" "$dev" "$isize" "$srcmd5" 还原 || bad=$((bad + 1))
done

nf_say "还原完成，不一致 $bad 个；请重启到系统验证"
nf_note "共 $n 个分区，回读不一致 $bad 个"
[ "$bad" -eq 0 ] || exit 1
