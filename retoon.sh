#!/bin/sh
# ReToon setup, run on the original Toon 2 software.
#
# Started by the ReToon app through the "tsc" helper (which runs
# <app>.sh of an app as root when the app writes "external-<app>" to
# /tmp/tsc.command), or by hand:
#
#   retoon.sh check      say what is there and what is missing
#   retoon.sh install    put everything in place and restart into ReToon
#
# Without an argument it does what /tmp/retoon.request asks for.
# Progress goes to /tmp/retoon.status (JSON, read by the app) and to
# /var/log/retoon.log. Set RETOON_NO_REBOOT=1 to stop before the restart.
#
# What "in place" means:
#   p3 (ext3)        toon2-zImage, toon2.dtb, toon2-initrd.cpio.gz.u-boot
#   p4 /mnt/data     toon-os/rootfs.squashfs, toon-os/boot.scr,
#                    toon-os/config/wpa_supplicant.conf (taken over from this
#                    system, so WiFi works at once),
#                    toon-os/config/thermostat.json (the preset temperatures
#                    and week program of this system, see thermostat.awk),
#                    toon-os/firmware/brcm/: the WiFi and Bluetooth chip's
#                    firmware, copied from this system (so a ReToon image
#                    does not have to contain it)
#   p1 (vfat)        boot.scr - what makes the next start go to ReToon
# Files that are already there with the right checksum (files.sha256 next to
# this script) are kept; the others are taken from retoon.tar.gz next to this
# script. Without that archive they are fetched from the address in the file
# "source.url" next to this script, if there is one.

APP=$(cd "$(dirname "$0")" && pwd)
STATUS=/tmp/retoon.status
LOG=/var/log/retoon.log
OS=/mnt/data/toon-os
P3=/tmp/retoon-p3
P1=/tmp/retoon-p1
VENDOR_WIFI=/etc/network/wpa_supplicant.wlan0.conf
VENDOR_THERMOSTAT=/qmf/config/config_happ_thermstat.xml
ARCHIVE=$APP/retoon.tar.gz
STEPS=7

ACTION=${1:-$(cat /tmp/retoon.request 2>/dev/null)}
rm -f /tmp/retoon.request
[ -n "$ACTION" ] || ACTION=check

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> $LOG; }

# One at a time. The app asks for a check whenever its screen is shown, and
# that can happen while an install is busy: a second run would unmount the
# partition the first one is writing to. A check that finds another run busy
# goes away quietly; an install waits for a check to finish.
LOCK=/tmp/retoon.lock
while ! mkdir $LOCK 2>/dev/null; do
	pid=$(cat $LOCK/pid 2>/dev/null)
	if [ -z "$pid" ] || ! kill -0 "$pid" 2>/dev/null; then
		rm -rf $LOCK
		continue
	fi
	if [ "$ACTION" != install ] || [ "$(cat $LOCK/action 2>/dev/null)" != check ]; then
		log "$ACTION asked for while $(cat $LOCK/action 2>/dev/null) is busy: left out"
		exit 0
	fi
	sleep 1
done
echo $$ > $LOCK/pid
echo "$ACTION" > $LOCK/action
trap 'rm -rf $LOCK' EXIT
status() {	# state, step, text
	log "$1: $3"
	printf '{"state":"%s","step":%s,"steps":%s,"text":"%s"}\n' "$1" "$2" $STEPS "$3" > $STATUS.tmp
	mv $STATUS.tmp $STATUS
}
cleanup() {
	umount $P3 2>/dev/null
	umount $P1 2>/dev/null
}
fail() {
	cleanup
	status error 0 "$1"
	exit 1
}

