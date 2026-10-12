# ReToon setup app for the original Toon 2 software

An app for a rooted Toon 2 running the original software with the
ToonSoftwareCollective `tsc` helper. It puts ReToon in place next to the
original software and restarts the Toon into it. ReToon turns a Toon 2 into
an open wall panel and thermostat that works with Home Assistant.

Nothing of the original software is removed; from the ReToon web interface
(Settings, System, Starting up) you can go back to it.

## Files

- `RetoonApp.qml`, `RetoonTile.qml`, `RetoonScreen.qml`: a tile and one screen
  with a status line and a button.
- `retoon.sh`: does the work. The app writes `check` or `install` to
  `/tmp/retoon.request` and `external-retoon` to `/tmp/tsc.command`; the
  helper then runs this script as root. Progress is in `/tmp/retoon.status`
  (JSON) and `/var/log/retoon.log`.
- `files.sha256`: the five files that make up ReToon (kernel, device tree,
  initrd, system image, boot script), with checksums. Files already on the
  Toon with the right checksum are kept.
- `source.url` (not included yet): one line with the address the missing
  files are fetched from, as `<address>/<file name>`. Without it the app can
  only start a ReToon that is already on the Toon.

## What the button does

1. Fetches the files that are missing and checks them.
2. Puts the system image on the data partition (`/mnt/data/toon-os/`).
3. Puts kernel, device tree and initrd on the third partition, next to the
   recovery files.
4. Takes over the WiFi settings of the Toon.
5. Copies the firmware of the WiFi and Bluetooth chip from the original
   software to the data partition (ReToon images do not contain it).
6. Writes `boot.scr` to the first partition.
7. Restarts the Toon.

## Installing by hand

Copy these files to `/qmf/qml/apps/retoon` and restart the screen program.
`retoon.sh check` and `RETOON_NO_REBOOT=1 retoon.sh install` can also be run
from a shell.

## Status

Tested on two Toon 2 units: all steps including the restart into ReToon with
WiFi and Bluetooth working, started from the button on the screen. The ReToon
images are not published yet, so there is no download address.
