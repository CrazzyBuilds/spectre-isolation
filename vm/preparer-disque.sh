#!/bin/sh
# Construit le disque virtuel des VM à partir du rootfs commun : un fichier
# qui contient un système de fichiers ext4, comme un vrai disque.
# Usage : vm/preparer-disque.sh   (après ./preparer-rootfs.sh)
set -eu

ROOTFS=build/rootfs
DISQUE=build/disque.ext4

cp vm/init "$ROOTFS/init"
chmod 755 "$ROOTFS/init"
printf '127.0.0.1\tlocalhost vm\n' >"$ROOTFS/etc/hosts"

# mkfs.ext4 -d remplit le système de fichiers avec le contenu d'un dossier,
# sans avoir besoin de monter le disque (donc sans être root).
rm -f "$DISQUE"
mkfs.ext4 -q -F -L racine -d "$ROOTFS" "$DISQUE" 256M

echo "$DISQUE prêt ($(du -h --apparent-size "$DISQUE" | cut -f1), dont $(du -sh "$ROOTFS" | cut -f1) de fichiers)"