# Where a file belongs, and where a checked copy of it is now ("" = nowhere).
home_of() {
	case "$1" in
	rootfs.squashfs|boot.scr) echo "$OS/$1" ;;
	*) echo "$P3/$1" ;;
	esac
}
sum_of() { sed -n "s/^\([0-9a-f]\{64\}\)  $1\$/\1/p" "$APP/files.sha256"; }
good() {	# path, name
	[ -f "$1" ] && [ "$(sha256sum "$1" | cut -d ' ' -f 1)" = "$(sum_of "$2")" ]
}
FILES=$(sed 's/^[0-9a-f]*  //' "$APP/files.sha256" 2>/dev/null)

grep -q 'i.MX6 SoloX' /proc/device-tree/model 2>/dev/null ||
	fail "This is not a Toon 2. ReToon only runs on a Toon 2."
[ -n "$FILES" ] || fail "The list of files (files.sha256) is missing from the app."
mount | grep -q ' /mnt/data ' || fail "The data partition is not there."
mkdir -p $P3 $P1
mount -o ro /dev/mmcblk3p3 $P3 2>/dev/null || fail "The third partition cannot be read."

missing=""
for f in $FILES; do
	good "$(home_of $f)" $f || missing="$missing $f"
done

if [ "$ACTION" = check ]; then
	cleanup
	if [ -z "$missing" ]; then
		status ready 0 "ReToon is on this Toon. Press the button to start it."
	elif [ -s "$ARCHIVE" ] || [ -s "$APP/source.url" ]; then
		n=$(echo $missing | wc -w)
		[ $n = 1 ] && what="1 file" || what="$n files"
		status needed 0 "ReToon is not on this Toon yet ($what to put in place). Press the button to install and start it."
	else
		status error 0 "ReToon is not on this Toon yet and the app has neither its archive (retoon.tar.gz) nor a download address."
	fi
	exit 0
fi
[ "$ACTION" = install ] || fail "Unknown request: $ACTION"

# 1. get what is missing: out of the archive that came with the app, or,
#    without one, from the download address
if [ -n "$missing" ]; then
	url=$(head -n 1 "$APP/source.url" 2>/dev/null | tr -d '\r\n')
	[ -s "$ARCHIVE" ] || [ -n "$url" ] ||
		fail "Files are missing and the app has neither its archive (retoon.tar.gz) nor a download address."
	free=$(df -k /mnt/data | tail -n 1 | awk '{print $4}')
	[ "$free" -gt 60000 ] || fail "Not enough room on the data partition."
	mkdir -p $OS/download
	if [ -s "$ARCHIVE" ]; then
		# the files sit in one folder inside the archive
		top=$(tar -tzf "$ARCHIVE" 2>> $LOG | head -n 1 | cut -d / -f 1)
		[ -n "$top" ] || fail "The archive of the app (retoon.tar.gz) is damaged. Install the app again."
	fi
	n=0
	for f in $missing; do
		n=$((n + 1))
		if [ -s "$ARCHIVE" ]; then
			status working 1 "Unpacking $f ($n of $(echo $missing | wc -w))"
			tar -xzOf "$ARCHIVE" "$top/$f" > "$OS/download/$f" 2>> $LOG ||
				fail "Could not unpack $f. Install the app again."
			good "$OS/download/$f" $f || fail "$f in the archive of the app is damaged. Install the app again."
		else
			status working 1 "Fetching $f ($n of $(echo $missing | wc -w))"
			curl -fsSL --connect-timeout 20 -o "$OS/download/$f" "${url%/}/$f" >> $LOG 2>&1 ||
				fail "Could not fetch $f. Is the Toon connected to the internet?"
			good "$OS/download/$f" $f || fail "$f arrived damaged. Try again."
		fi
	done
fi

