#!/system/bin/sh
# NX809J (S3910V) touch bring-up for TWRP recovery.
#
# Measured boot timeline (dmesg):
#   0.48s  first-stage init modprobes /lib/modules/zte_tpd.ko
#   0.99s  syna_dev_probe -> "Fail to find hardware configuration", -22, no node
#   1.28s  dsi_display_bind: panel qcom,mdss_dsi_bf375_rm692h5_6p8_magic_dsc_cmd
#
# The touch driver loses a ~0.3s race against the DSI panel bind: it is loaded
# before the display exists and never retries by itself. Removing and
# re-inserting it once the panel is up makes syna_dev_probe succeed and creates
# synaptics_tcm_touch -> eventN.
#
# Started from "on boot" before init.rc runs "class_start default", so
# /system/bin/recovery starts with touch already present and decrypts /data in
# a single pass. Recovery must never be restarted afterwards: a respawned
# instance inherits twrp.decrypt.done / ro.crypto.fs_crypto_blkdev and skips
# the FBE unlock, which leaves /data showing encrypted file names.

LOG=/tmp/tpd_boot.log
K=/lib/modules/zte_tpd.ko

echo "===================== tpd_boot =====================" >> $LOG 2>&1
echo "[tpd_boot] start uptime: $(cat /proc/uptime)" >> $LOG 2>&1

if [ -f "$K" ]; then
    echo "[tpd_boot] ko present: $K" >> $LOG 2>&1
else
    echo "[tpd_boot] ERROR: ko missing at $K" >> $LOG 2>&1
    ls /lib/modules >> $LOG 2>&1
fi

# --- touch bring-up -------------------------------------------------------
attempt=1
while [ "$attempt" -le 3 ]; do
    if grep -q synaptics_tcm_touch /proc/bus/input/devices; then
        echo "[tpd_boot] touch node already present" >> $LOG 2>&1
        break
    fi
    echo "[tpd_boot] attempt $attempt: rmmod + insmod at $(cat /proc/uptime)" >> $LOG 2>&1
    rmmod zte_tpd >> $LOG 2>&1
    insmod "$K" >> $LOG 2>&1
    # touchfix22: was "sleep 3". The probe creates the node within a few tens
    # of ms, so the fixed 3 s nap made init.rc's "wait /tmp/.tpd_ready" hold
    # back class_start default (and therefore /system/bin/recovery) for
    # 3.06 s on every boot -- measured as the only meaningful gap in the
    # ro.boottime timeline. Poll instead: same 3 s worst case, no dead time.
    i=0
    while [ "$i" -lt 30 ]; do
        if grep -q synaptics_tcm_touch /proc/bus/input/devices; then
            echo "[tpd_boot] node up after $i x 100ms" >> $LOG 2>&1
            break 2
        fi
        sleep 0.1
        i=$((i + 1))
    done
    attempt=$((attempt + 1))
done

if grep -q synaptics_tcm_touch /proc/bus/input/devices; then
    echo "[tpd_boot] RESULT ok at $(cat /proc/uptime)" >> $LOG 2>&1
    grep -A2 synaptics_tcm_touch /proc/bus/input/devices >> $LOG 2>&1
else
    echo "[tpd_boot] RESULT fail at $(cat /proc/uptime), input devices now:" >> $LOG 2>&1
    grep "Name=" /proc/bus/input/devices >> $LOG 2>&1
fi

echo ready > /tmp/.tpd_ready
echo "[tpd_boot] marker /tmp/.tpd_ready written at $(cat /proc/uptime)" >> $LOG 2>&1

# --- nf5: real vendor, in the background --------------------------------
# vendor_a is a logical partition created by TWRP's libfs_mgr, so it only
# exists once /system/bin/recovery is running - which is exactly what the
# marker above just released. Poll for up to 60 s and never block init.
i=0
while [ "$i" -lt 600 ]; do
    [ -e /dev/block/mapper/vendor_a ] && break
    sleep 0.1
    i=$((i + 1))
done
# --- nf8: own the /vendor mount, then let init start gatekeeper ---------
# TWRP mounts the real vendor for a few seconds to read properties, then
# unmounts it and kills every process that held it (that is how nf7's
# gatekeeper died with SIGKILL and could not be restarted). Wait for that
# unmount to happen, then mount the partition ourselves - this mount is ours
# and stays - and only then trigger init via vendor.gk.go.
GK=/vendor/bin/hw/android.hardware.gatekeeper-rust-service-qti

i=0
while [ "$i" -lt 600 ]; do
    [ -e "$GK" ] && break
    sleep 0.1
    i=$((i + 1))
done
echo "[tpd_boot] real vendor visible after $i x 100ms at $(cat /proc/uptime)" >> $LOG 2>&1

i=0
while [ "$i" -lt 1200 ]; do
    [ -e "$GK" ] || break
    sleep 0.1
    i=$((i + 1))
