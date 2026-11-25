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
	*)
		echo "niveau inconnu : $NIVEAU" >&2
		exit 2 ;;
	esac
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
