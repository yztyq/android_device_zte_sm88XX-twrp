#!/system/bin/sh
# nf_ota.sh —— 安装 OTA 包（payload.bin）里的分区
# 用法:
#   nf_ota.sh <payload.bin>                     只列出包内分区
#   nf_ota.sh <payload.bin> boot init_boot ...  只刷指定分区
#
# 说明: 只有「物理分区」能直接 dd（by-name 里有同名节点）。
#       system/product/vendor 这类逻辑分区在 super 里，本脚本会跳过并提示。
NF=$(cd "$(dirname "$0")" && pwd); . "$NF/nf_lib.sh"

PD=${NF_PDG:-$NF/payload-dumper-go}
[ -x "$PD" ] || nf_die "缺 payload-dumper-go: $PD"

payload=$1
shift 2>/dev/null
[ -f "$payload" ] || nf_die "payload 文件不存在: $payload"

if [ $# -lt 1 ]; then
    nf_say "== payload 内分区列表"
    "$PD" -l "$payload" || nf_die "payload 解析失败（文件损坏或不是 OTA payload）"
    nf_say ""
    nf_say "刷指定分区: nf_ota.sh $payload boot init_boot vendor_boot dtbo"
    nf_say "（只建议选物理分区；逻辑分区无法直接写）"
    exit 0
fi

# 拼分区列表
parts=""
for p in "$@"; do
    if [ -z "$parts" ]; then parts=$p; else parts=$parts,$p; fi
done

OUT=/tmp/nf_ota
rm -rf "$OUT"
mkdir -p "$OUT" || nf_die "无法创建 $OUT"
cd "$OUT" || nf_die "无法进入 $OUT"

nf_say "== 解析 payload（分区: $parts）"
"$PD" -p "$parts" "$payload" || nf_die "解包失败"

n_ok=0
n_skip=0
for img in "$OUT"/extracted_*.img; do
    [ -f "$img" ] || continue
    p=$(basename "$img" .img)
    p=${p#extracted_}
    dev="/dev/block/by-name/$p"
    if [ ! -e "$dev" ]; then
        nf_say "跳过 $p：by-name 里没有这个物理分区（逻辑分区，需重建 super）"
        n_skip=$((n_skip + 1))
        continue
    fi
    nf_say "== 写入 $p -> $dev  ($(nf_human "$(stat -c %s "$img")"))"
    dd if="$img" of="$dev" bs=1M conv=fsync 2>/dev/null || nf_die "写入失败: $p"
    sync
    n_ok=$((n_ok + 1))
done

rm -rf "$OUT"
nf_say "完成：写入 $n_ok 个分区，跳过 $n_skip 个"
