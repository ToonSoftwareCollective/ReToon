#!/bin/sh
# ReToon setup, run on the original Toon software (Toon 2 and Toon 1).
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
# What "in place" means on a Toon 2:
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
# On a Toon 1 (raw NAND, original kernel in the "kernel" partition):
#   kernel           uImage-toon1-flash, ReToon's kernel with its start-up
#                    built in; the original kernel moves to "kernel-backup"
#                    first (and a copy to toon-os/vendor-uImage)
#   /mnt/data        toon-os/rootfs.squashfs (+ a copy of the kernel), WiFi
#                    and thermostat settings as on the Toon 2
#   U-Boot settings  untouched on a Toon that never ran ReToon: its own
#                    "run boot_nand" starts the kernel partition. Once ReToon
#                    has run they can be written from here too, and the start
#                    command is set to ReToon's (see toon-boot in ReToon).
# Which files make up ReToon comes with the image: files-toon2.sha256
# (files-toon1.sha256 on a Toon 1) in the newest release of ReToon-images,
# or files.sha256 inside an archive placed here by hand. Files that are
# already there with the right checksum are kept; the others are taken from
# the image archive: retoon-toon2.tar.gz (retoon-toon1.tar.gz on a Toon 1).
# That archive is downloaded from the address in "images.url" next to this
# script (a release of ReToon-images) and unpacked while it comes in, so it
# is never stored whole (a Toon 1 has little room); an archive placed next
# to this script by hand is used instead. Without either, the files are fetched one by one from the address
# in "source.url", if there is one.

APP=$(cd "$(dirname "$0")" && pwd)
STATUS=/tmp/retoon.status
LOG=/var/log/retoon.log
OS=/mnt/data/toon-os
P3=/tmp/retoon-p3
P1=/tmp/retoon-p1
VENDOR_WIFI=/etc/network/wpa_supplicant.wlan0.conf
VENDOR_THERMOSTAT=/qmf/config/config_happ_thermstat.xml
VENDOR_ZWAVE_KEYS=/qmf/var/hdrv_zwave/s2keystore.xml
ARCHIVE=$APP/retoon-toon2.tar.gz
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
	# a downloaded archive or half-unpacked files: 10 MB and more
	rm -rf "$OS/download"
	status error 0 "$1"
	exit 1
}

# Where a file belongs, and where a checked copy of it is now ("" = nowhere).
home_of() {
	case "$1" in
	rootfs.squashfs|boot.scr|uImage-toon1-flash) echo "$OS/$1" ;;
	*) echo "$P3/$1" ;;
	esac
}
sum_of() { sed -n "s/^\([0-9a-f]\{64\}\)  $1\$/\1/p" "$SUMS"; }
good() {	# path, name
	[ -f "$1" ] && [ "$(sha256sum "$1" | cut -d ' ' -f 1)" = "$(sum_of "$2")" ]
}
# Which Toon: the Toon 2 has a device tree, the Toon 1's kernel is too old
# for one. The app says which one it is on too (isNxt); both must agree.
if grep -q 'i.MX6 SoloX' /proc/device-tree/model 2>/dev/null; then
	BOARD=toon2
elif grep -q 'ED2.0' /proc/cpuinfo 2>/dev/null; then
	BOARD=toon1
else
	fail "ReToon does not know this Toon."
fi
asked=$(cat /tmp/retoon.board 2>/dev/null)
[ -z "$asked" ] || [ "$asked" = $BOARD ] || fail "The app and this script do not agree on which Toon this is."
[ $BOARD = toon1 ] && ARCHIVE=$APP/retoon-toon1.tar.gz
# Which files the image has, with their checksums: from an archive placed
# next to this script (its own files.sha256), or else from the newest
# release of ReToon-images (files-toon2.sha256 / files-toon1.sha256 next to
# the archives there). So a new image needs no new app.
images=$(head -n 1 "$APP/images.url" 2>/dev/null | tr -d '\r\n')
SUMS=/tmp/retoon-files.sha256
rm -f $SUMS
if [ -s "$ARCHIVE" ]; then
	inner=$(tar -tzf "$ARCHIVE" 2>> $LOG | grep '/files.sha256$' | head -n 1)
	[ -n "$inner" ] && tar -xzOf "$ARCHIVE" "$inner" > $SUMS 2>> $LOG
elif [ -n "$images" ]; then
	curl -fsSL --connect-timeout 20 --retry 2 -o $SUMS "${images%/}/files-$BOARD.sha256" >> $LOG 2>&1 ||
		fail "Cannot reach the ReToon images. Is the Toon connected to the internet?"
