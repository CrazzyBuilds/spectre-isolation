#!/bin/sh
# Mesure un niveau du spectre :
#   - demarrageMs : temps médian pour lancer /bin/true (qui ne fait rien),
#     soit le coût pur de l'isolation, sans le travail du programme ;
#   - dontNoyauMs (VM seulement) : la part passée par le noyau invité à
#     démarrer ; le reste, c'est le VMM, le firmware et l'extinction ;
#   - la sonde : ce que voit un programme à ce niveau.
# Usage : ./mesurer.sh <niveau> [répétitions]
set -eu
. ./niveaux.sh

NIVEAU=${1:?usage : $0 <niveau> [répétitions]}
N=${2:-10}

TEMPS=""
NOYAU_MS=""
for i in $(seq 1 "$N"); do
	debut=$(date +%s%N)
	sortie=$(lancer "$NIVEAU" /bin/true)
	TEMPS="$TEMPS $((($(date +%s%N) - debut) / 1000000))"
	# Dans une VM, l'init affiche "INIT <secondes depuis le démarrage du noyau>".
	init=$(echo "$sortie" | sed -n 's/^INIT //p')
	[ -n "$init" ] && NOYAU_MS="$NOYAU_MS $(echo "$init" | awk '{print int($1 * 1000)}')"
done

SONDE=$(lancer "$NIVEAU" node sonde.js | sed 's/^SONDE //' | grep '^{')
echo "$SONDE" | jq -c --arg n "$NIVEAU" \
	--argjson t "$(echo "$TEMPS" | mediane)" \
	--arg k "$(echo "$NOYAU_MS" | mediane)" \
	'{niveau: $n, demarrageMs: $t, dontNoyauMs: (if $k == "" then null else ($k | tonumber) end)} + .'
