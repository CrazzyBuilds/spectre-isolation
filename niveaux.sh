# Les niveaux du spectre, du moins isolé au plus isolé. Fichier inclus par
# mesurer.sh et memoire.sh (". ./niveaux.sh"), pas un script à lancer seul.
#
# lancer <niveau> <commande...> exécute la commande à ce niveau. Pour les VM,
# la commande est traduite en mode de l'init (voir vm/init).

ROOTFS=$(pwd)/build/rootfs
NOYAU=$(pwd)/build/noyau/vmlinux-6.1.155
DISQUE=$(pwd)/build/disque.ext4
MINIBOX=${MINIBOX:-$HOME/Projects/minibox/minibox}
IMAGE=crazzybuilds/sysinfo-api:0.0.2

NIVEAUX="processus minibox docker qemu firecracker"

lancer() {
	niveau=$1
	shift
	case "$niveau" in
	processus)
		# Sur l'hôte, sans aucune isolation. Pour comparer à armes égales, on
		# prend le Node de l'image (v20, compilé pour musl) plutôt que celui de
		# l'hôte : on le lance avec le chargeur de bibliothèques musl du rootfs.
		if [ "$1" = node ]; then
			shift
			set -- "$ROOTFS/lib/ld-musl-x86_64.so.1" \
				--library-path "$ROOTFS/usr/lib:$ROOTFS/lib" "$ROOTFS/usr/bin/node" "$@"
		fi
		(cd "$ROOTFS/app" && exec "$@") ;;
	minibox)
		# Namespaces + cgroups, sans root (piste 2).
		"$MINIBOX" run -rootfs "$ROOTFS" -workdir /app "$@" 2>/dev/null ;;
	docker)
		# runc, le runtime par défaut de Docker.
		docker run --rm ${DOCKER_NOM:+--name "$DOCKER_NOM"} \
			-v "$ROOTFS/app/sonde.js:/app/sonde.js:ro" "$IMAGE" "$@" ;;
	qemu)
		# Une VM complète : BIOS, carte mère émulée (q35), son propre noyau.
		vm_qemu "$(mode_vm "$@")" ;;
	firecracker)
		# Une micro-VM : pas de BIOS, pas de PCI, 5 périphériques en tout.
		vm_firecracker "$(mode_vm "$@")" ;;
	*)
		echo "niveau inconnu : $niveau (niveaux : $NIVEAUX)" >&2
		return 2 ;;
	esac
}

# Dans une VM, on ne peut pas passer une commande : on passe un mode sur la
# ligne de commande du noyau, que l'init lit dans /proc/cmdline.
mode_vm() {
	case "$*" in
	"node sonde.js") echo sonde ;;
	"node dist/index.js") echo api ;;
	*) echo vide ;;
	esac
}

# La console série de la VM arrive dans un fichier ; on n'en garde que les
# lignes de l'init (SONDE ..., INIT ...).
vm_qemu() {
	console=$(pwd)/build/console-qemu.log
	qemu-system-x86_64 -M q35 -enable-kvm -cpu host -m 512 -smp 1 \
		-nodefaults -no-user-config -display none -no-reboot \
		-serial "file:$console" \
		-kernel "$NOYAU" \
		-append "console=ttyS0 quiet root=/dev/vda ro init=/init mode=$1" \
		-drive id=d,file="$DISQUE",format=raw,if=none,readonly=on \
		-device virtio-blk-pci,drive=d
	grep -E '^(SONDE|INIT) ' "$console"
}

# Firecracker sans API : toute la machine est décrite dans un fichier JSON.
# Il ajoute lui-même root=/dev/vda et l'adresse du disque au noyau. Les options
# i8042.* évitent 0,5 s d'attente d'un clavier PS/2 qu'il n'émule pas.
vm_firecracker() {
	config=$(pwd)/build/firecracker.json
	cat >"$config" <<-JSON
	{
	  "boot-source": {
	    "kernel_image_path": "$NOYAU",
	    "boot_args": "console=ttyS0 quiet reboot=k panic=1 pci=off i8042.noaux i8042.nomux i8042.nopnp i8042.dumbkbd init=/init mode=$1"
	  },
	  "drives": [{
	    "drive_id": "racine", "path_on_host": "$DISQUE",
	    "is_root_device": true, "is_read_only": true
	  }],
	  "machine-config": { "vcpu_count": 1, "mem_size_mib": 512 }
	}
	JSON
	firecracker --no-api --config-file "$config" </dev/null | grep -E '^(SONDE|INIT) '
}

mediane() { tr ' ' '\n' | grep . | sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}'; }
