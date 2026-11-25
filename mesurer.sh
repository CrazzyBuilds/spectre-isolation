#!/bin/sh
# Mesure un niveau du spectre :
#   - demarrageMs : temps médian pour lancer /bin/true (qui ne fait rien),
#     soit le coût pur de l'isolation, sans le travail du programme ;
#   - la sonde : ce que voit un programme à ce niveau.
# Usage : ./mesurer.sh <niveau> [répétitions]
set -eu

NIVEAU=${1:?usage : $0 <niveau> [répétitions]}
N=${2:-10}
ROOTFS=$(pwd)/build/rootfs
MINIBOX=${MINIBOX:-$HOME/Projects/minibox/minibox}
IMAGE=crazzybuilds/sysinfo-api:0.0.2

# lancer <commande...> : exécute la commande au niveau demandé.
lancer() {
	case "$NIVEAU" in
	processus)
		# Sur l'hôte, sans aucune isolation (avec le Node de l'hôte).
		(cd "$ROOTFS/app" && "$@") ;;
	minibox)
		# Namespaces + cgroups, sans root (piste 2).
		"$MINIBOX" run -rootfs "$ROOTFS" -workdir /app "$@" 2>/dev/null ;;
	docker)
		# runc, le runtime par défaut de Docker.
		docker run --rm -v "$ROOTFS/app/sonde.js:/app/sonde.js:ro" "$IMAGE" "$@" ;;
	qemu)
		# Une VM complète : BIOS, carte mère émulée (q35), son propre noyau.
		vm_qemu "$@" ;;
	*)
		echo "niveau inconnu : $NIVEAU" >&2
		exit 2 ;;
	esac
}

NOYAU=$(pwd)/build/noyau/vmlinux-6.1.155
DISQUE=$(pwd)/build/disque.ext4

# vm_qemu <commande...> : démarre la VM ; l'init du disque lance la sonde si
# on la demande (sonde=1), sinon s'éteint aussitôt. La console série est
# écrite dans un fichier, d'où on extrait la ligne de la sonde.
vm_qemu() {
	mode=0
	[ "$1" = node ] && mode=1
	console=$(pwd)/build/console-qemu.log
	qemu-system-x86_64 -M q35 -enable-kvm -cpu host -m 512 -smp 1 \
		-nodefaults -no-user-config -display none -no-reboot \
		-serial "file:$console" \
		-kernel "$NOYAU" \
		-append "console=ttyS0 quiet root=/dev/vda ro init=/init sonde=$mode" \
		-drive id=d,file="$DISQUE",format=raw,if=none,readonly=on \
		-device virtio-blk-pci,drive=d
	sed -n 's/^SONDE //p' "$console"
}

mediane() { tr ' ' '\n' | grep . | sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}'; }

TEMPS=""
for i in $(seq 1 "$N"); do
	debut=$(date +%s%N)
	lancer /bin/true >/dev/null
	TEMPS="$TEMPS $((($(date +%s%N) - debut) / 1000000))"
done

SONDE=$(lancer node sonde.js)
echo "$SONDE" | jq -c --arg n "$NIVEAU" --argjson t "$(echo "$TEMPS" | mediane)" \
	'{niveau: $n, demarrageMs: $t} + .'
