# spectre-isolation

Le même programme (une sonde Node, construite sur l'image `sysinfo-api`), sur
les mêmes fichiers, lancé à cinq niveaux d'isolation : processus, minibox,
Docker, micro-VM Firecracker et VM QEMU. On compare ce qu'il voit, son temps de
démarrage et la mémoire qu'il coûte à l'hôte.

Résultats, explications et pièges rencontrés : **[FICHE.md](FICHE.md)**.

| Fichier | Rôle |
|---|---|
| `sonde/sonde.js` | ce que voit le programme (une ligne JSON) |
| `preparer-rootfs.sh` | extrait le système de fichiers de l'image dans `build/rootfs` |
| `vm/init`, `vm/preparer-disque.sh` | PID 1 des VM et disque ext4 construit depuis le rootfs |
| `niveaux.sh` | comment lancer une commande à chaque niveau |
| `mesurer.sh <niveau>` | démarrage (`/bin/true`, médiane) + sonde |
| `memoire.sh <niveau>` | mémoire de l'API au repos, lue dans le cgroup |
| `resultats/mesures.jsonl` | les mesures de la fiche |

Prérequis : Docker, QEMU, Firecracker, `/dev/kvm` accessible, `jq`,
[minibox](https://github.com/CrazzyBuilds/minibox), et le noyau
`vmlinux-6.1.155` de la CI Firecracker dans `build/noyau/`.