# 2. the system itself, on the data partition
status working 2 "Putting the system in place"
mkdir -p $OS/config
chmod 700 $OS/config
for f in $missing; do
	case "$(home_of $f)" in
	$OS/*) mv "$OS/download/$f" "$OS/$f" || fail "Cannot write to the data partition." ;;
	esac
done

# 3. kernel and start-up files, on the third partition
status working 3 "Putting the start-up files in place"
need_p3=""
for f in $missing; do
	case "$(home_of $f)" in $P3/*) need_p3="$need_p3 $f" ;; esac
done
if [ -n "$need_p3" ]; then
	mount -o remount,rw $P3 || fail "The third partition cannot be written."
	for f in $need_p3; do
		cp "$OS/download/$f" "$P3/$f.new" && sync && mv "$P3/$f.new" "$P3/$f" ||
			fail "Cannot write $f to the third partition."
	done
	sync
fi
umount $P3
rm -rf $OS/download

# 4. WiFi: ReToon uses the network this Toon is on now
status working 4 "Taking over the WiFi settings"
if [ ! -s $OS/config/wpa_supplicant.conf ]; then
	[ -s $VENDOR_WIFI ] || fail "This Toon has no WiFi settings to take over. Connect it to WiFi first."
	# Only the networks and the country: ReToon's wpa_supplicant has no
	# control interface, and a ctrl_interface line makes it refuse the file.
	{
		grep -m 1 '^[ \t]*country=' $VENDOR_WIFI
		sed -n '/^[ \t]*network[ \t]*=[ \t]*{/,/^[ \t]*}/p' $VENDOR_WIFI
	} > $OS/config/wpa_supplicant.conf
	chmod 600 $OS/config/wpa_supplicant.conf
	grep -q 'ssid=' $OS/config/wpa_supplicant.conf ||
		fail "This Toon has no WiFi network set. Connect it to WiFi first."
fi
# the thermostat's preset temperatures and week program, as set here; a
# failure leaves ReToon's defaults (the heating itself stays off either way)
if [ ! -s $OS/config/thermostat.json ] && [ -s $VENDOR_THERMOSTAT ]; then
	status working 4 "Taking over the thermostat program"
	if awk -f $APP/thermostat.awk $VENDOR_THERMOSTAT > $OS/config/thermostat.json.new &&
	   grep -q '"presets"' $OS/config/thermostat.json.new; then
		mv $OS/config/thermostat.json.new $OS/config/thermostat.json
	else
		rm -f $OS/config/thermostat.json.new
		log "the thermostat program could not be read; ReToon starts with its defaults"
	fi
fi
# 5. the radio chip's firmware, as this Toon has it
status working 5 "Copying the WiFi and Bluetooth firmware"
FW=$OS/firmware/brcm
mkdir -p $FW
for f in brcmfmac43430-sdio.bin brcmfmac43430-sdio.clm_blob brcmfmac43430-sdio.txt; do
	if [ -s /lib/firmware/brcm/$f ]; then
		cp /lib/firmware/brcm/$f $FW/$f.new && mv $FW/$f.new $FW/$f || fail "Cannot write to the data partition."
	fi
done
hcd=$(ls /etc/firmware/BCM43430A1*.hcd /lib/firmware/brcm/BCM43430A1*.hcd 2>/dev/null | head -n 1)
[ -n "$hcd" ] && cp "$hcd" $FW/BCM43430A1.hcd
[ -s $FW/brcmfmac43430-sdio.bin ] && [ -s $FW/brcmfmac43430-sdio.txt ] ||
	log "no WiFi firmware found on this system; ReToon will use what its own image has"

# asking for ReToon here also means: keep starting it
rm -f $OS/config/no-autoboot
sync

# 6. the boot script: the next start goes to ReToon
status working 6 "Preparing the restart"
good $OS/boot.scr boot.scr || fail "The boot script is damaged."
mount -t vfat /dev/mmcblk3p1 $P1 || fail "The boot partition cannot be written."
cp $OS/boot.scr $P1/boot.new && sync && mv $P1/boot.new $P1/boot.scr || fail "Cannot write the boot script."
sync
umount $P1

# 7. restart
if [ -n "$RETOON_NO_REBOOT" ]; then
	status ready $STEPS "Everything is in place. (Test run: no restart.)"
	exit 0
fi
status restarting $STEPS "Restarting into ReToon..."
sleep 5
/sbin/reboot
