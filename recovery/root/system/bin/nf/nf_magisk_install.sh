#!/system/bin/sh
# nf_magisk_install.sh —— 用 Magisk v31.1 修补当前槽 init_boot 并写回
# 用法:
#   nf_magisk_install.sh          只看状态
#   nf_magisk_install.sh --dry    只生成补丁镜像到 /tmp/nf_magisk_new-boot.img
#   nf_magisk_install.sh --flash  真写 init_boot 分区
#
# 资源: /system/bin/nf/magisk/ 下已解出来的 boot_patch.sh + magiskboot/magiskinit/magisk/init-ld
#
# 2026-11-20 v2：修补完成后把 Magisk v31.1 安装包复制到内置存储根目录
#                （/sdcard/Magisk-v31.1.apk），并提示用户重启进系统后安装。
NF=$(cd "$(dirname "$0")" && pwd); . "$NF/nf_lib.sh"

ASSET=${NF_MAGISK_DIR:-$NF/magisk}
MODE=$1

SLOT=$(nf_slot)
SRC=$(nf_slot_pair | cut -d' ' -f2)
PART="init_boot$SLOT"
DEV="/dev/block/by-name/$PART"
[ -e "$DEV" ] || nf_die "找不到分区 $PART（当前槽 $SLOT，来源 $SRC）"
[ -f "$ASSET/boot_patch.sh" ] || nf_die "缺补丁资源: $ASSET/boot_patch.sh"

# Magisk 安装包：优先用内置存储里放好的，其次看镜像里有没有
# （不再往 ramdisk 里塞 10MB 的 apk，避免 ramdisk 体积膨胀）
APK=""
for cand in /sdcard/TWRP/Magisk-v31.1.apk /sdcard/TWRP/nf_pack/Magisk-v31.1.apk \
            /sdcard/Magisk-v31.1.apk /sdcard/TWRP/*.apk /sdcard/Magisk*.apk \
            /data/media/0/TWRP/Magisk-v31.1.apk /data/media/0/TWRP/nf_pack/Magisk-v31.1.apk \
            /data/media/0/Magisk-v31.1.apk /data/media/0/TWRP/*.apk /data/media/0/Magisk*.apk \
            "$ASSET/Magisk-v31.1.apk" "$NF/Magisk-v31.1.apk"; do
    [ -f "$cand" ] && { APK=$cand; break; }
done

# 把安装包放到内置存储根目录，让用户重启后能直接点开安装
nf_export_apk() {
    if [ -z "$APK" ]; then
        nf_say "[提示] 没找到 Magisk 安装包，root 已写入但还没放安装包。"
        nf_say "       请用 adb push 把 Magisk-v31.1.apk 放到 /sdcard/Magisk-v31.1.apk，"
        nf_say "       重启进系统后用文件管理器打开安装即可。"
        return 1
    fi
    case "$APK" in
        /sdcard/*|/data/media/0/*) dst=$APK; ;;
        *) dst=""
           for dir in /sdcard /data/media/0 /sdcard/TWRP; do
               [ -d "$dir" ] || continue
               if cp -f "$APK" "$dir/Magisk-v31.1.apk" 2>/dev/null; then
                   dst="$dir/Magisk-v31.1.apk"
                   break
               fi
           done
           [ -n "$dst" ] || { nf_say "[提示] 安装包复制失败，请手动取 $APK"; return 1; } ;;
    esac
    chmod 644 "$dst" 2>/dev/null
    nf_say "== 安装包就绪: $dst  ($(nf_human "$(stat -c %s "$dst")"))  md5=$(nf_md5 "$dst")"
    nf_say "   重启进系统后：用文件管理器打开这个 apk 安装（允许未知来源），"
    nf_say "   打开 Magisk App，按提示完成环境配置，root 即生效。"
    return 0
}

if [ -z "$MODE" ]; then
    nf_say "当前槽   : $SLOT（来源 $SRC）"
    nf_say "目标分区 : $PART  $(nf_human "$(nf_size "$DEV")")"
    nf_say "补丁资源 : $ASSET"
    nf_say "安装包   : ${APK:-（未随镜像附带）}"
    nf_say "写盘请用 : nf_magisk_install.sh --flash"
    exit 0
fi

W=/tmp/nf_magisk
rm -rf "$W"
mkdir -p "$W" || nf_die "无法创建 $W"
cp -r "$ASSET"/* "$W"/ 2>/dev/null || nf_die "复制补丁资源失败"
rm -f "$W"/Magisk*.apk 2>/dev/null
cd "$W" || nf_die "无法进入 $W"
chmod 755 magiskboot magiskinit magisk init-ld 2>/dev/null

nf_step 2 5 "读取分区 $PART"
dd if="$DEV" of="$W/init_boot.img" bs=1M 2>/dev/null || nf_die "读取 $PART 失败"
nf_say "== 分区镜像: $(nf_human "$(stat -c %s "$W/init_boot.img")")  md5=$(nf_md5 "$W/init_boot.img")"

nf_step 3 5 "修补 ramdisk（Magisk boot_patch.sh）"
# OUTFD 必须给：util_functions.sh 里会写 /proc/self/fd/$OUTFD，
# 为空时路径退化成目录 /proc/self/fd/ ，直接报 "Is a directory"。
OUTFD=1 KEEPVERITY=true KEEPFORCEENCRYPT=true sh "$W/boot_patch.sh" "$W/init_boot.img" || nf_die "boot_patch.sh 失败"

[ -f "$W/new-boot.img" ] || nf_die "没有产出 new-boot.img"
nf_say "补丁镜像 : $(nf_human "$(stat -c %s "$W/new-boot.img")")  md5=$(nf_md5 "$W/new-boot.img")"

if [ "$MODE" = "--dry" ]; then
    OUT=${NF_OUT:-/tmp}
    cp "$W/new-boot.img" "$OUT/nf_magisk_new-boot.img"
    nf_say "已存 $OUT/nf_magisk_new-boot.img（未写盘）"
    nf_step 5 5 "释放安装包到内置存储"
    nf_export_apk
    exit 0
fi

nf_step 4 5 "写回 $PART 并回读校对"
dd if="$W/new-boot.img" of="$DEV" bs=1M conv=fsync 2>/dev/null || nf_die "写入 $PART 失败"
sync
nf_say "完成：Magisk 已写入 $PART"
# 回读校对：写进去的必须和补丁镜像逐字节一致
dd if="$DEV" of="$W/readback.img" bs=1M 2>/dev/null
rb=$(nf_md5 "$W/readback.img")
if [ "$rb" = "$(nf_md5 "$W/new-boot.img")" ]; then
    nf_ok "回读校验一致 md5=$rb"
    nf_note "$PART 已打补丁，回读 md5 一致 → apk 已放到 /sdcard"
else
    nf_warn "回读校验不一致：期望 $(nf_md5 "$W/new-boot.img") 实际 $rb"
    nf_note "$PART 写入后回读不一致，请重刷官方 init_boot 再试"
fi
nf_step 5 5 "释放安装包到内置存储"
nf_export_apk || nf_warn "安装包没能放到内置存储，请手动导出 $APK"
nf_say "重启进系统后安装上面的 apk 即可获得 root。"