elif [ -s "$APP/files-$BOARD.sha256" ]; then
	cp "$APP/files-$BOARD.sha256" $SUMS	# with source.url, as older apps had
fi
# only plain file names: they become paths below
FILES=$(sed -n 's/^[0-9a-f]\{64\}  \([A-Za-z0-9._-]*\)$/\1/p' "$SUMS" 2>/dev/null)
[ -n "$FILES" ] || fail "Cannot find out which files ReToon needs (no images.url or archive)."

# --- Toon 1: the kernel partitions and the U-Boot settings ---
mtd_of() { sed -n "s/^\(mtd[0-9]*\): .* \"$1\"\$/\1/p" /proc/mtd; }
hexof() { hexdump -v -e '1/1 "%02x"'; }
# Reading a partition: like U-Boot's "nand read", a bad block is skipped and
# the next good one follows (plain reads of /dev/mtdN stop at a bad block
# with an I/O error). nanddump's output is cut to the length asked for.
# The reason of a failure ends up in $REASON (and the log).
# nanddump changed its mind about "-o": the old one (the original software)
# includes the spare bytes of every page unless -o is given, the new one
# (ReToon) leaves them out unless -o is given. Find out once from the size
# of one block.
nd_opts() {
	[ -n "$ND_OPTS" ] && return
	nanddump -l 0x20000 -f /tmp/retoon-nd /dev/$1 > /dev/null 2>&1
	case "$(wc -c < /tmp/retoon-nd 2>/dev/null)" in
	131072) ND_OPTS="--bb=skipbad" ;;
	*) ND_OPTS="-o --bb=skipbad" ;;
	esac
	rm -f /tmp/retoon-nd
}
flash_read() {	# mtd, bytes, file
	REASON=""
	nd_opts $1
	# one block more than the data needs, for a skipped bad block, within
	# the partition
	blocks=$(( ($2 + 131071) / 131072 + 1 ))
	have=$(( 0x$(sed -n "s/^$1: \([0-9a-f]*\) .*/\1/p" /proc/mtd) / 131072 ))
	[ $blocks -le $have ] || blocks=$have
	if nanddump $ND_OPTS -l $(( blocks * 131072 )) -f /tmp/retoon-read /dev/$1 2> /tmp/retoon-read.err; then
		:
	else
		# an older nanddump without --bb: hope for no bad block
		nanddump ${ND_OPTS%--bb=skipbad} -l $(( blocks * 131072 )) -f /tmp/retoon-read /dev/$1 2> /tmp/retoon-read.err ||
		dd if=/dev/$1 of=/tmp/retoon-read bs=131072 count=$blocks 2> /tmp/retoon-read.err
	fi
	dd if=/tmp/retoon-read of=$3 bs=$2 count=1 2>> /tmp/retoon-read.err
	rm -f /tmp/retoon-read
	if [ "$(wc -c < $3 2>/dev/null)" = $2 ]; then rm -f /tmp/retoon-read.err; return 0; fi
	REASON=$(grep -v '^$' /tmp/retoon-read.err | tail -n 1 | tr -d '"')
	log "flash_read $1 $2: $REASON (got $(wc -c < $3 2>/dev/null) bytes)"
	rm -f /tmp/retoon-read.err
	return 1
}
# name in a partition's uImage header ("" = no uImage there)
image_name() {
	flash_read $1 64 /tmp/retoon-hdr || return
	[ "$(dd if=/tmp/retoon-hdr bs=4 count=1 2>/dev/null | hexof)" = 27051956 ] || return
	dd if=/tmp/retoon-hdr bs=1 skip=32 count=32 2>/dev/null | tr -d '\000'
}
# the whole uImage in a partition (header + data) to a file
image_copy() {	# mtd, file
	flash_read $1 64 /tmp/retoon-hdr || return
	len=$(( 0x$(dd if=/tmp/retoon-hdr bs=1 skip=12 count=4 2>/dev/null | hexof) + 64 ))
	[ $len -gt 64 ] && [ $len -le 3145728 ] || { REASON="odd size in the kernel header"; return 1; }
	flash_read $1 $len $2
}
# is this file what the partition holds?
flash_has() {	# mtd, file
	size=$(wc -c < $2)
	flash_read $1 $size /tmp/retoon-flash || { rm -f /tmp/retoon-flash; return 1; }
	[ "$(sha256sum < /tmp/retoon-flash | cut -d ' ' -f 1)" = "$(sha256sum < $2 | cut -d ' ' -f 1)" ]
	ok=$?
	rm -f /tmp/retoon-flash
	return $ok
}
# The original software's flash_erase takes "0 0" as no blocks at all:
# flash_eraseall erases the whole partition (and skips bad blocks).
flash_write() {	# mtd, file
	flash_eraseall -q /dev/$1 >> $LOG 2>&1 && nandwrite -p /dev/$1 $2 >> $LOG 2>&1 && flash_has $1 $2
}
# U-Boot settings: one copy of 128 KiB (4-byte CRC32, then name=value\0...).
# busybox has no crc32, but gzip ends its output with the CRC32 of its input.
env_read() {	# file for the name=value lines
	nanddump -o -l 0x20000 -f /tmp/retoon-env.bin /dev/$ENV_MTD >> $LOG 2>&1 || return 1
	dd if=/tmp/retoon-env.bin of=/tmp/retoon-env.body bs=4 skip=1 2>/dev/null
	dd if=/tmp/retoon-env.bin of=/tmp/retoon-env.crc bs=4 count=1 2>/dev/null
	[ "$(gzip -c /tmp/retoon-env.body | tail -c 8 | dd bs=4 count=1 2>/dev/null | hexof)" = \
	  "$(hexof < /tmp/retoon-env.crc)" ] || return 1
	tr '\000' '\n' < /tmp/retoon-env.body | awk '$0 == "" { exit } { print }' > $1
}
env_write() {	# file with the name=value lines
	{ tr '\n' '\000' < $1; printf '\000'; } > /tmp/retoon-env.data
	n=$(wc -c < /tmp/retoon-env.data)
	[ $n -gt 1 ] && [ $n -le 131068 ] || return 1
	# padded with zeros by appending: the original software's busybox dd
	# has no conv=notrunc (it would fail and leave only zeros)
	{ cat /tmp/retoon-env.data; dd if=/dev/zero bs=$((131068 - n)) count=1 2>/dev/null; } > /tmp/retoon-env.pad
	[ "$(wc -c < /tmp/retoon-env.pad)" = 131068 ] || return 1
	[ "$(dd if=/tmp/retoon-env.pad bs=$n count=1 2>/dev/null | md5sum)" = "$(md5sum < /tmp/retoon-env.data)" ] || return 1
	gzip -c /tmp/retoon-env.pad | tail -c 8 | dd bs=4 count=1 2>/dev/null > /tmp/retoon-env.crc
	cat /tmp/retoon-env.crc /tmp/retoon-env.pad > /tmp/retoon-env.new
	[ "$(wc -c < /tmp/retoon-env.new)" = 131072 ] || return 1
	flash_write $ENV_MTD /tmp/retoon-env.new
}
env_writable() { ! grep -q '(u-boot-env)ro' /proc/cmdline; }
RETOON_BOOTCMD='setenv bootcmd run boot_nand_backup; saveenv; run boot_retoon'
RETOON_BOOT='nand read 0xa2000000 0x300000 0x300000; bootm 0xa2000000'

