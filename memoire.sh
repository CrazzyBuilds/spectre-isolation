#!/bin/sh
# Mémoire consommée sur l'hôte par l'API sysinfo, à un niveau du spectre.
#
# On lance l'API, on attend qu'elle soit au repos, puis on lit le cgroup qui
# la contient : chaque niveau tourne dans son propre cgroup (un « scope »
# systemd, celui de minibox ou celui de Docker), et memory.stat y compte :
#   - anon : la mémoire propre au niveau (tas de Node, et pour une VM toute
#     la RAM que l'invité a touchée : son noyau, ses processus, son cache) ;
#   - shmem : la mémoire partagée ; gVisor y range la mémoire de l'appli
#     (un fichier mémoire que le Sentry distribue à ses processus) ;
#   - propreMo = anon + shmem : ce que ce niveau coûte en propre à l'hôte.
# On ne compte pas le cache de fichiers (file) : il est imputé au premier
# cgroup qui a lu le fichier, donc il dépend de l'ordre des mesures.
# Usage : ./memoire.sh <niveau> [secondes d'attente]
set -eu
. ./niveaux.sh

NIVEAU=${1:?usage : $0 <niveau> [secondes]}
ATTENTE=${2:-5}
SCOPE=spectre-$NIVEAU-$$
CGROUPS=/sys/fs/cgroup

case "$NIVEAU" in
docker)
	# Docker crée lui-même le cgroup du conteneur (géré par root).
	DOCKER_NOM=$SCOPE lancer docker node dist/index.js >/dev/null &
	sleep "$ATTENTE"
	cg=$CGROUPS/system.slice/docker-$(docker inspect -f '{{.Id}}' "$SCOPE").scope ;;
minibox)
	# minibox place l'API dans son propre cgroup : le plus récent créé.
	lancer minibox node dist/index.js >/dev/null &
	sleep "$ATTENTE"
	cg=$(ls -dt "$CGROUPS"/user.slice/user-"$(id -u)".slice/user@"$(id -u)".service/minibox/*/ | head -1) ;;
*)
	# Les autres niveaux tournent dans un scope systemd créé pour l'occasion.
	systemd-run --user --scope --quiet --unit="$SCOPE" \
		sh -c ". ./niveaux.sh && lancer $NIVEAU node dist/index.js" >/dev/null &
	sleep "$ATTENTE"
	cg=$CGROUPS$(systemctl --user show -P ControlGroup "$SCOPE.scope") ;;
esac

mo() { awk -v c="$1" '$1 == c {printf "%d", $2 / 1048576}' "$cg/memory.stat"; }
jq -nc --arg n "$NIVEAU" --argjson a "$(mo anon)" --argjson s "$(mo shmem)" \
	'{niveau: $n, propreMo: ($a + $s), anonMo: $a, shmemMo: $s}'

# Arrêt : cgroup.kill tue d'un coup tous les processus du cgroup.
if [ "$NIVEAU" = docker ]; then
	docker rm -f "$SCOPE" >/dev/null
else
	echo 1 >"$cg/cgroup.kill"
fi
wait 2>/dev/null || true
