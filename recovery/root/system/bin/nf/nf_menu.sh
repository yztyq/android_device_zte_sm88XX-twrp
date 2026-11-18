#!/system/bin/sh
# nf_menu.sh —— 终端里的文本菜单（界面按钮做好之前先用这个验证功能）
# 用法: nf 或 nf_menu.sh
NF=$(cd "$(dirname "$0")" && pwd); . "$NF/nf_lib.sh"
SLOT=$(nf_slot)

while :; do
    echo ""
    echo "================ 自定义功能 ================"
    echo " 1) 安装 OTA 包（payload.bin 逐分区）"
    echo " 2) 备份分区（dd 存 .img）"
    echo " 3) 还原分区（dd 写回）"
    echo " 4) 一键进 9008 (EDL)"
    echo " 5) 关闭所有 Magisk 模组"
    echo " 6) 安装 Magisk v31.1（补丁 $SLOT 槽 init_boot）"
    echo " q) 退出"
    printf "请选择: "
    read -r c
    case "$c" in
        1)
            printf "payload.bin 路径（如 /sdcard/ota.zip 里的 payload.bin）: "
            read -r f
            sh "$NF/nf_ota.sh" "$f"
            ;;
        2)
            echo "常用分区: boot init_boot vendor_boot dtbo vbmeta recovery$SLOT"
            printf "要备份的分区（空格分隔）: "
            read -r ps
            # shellcheck disable=SC2086
            sh "$NF/nf_backup.sh" $ps
            ;;
        3)
            printf "要还原的 img 路径（空格分隔）: "
            read -r fs
            # shellcheck disable=SC2086
            sh "$NF/nf_restore.sh" $fs
            ;;
        4)
            sh "$NF/nf_edl.sh"
            ;;
        5)
            sh "$NF/nf_magisk_off.sh"
            ;;
        6)
            sh "$NF/nf_magisk_install.sh"
            ;;
        q|Q) exit 0 ;;
        *) echo "无效选项" ;;
    esac
done