if [ $BOARD = toon2 ]; then
	mount | grep -q ' /mnt/data ' || fail "The data partition is not there."
	mkdir -p $P3 $P1
	mount -o ro /dev/mmcblk3p3 $P3 2>/dev/null || fail "The third partition cannot be read."
else
	[ -d /mnt/data ] || fail "The data folder is not there."
	KERNEL_MTD=$(mtd_of kernel); BACKUP_MTD=$(mtd_of kernel-backup); ENV_MTD=$(mtd_of u-boot-env)
	[ -n "$KERNEL_MTD" ] && [ -n "$BACKUP_MTD" ] && [ -n "$ENV_MTD" ] ||
		fail "The flash partitions of this Toon are not as expected."
fi

missing=""
for f in $FILES; do
	good "$(home_of $f)" $f || missing="$missing $f"
done
# on a Toon 1 the kernel must also be in its partition
kernel_in_place=1
if [ $BOARD = toon1 ]; then
	good "$OS/uImage-toon1-flash" uImage-toon1-flash && flash_has $KERNEL_MTD "$OS/uImage-toon1-flash" ||
		kernel_in_place=0
fi

if [ "$ACTION" = check ]; then
	cleanup
	if [ -z "$missing" ] && [ $kernel_in_place = 1 ]; then
		status ready 0 "ReToon is on this Toon. Press the button to start it."
	elif [ -s "$ARCHIVE" ] || [ -s "$APP/images.url" ] || [ -s "$APP/source.url" ]; then
		n=$(echo $missing | wc -w)
		[ $n = 0 ] && n=1	# only the kernel partition
		[ $n = 1 ] && what="1 file" || what="$n files"
		status needed 0 "ReToon is not on this Toon yet ($what to put in place). Press the button to install and start it."
	else
		status error 0 "ReToon is not on this Toon yet and the app has no download address (images.url)."
	fi
	exit 0
