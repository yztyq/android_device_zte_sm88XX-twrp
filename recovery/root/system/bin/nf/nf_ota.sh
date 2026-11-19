#!/system/bin/sh
# nf_ota.sh —— 安装 OTA 包（payload.bin）里的指定物理分区
# 用法:
#   nf_ota.sh <payload.bin>                     只列出包内分区
#   nf_ota.sh <payload.bin> boot init_boot ...  只刷指定分区（裸名/带槽名都认）
#
# 说明: 只有「物理分区」能直接 dd（by-name 里有节点）；包里的逻辑分区
#       （system/product/vendor 等）无法这样写，脚本会跳过并提示。
NF=$(cd "$(dirname "$0")" && pwd); . "$NF/nf_lib.sh"

PD=${NF_PDG:-$NF/payload-dumper-go}
[ -x "$PD" ] || nf_die "缺 payload-dumper-go: $PD"

payload=$1
shift 2>/dev/null
[ -f "$payload" ] || nf_die "payload 文件不存在: $payload"

# 包内分区清单（-l 的输出按空白切词，取像分区名的串）
listing=$("$PD" -l "$payload" 2>/dev/null)
[ -n "$listing" ] || nf_die "payload 解析失败（文件损坏或不是 OTA payload）"

if [ $# -lt 1 ]; then
    nf_say "== payload 内分区"
    echo "$listing"
    nf_say ""
    nf_say "刷指定分区: nf_ota.sh $payload boot init_boot vendor_boot dtbo"
    exit 0
fi

# 把用户选的分区名映射成 payload 里的名字，只保留双方都有的物理分区
want=""
for p in "$@"; do
    base=${p%_a}; base=${base%_b}
    hit=""
    if echo "$listing" | grep -qw "$p"; then
        hit=$p
    elif echo "$listing" | grep -qw "$base"; then
        hit=$base
    fi
    if [ -z "$hit" ]; then
        nf_say "[跳过] payload 里没有: $p"
        continue
    fi
    if [ -z "$(nf_dev "$hit")" ]; then
        nf_say "[跳过] 本机没有对应物理分区（逻辑分区需重建 super）: $hit"
        continue
    fi
    if [ -z "$want" ]; then want=$hit; else want=$want,$hit; fi
done
[ -n "$want" ] || nf_die "选中的分区都不在 payload / 不可直写"

OUT=/tmp/nf_ota
rm -rf "$OUT"
mkdir -p "$OUT" || nf_die "无法创建 $OUT"
cd "$OUT" || nf_die "无法进入 $OUT"

nf_say "== 解包分区: $want"
"$PD" -p "$want" "$payload" || nf_die "解包失败"

n_ok=0
bad=0
for img in "$OUT"/extracted_*.img; do
    [ -f "$img" ] || continue
    p=$(basename "$img" .img); p=${p#extracted_}
    dev=$(nf_dev "$p")
    if [ -z "$dev" ]; then
        nf_say "[跳过] $p：本机没有这个物理分区"
        continue
    fi
    isz=$(stat -c %s "$img")
    nf_say "== 写入 $p -> $(basename "$dev")  ($(nf_human "$isz"))"
    dd if="$img" of="$dev" bs=1M conv=fsync 2>/dev/null || nf_die "写入失败: $p"
    sync
    md5=$(nf_md5 "$img")
    if nf_ge 268435456 "$isz"; then
        blocks=$((isz / 1048576))
        dd if="$dev" of=/tmp/nf_chk.img bs=1M count=$blocks 2>/dev/null
        devmd5=$(nf_md5 /tmp/nf_chk.img); rm -f /tmp/nf_chk.img
        if [ "$devmd5" = "$md5" ]; then
            nf_say "   md5=$md5  [回读一致]"
        else
            nf_say "   md5=$md5  回读=$devmd5  [回读不一致]"; bad=$((bad + 1))
        fi
    else
        nf_say "   md5=$md5（分区较大，跳过回读）"
    fi
    n_ok=$((n_ok + 1))
done

rm -rf "$OUT"
nf_say "完成：写入 $n_ok 个分区，校验不一致 $bad 个"
[ "$bad" -eq 0 ] || exit 1