done
echo "[tpd_boot] TWRP unmounted vendor after $i x 100ms at $(cat /proc/uptime)" >> $LOG 2>&1

if [ ! -e "$GK" ]; then
    mount -t erofs -o ro /dev/block/mapper/vendor_a /vendor >> $LOG 2>&1
    echo "[tpd_boot] own mount rc=$?" >> $LOG 2>&1
fi
ls -l "$GK" >> $LOG 2>&1
# --- nf9: bring up the minkipcbinder daemon first ---------------------
# OneKeyMint's gatekeeper channel talks to the TA through this AIDL
# intermediary (vendor.qti.hardware.minkipcbinder.IMinkServer/default).
# It is disabled|oneshot in the real vendor and only appears once the
# vendor mount is ours, so init starts it from this property trigger.
# --- nf10: the mink gateway daemon, before the binder front end ------
# vendor.minkdaemon owns /dev/socket/ssgtzd + hlos_mink_opener; without
# them minkipcbinder dies with SockAgnostic_connect errno 2 (nf9).
# --- nf13: the mounts Android always has up before any TEE HAL starts -----
for d in /mnt/vendor/spunvm /mnt/vendor/qmcs /mnt/vendor/persist; do
    mkdir -p $d
done
mountpoint -q /mnt/vendor/spunvm 2>/dev/null ||     mount -t vfat -o rw /dev/block/by-name/spunvm /mnt/vendor/spunvm >> $LOG 2>&1
mountpoint -q /mnt/vendor/qmcs 2>/dev/null ||     mount -t vfat -o rw /dev/block/by-name/qmcs /mnt/vendor/qmcs >> $LOG 2>&1
mountpoint -q /mnt/vendor/persist 2>/dev/null ||     mount -t ext4 -o rw /dev/block/by-name/persist /mnt/vendor/persist >> $LOG 2>&1
for d in /mnt/vendor/spunvm /mnt/vendor/qmcs /mnt/vendor/persist; do
    if mountpoint -q $d 2>/dev/null; then st=ok; else st=FAIL; fi
    echo "[tpd_boot] mount $d -> $st at $(cat /proc/uptime)" >> $LOG 2>&1
done
setprop vendor.minkdaemon.go 1
echo "[tpd_boot] vendor.minkdaemon.go=1 sent at $(cat /proc/uptime)" >> $LOG 2>&1
i=0
while [ "$i" -lt 20 ]; do
    [ -S /dev/socket/ssgtzd ] && [ -S /dev/socket/hlos_mink_opener ] && break
    sleep 0.1
    i=$((i + 1))
done
ls -l /dev/socket/ssgtzd /dev/socket/hlos_mink_opener >> $LOG 2>&1
echo "[tpd_boot] mink sockets after $i x 100ms at $(cat /proc/uptime)" >> $LOG 2>&1

setprop vendor.mink.go 1
echo "[tpd_boot] vendor.mink.go=1 sent at $(cat /proc/uptime)" >> $LOG 2>&1
# give init + servicemanager a moment to register IMinkServer before
# gatekeeper opens its channel
sleep 1

setprop vendor.gk.go 1
# --- nf12: post-boot steps that used to be done by hand over adb ---------
i=0
while [ "$i" -lt 100 ]; do
    logcat -d -t 300 2>/dev/null | grep -q 'Successfully registered Gatekeeper HAL services' && break
    sleep 0.1
    i=$((i + 1))
done
echo "[tpd_boot] gatekeeper registered after $i x 100ms at $(cat /proc/uptime)" >> $LOG 2>&1
for s in vendor.keymint-qti vendor.weaver-service gto_secure_element_aidl_service; do
    setprop ctl.stop "$s" >/dev/null 2>&1
done
setprop ctl.stop keystore2 >/dev/null 2>&1
sleep 1
setprop ctl.start keystore2 >/dev/null 2>&1
sleep 2
echo "[tpd_boot] keystore2=$(getprop init.svc.keystore2) gatekeeper=$(getprop init.svc.vendor.gatekeeper_default)" >> $LOG 2>&1
echo "[tpd_boot] vendor.gk.go=1 sent at $(cat /proc/uptime)" >> $LOG 2>&1

# watchdog: TWRP may unmount again later (mount menu, zip install, ...). Keep
# the mount alive so a killed gatekeeper can always be restarted.
n=0
while [ "$n" -lt 3000 ]; do
    if [ ! -e "$GK" ]; then
        mount -t erofs -o ro /dev/block/mapper/vendor_a /vendor >> $LOG 2>&1
        echo "[tpd_boot] watchdog remount at $(cat /proc/uptime)" >> $LOG 2>&1
        setprop vendor.minkdaemon.go 1
        setprop vendor.mink.go 1
        setprop vendor.gk.go 1
    fi
    sleep 2
    n=$((n + 1))
done
