#!/bin/sh
# Prépare le système de fichiers commun à tous les niveaux : l'image
# sysinfo-api (Alpine + Node + systeminformation) avec la sonde dans /app.
# Usage : ./preparer-rootfs.sh
set -eu

IMAGE=crazzybuilds/sysinfo-api:0.0.2
ROOTFS=build/rootfs

ID=$(docker create "$IMAGE")
trap 'docker rm "$ID" >/dev/null' EXIT

[ -d "$ROOTFS" ] && chmod -R u+rwx "$ROOTFS"
rm -rf "$ROOTFS" && mkdir -p "$ROOTFS"
docker export "$ID" | tar -x -C "$ROOTFS" --no-same-owner --exclude='dev/*'
cp sonde/sonde.js "$ROOTFS/app/sonde.js"

echo "$ROOTFS prêt ($(du -sh "$ROOTFS" | cut -f1))"
