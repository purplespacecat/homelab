#!/bin/bash
# Mount the external media HDD (Jellyfin library) at /mnt/media.
#
# Host-level state Flux cannot own (fstab is Layer 1; k8s hostPath is Layer 2
# and only bind-mounts whatever the host has here). This script is the
# Git-tracked source of truth for that host state — same pattern as the
# out-of-band secrets: documented manual step, run once per host rebuild.
#
# The drive is the pre-existing NTFS Seagate Expansion (also holds backups —
# do NOT reformat). Jellyfin's hostPath points at /mnt/media/media so the pod
# never sees the backup folders.
#
# fstab reasoning (see docs / hdd-mount-guide note):
#   UUID=            device letters shift across boots; UUID is stable
#   nofail           drive unplugged must NOT drop a headless box into
#                    emergency mode at boot — boot proceeds, media absent
#   x-systemd.device-timeout=10  don't wait 90s for a device that isn't coming
#   noatime          no access-time writes; less HDD chatter/spin-ups
#   uid/gid/dmask/fmask  NTFS has no POSIX owners; expose as spacecrab (1000),
#                    world-readable (dirs 755 / files 644) for the pod
#
# ntfs3 honors NTFS security descriptors where they exist: a root-created dir
# stays root-owned and the uid= option loses. (The noacsrules override was
# removed from the kernel in ~6.2.) Hence media/ below is created AS the user.
#   last field 0     never fsck terabytes of USB media at boot
#   no x-systemd.automount  autofs triggers don't fire reliably through
#                    kubelet bind mounts — eager mount + nofail instead
#
# Idempotent: safe to re-run; skips the fstab append if the UUID is present.
# Must run as root ON the node (or via privileged pod + nsenter -t 1 -m -u -i -n).
set -euo pipefail

UUID="C820A0AA20A0A144"
MOUNTPOINT="/mnt/media"
FSTAB_LINE="UUID=${UUID}  ${MOUNTPOINT}  ntfs3  defaults,nofail,noatime,uid=1000,gid=1000,dmask=022,fmask=133,x-systemd.device-timeout=10  0  0"

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root" >&2; exit 1; }

if ! blkid -U "$UUID" >/dev/null 2>&1; then
  echo "ERROR: filesystem UUID $UUID not present — is the HDD plugged in?" >&2
  exit 1
fi

if grep -qF "$FSTAB_LINE" /etc/fstab; then
  echo "fstab entry already correct, leaving as-is."
else
  cp -n /etc/fstab "/etc/fstab.bak-$(date +%Y%m%d)"
  sed -i "\\#UUID=${UUID}#d" /etc/fstab   # drop any stale entry for this UUID
  echo "$FSTAB_LINE" >> /etc/fstab
  echo "fstab entry written (backup at /etc/fstab.bak-$(date +%Y%m%d))."
fi

mkdir -p "$MOUNTPOINT"
systemctl daemon-reload
# Remount if already mounted so changed fstab options actually take effect
if mountpoint -q "$MOUNTPOINT"; then umount "$MOUNTPOINT"; fi
mount -a   # mounts via the fstab entry — verifies boot will do the same

# Guard marker ON the drive, inside the dir Jellyfin hostPaths: the pod's
# initContainer checks /media/.mounted, so a missing drive (empty mountpoint)
# fails the pod loudly instead of the app marking the library deleted.
# Created AS the user (see header): the NTFS descriptor must be user-owned or
# media can't be copied in without sudo. Recreate if root-owned from earlier.
if [ -d "$MOUNTPOINT/media" ] && ! runuser -u spacecrab -- test -w "$MOUNTPOINT/media"; then
  rm -f "$MOUNTPOINT/media/.mounted"
  rmdir "$MOUNTPOINT/media"   # fails loudly if it unexpectedly holds data
fi
runuser -u spacecrab -- mkdir -p "$MOUNTPOINT/media"
runuser -u spacecrab -- touch "$MOUNTPOINT/media/.mounted"

echo
findmnt "$MOUNTPOINT"
df -h "$MOUNTPOINT"
# The whole point of uid=/noacsrules: the regular user must be able to copy
# media in without sudo. Fail here rather than at copy time.
runuser -u spacecrab -- sh -c "touch '$MOUNTPOINT/media/.writetest' && rm '$MOUNTPOINT/media/.writetest'" \
  && echo "user write check: OK" || { echo "ERROR: spacecrab cannot write to $MOUNTPOINT/media" >&2; exit 1; }
echo "OK: drop media under $MOUNTPOINT/media/ — Jellyfin hostPath is $MOUNTPOINT/media (read-only)."