fi
[ "$ACTION" = install ] || fail "Unknown request: $ACTION"

# 1. get what is missing: out of the image archive (downloaded from the
#    address in images.url, or placed next to this script), or, without
#    either, file by file from source.url
if [ -n "$missing" ]; then
	url=$(head -n 1 "$APP/source.url" 2>/dev/null | tr -d '\r\n')
	[ -s "$ARCHIVE" ] || [ -n "$images" ] || [ -n "$url" ] ||
		fail "Files are missing and the app has no download address (images.url)."
	free=$(df -k /mnt/data | tail -n 1 | awk '{print $4}')
	need=60000; [ $BOARD = toon1 ] && need=15000	# kB: what gets unpacked
	[ "$free" -gt $need ] || fail "Not enough room on the data partition."
	mkdir -p $OS/download
	again="Install the app again."
	if [ ! -s "$ARCHIVE" ] && [ -n "$images" ]; then
		# straight from the download into the files: the archive itself is
		# never stored; every file is checked against its checksum below
		status working 1 "Downloading ReToon"
		mkdir -p $OS/download/unpack
		curl -fsSL --connect-timeout 20 --retry 3 "${images%/}/$(basename "$ARCHIVE")" 2>> $LOG |
			tar -xzf - -C $OS/download/unpack 2>> $LOG
		for f in $missing; do
			got=$(ls $OS/download/unpack/*/$f 2>/dev/null | head -n 1)
			[ -n "$got" ] && mv "$got" "$OS/download/$f"
			good "$OS/download/$f" $f ||
				fail "Could not download ReToon (or it arrived damaged). Is the Toon connected to the internet?"
		done
		rm -rf $OS/download/unpack
		ARCHIVE=""
	fi
	if [ -s "$ARCHIVE" ]; then
		# the files sit in one folder inside the archive
		top=$(tar -tzf "$ARCHIVE" 2>> $LOG | head -n 1 | cut -d / -f 1)
		[ -n "$top" ] || fail "The ReToon archive is damaged. $again"
	fi
	n=0
	for f in $missing; do
		n=$((n + 1))
		if [ -z "$ARCHIVE" ] && [ -n "$images" ]; then
			:	# downloaded and checked above
		elif [ -s "$ARCHIVE" ]; then
			status working 1 "Unpacking $f ($n of $(echo $missing | wc -w))"
			tar -xzOf "$ARCHIVE" "$top/$f" > "$OS/download/$f" 2>> $LOG ||
				fail "Could not unpack $f. $again"
			good "$OS/download/$f" $f || fail "$f in the ReToon archive is damaged. $again"
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

# 3. kernel and start-up files: on the third partition (Toon 2), in the
#    kernel partition (Toon 1)
status working 3 "Putting the start-up files in place"
if [ $BOARD = toon1 ]; then
	# The original kernel stays: before ReToon's goes into "kernel", the
	# original one must be safe in "kernel-backup".
	in_kernel=$(image_name $KERNEL_MTD)
	case "$in_kernel" in
	toon1-retoon*) ;;
	Linux-*)
		status working 3 "Keeping the original kernel"
		# read it into memory first: the data partition may be nearly
		# full, and a copy there is only a convenience for later checks
		image_copy $KERNEL_MTD /tmp/vendor-uImage ||
			fail "Cannot read the original kernel${REASON:+ ($REASON)}. Nothing was changed."
		if ! flash_has $BACKUP_MTD /tmp/vendor-uImage; then
			flash_write $BACKUP_MTD /tmp/vendor-uImage ||
				fail "Cannot keep the original kernel${REASON:+ ($REASON)}. Nothing was changed in the kernel partition."
		fi
		rm -f $OS/vendor-uImage.new
		cp /tmp/vendor-uImage $OS/vendor-uImage.new 2>> $LOG && mv $OS/vendor-uImage.new $OS/vendor-uImage ||
			{ rm -f $OS/vendor-uImage.new; log "no room for a copy of the original kernel on the data partition (it is in kernel-backup)"; }
		rm -f /tmp/vendor-uImage ;;
	*)
		# an earlier attempt that stopped while writing ReToon's kernel:
		# the original one is already safe in kernel-backup
		case "$(image_name $BACKUP_MTD)" in Linux-*) ;; *)
			fail "The kernel partition holds something unknown (${in_kernel:-no kernel})." ;; esac
		log "kernel partition: unfinished earlier write, the original kernel is in kernel-backup" ;;
	esac
	case "$(image_name $BACKUP_MTD)" in
	Linux-*) ;;
	*) fail "The original kernel is not in its place (kernel-backup); nothing was changed." ;;
	esac
	if ! flash_has $KERNEL_MTD $OS/uImage-toon1-flash; then
		status working 3 "Writing the ReToon kernel"
		flash_write $KERNEL_MTD $OS/uImage-toon1-flash ||
			fail "Writing the ReToon kernel failed${REASON:+ ($REASON)}. Do not restart the Toon: press the button again."
	fi
fi
need_p3=""
for f in $missing; do
	case "$(home_of $f)" in $P3/*) need_p3="$need_p3 $f" ;; esac
done
if [ $BOARD = toon2 ] && [ -n "$need_p3" ]; then
	mount -o remount,rw $P3 || fail "The third partition cannot be written."
	for f in $need_p3; do
		cp "$OS/download/$f" "$P3/$f.new" && sync && mv "$P3/$f.new" "$P3/$f" ||
			fail "Cannot write $f to the third partition."
	done
	sync
fi
[ $BOARD = toon2 ] && umount $P3
rm -rf $OS/download

# 4. WiFi: ReToon uses the network this Toon is on now
status working 4 "Taking over the WiFi settings"
if [ ! -s $OS/config/wpa_supplicant.conf ]; then
	if [ ! -s $VENDOR_WIFI ] && [ $BOARD = toon1 ]; then
		log "no WiFi settings to take over; ReToon uses the ethernet port"
	else
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
fi
# the Z-Wave network keys of the original software (S0 and S2), for Z-Wave
# JS: the network itself lives in the Z-Wave chip, the keys do not
if [ ! -s $OS/config/zwave-keys.xml ] && [ -s $VENDOR_ZWAVE_KEYS ]; then
	status working 4 "Taking over the Z-Wave network keys"
	cp $VENDOR_ZWAVE_KEYS $OS/config/zwave-keys.xml.new && mv $OS/config/zwave-keys.xml.new $OS/config/zwave-keys.xml
	chmod 600 $OS/config/zwave-keys.xml 2>/dev/null
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
# 5. the radio chip's firmware, as this Toon has it (Toon 2; the Toon 1's
#    WiFi stick needs none from here)
if [ $BOARD = toon2 ]; then
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
fi

# asking for ReToon here also means: keep starting it
rm -f $OS/config/no-autoboot
sync

# 6. the boot script (Toon 2) or the U-Boot start command (Toon 1): the next
#    start goes to ReToon
status working 6 "Preparing the restart"
if [ $BOARD = toon1 ]; then
	env_read /tmp/retoon-env.txt || fail "Cannot read the U-Boot settings."
	cmd=$(sed -n 's/^bootcmd=//p' /tmp/retoon-env.txt)
	if env_writable; then
		# ReToon ran here before: its start command, one-shot as ReToon
		# expects (it sets it back once it is up)
		if [ "$cmd" != "$RETOON_BOOTCMD" ] || ! grep -q '^boot_retoon=' /tmp/retoon-env.txt; then
			grep -v '^bootcmd=\|^boot_retoon=' /tmp/retoon-env.txt > /tmp/retoon-env.set
			echo "boot_retoon=$RETOON_BOOT" >> /tmp/retoon-env.set
			echo "bootcmd=$RETOON_BOOTCMD" >> /tmp/retoon-env.set
			env_write /tmp/retoon-env.set || fail "Cannot write the U-Boot settings."
		fi
	else
		# never ran ReToon: U-Boot's own command starts the kernel partition,
		# which now holds ReToon
		[ "$cmd" = "run boot_nand" ] ||
			fail "This Toon starts in an unknown way (bootcmd=$cmd); nothing more was changed."
	fi
	rm -f /tmp/retoon-env.*
else
good $OS/boot.scr boot.scr || fail "The boot script is damaged."
mount -t vfat /dev/mmcblk3p1 $P1 || fail "The boot partition cannot be written."
cp $OS/boot.scr $P1/boot.new && sync && mv $P1/boot.new $P1/boot.scr || fail "Cannot write the boot script."
sync
umount $P1
fi

# 7. restart
if [ -n "$RETOON_NO_REBOOT" ]; then
	status ready $STEPS "Everything is in place. (Test run: no restart.)"
	exit 0
fi
status restarting $STEPS "Restarting into ReToon..."
sleep 5
/sbin/reboot
