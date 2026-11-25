# Fiche — Piste 1 : le spectre de l'isolation

> **La question** : où finit le conteneur, où commence la machine virtuelle ?
> **La méthode** : lancer *le même programme*, sur *les mêmes fichiers*, à cinq
> niveaux d'isolation, et comparer ce qu'il voit, le temps de démarrage et la
> mémoire qu'il coûte à l'hôte.

---

## 1. Le spectre en une image

Chaque niveau ajoute une couche entre le programme et le matériel. La question
qui compte : **à qui le programme parle-t-il quand il fait un appel système ?**

```mermaid
flowchart LR
    subgraph H["Noyau de l'hôte (7.2.15)"]
        P["processus<br/>aucune isolation"]
        M["minibox<br/>namespaces + cgroups"]
        D["Docker (runc)<br/>idem + démon + seccomp"]
    end
    subgraph V["Noyau invité (6.1.155), sous KVM"]
        F["Firecracker<br/>micro-VM"]
        Q["QEMU q35<br/>VM complète"]
    end
    P --> M --> D -.->|"la frontière :<br/>changer de noyau"| F --> Q
```

- **À gauche** (processus, minibox, Docker) : le programme parle au **noyau de
  l'hôte**. L'isolation, ce sont des étiquettes que ce noyau pose sur le
  processus (namespaces = ce qu'il voit, cgroups = ce qu'il peut consommer).
- **À droite** (Firecracker, QEMU) : le programme parle à **son propre noyau**,
  qui tourne sur un processeur virtuel. L'hôte ne voit qu'un seul processus :
  `firecracker` ou `qemu-system-x86_64`.

> [!tip] À retenir
> La frontière conteneur / VM, c'est **le noyau**. Un conteneur partage celui de
> l'hôte, une VM en a un à elle.

---

## 2. Le dispositif

```mermaid
flowchart TB
    IMG["image Docker<br/>crazzybuilds/sysinfo-api:0.0.2"] -->|"docker export"| R["build/rootfs/<br/>Alpine + Node 20 + l'API<br/>+ sonde.js"]
    R -->|"tel quel"| C["processus / minibox / Docker"]
    R -->|"mkfs.ext4 -d<br/>+ vm/init"| E["build/disque.ext4<br/>un « vrai » disque"]
    K["noyau Linux 6.1<br/>(celui de la CI Firecracker)"] --> VM
    E --> VM["QEMU / Firecracker"]
```

- **Les mêmes fichiers partout** : le système de fichiers de ton image du TD2.
  Pour les VM, on le met dans un fichier-disque ext4 (`mkfs.ext4 -d` remplit
  le disque à partir d'un dossier, sans root).
- **Le même Node partout** (v20 de l'image). Même sur l'hôte, on le lance via le
  chargeur musl du rootfs (voir les pièges, §7).
- **Le même noyau pour les deux VM**, pour comparer les VMM et pas les noyaux.
- **Dans une VM, personne ne prépare l'environnement** : c'est notre script
  `vm/init` (PID 1) qui monte `/proc`, `/sys`, `/dev`, lance la sonde puis
  éteint la machine avec `reboot -f`.

**Les trois mesures :**

| Mesure | Comment | Script |
|---|---|---|
| Ce que voit le programme | `sonde.js` : noyau, hostname, mémoire, CPU, processus, uptime du noyau, cache, coût d'un `stat()` | `mesurer.sh` |
| Démarrage | lancer **`/bin/true`** (qui ne fait rien) → coût pur de l'isolation, médiane sur 10 | `mesurer.sh` |
| Mémoire côté hôte | l'API au repos ; on lit `memory.stat` (`anon`) du cgroup qui la contient | `memoire.sh` |

---

## 3. Résultats

Machine : Ryzen 5 5500H (8 threads), 15 Go, noyau 7.2.15, KVM.

| Niveau | Démarrage | Noyau vu | Mémoire vue | CPU | Processus vus | Noyau lancé depuis | Cache vu | `stat()` | Mémoire hôte |
|---|---|---|---|---|---|---|---|---|---|
| processus | **2 ms** | 7.2.15 | 15 326 Mo | 8 | 539 | 3 h 22 | 5 896 Mo | 2 337 ns | 14 Mo |
| minibox | **9 ms** | 7.2.15 | 15 326 Mo | 8 | 2 | 3 h 22 | 5 891 Mo | 2 312 ns | 13 Mo |
| Docker | **423 ms** | 7.2.15 | 15 326 Mo | 8 | 3 | 3 h 22 | 5 904 Mo | 2 694 ns | 11 Mo |
| Firecracker | **155 ms** (dont noyau 60) | **6.1.155** | **482 Mo** | **1** | 53 | **0,26 s** | **55 Mo** | 2 671 ns | **106 Mo** |
| QEMU q35 | **456 ms** (dont noyau 270) | **6.1.155** | **482 Mo** | **1** | 51 | **0,45 s** | **55 Mo** | 2 753 ns | **125 Mo** |

---

## 4. Lecture n° 1 : ce que voit le programme

**Dans un conteneur, le programme voit l'hôte**, sauf ce que les namespaces
cachent :

- ✅ caché : les autres processus (2–3 au lieu de 539 : namespace PID), le nom
  de la machine (namespace UTS), les fichiers (namespace mount).
- ❌ pas caché : **le noyau** (7.2.15, démarré il y a 3 h), **la mémoire totale**
  (15 Go), **les CPU** (8), **le cache de fichiers** de l'hôte. Même avec une
  limite cgroup, `/proc/meminfo` montre la machine entière (c'est pour ça que
  minibox a l'option `-fake-meminfo`, piste 2, étape 7).

**Dans une VM, le programme voit une autre machine** : un autre noyau, démarré
il y a un quart de seconde, 482 Mo (les 512 Mo donnés moins ce que le noyau se
réserve), 1 CPU. Les ~50 « processus » sont surtout des *threads du noyau
invité* (`kworker`, `ksoftirqd`…) : dans un conteneur ils sont cachés, parce que
ceux de l'hôte n'appartiennent pas au namespace PID.

> [!example] Le lien avec le TD4
> Sur Azure Container Instances, la même API voyait **1 CPU, 1,45 Gio, un noyau
> `6.1.158.2-microsoft-standard`**, `system.virtual: true`. Exactement la
> signature de nos lignes Firecracker / QEMU, et pas celle de la ligne Docker.
> Le « conteneur » Azure tourne donc dans une **petite VM dédiée** : entre
> clients différents, partager un noyau serait trop risqué.

---

## 5. Lecture n° 2 : le démarrage

```mermaid
gantt
    title Démarrer puis arrêter « rien » (/bin/true), en ms
    dateFormat x
    axisFormat %L
    section minibox
    clone + pivot_root + exec      :0, 9
    section Docker
    client → dockerd → containerd → shim → runc, overlay, réseau :0, 423
    section Firecracker
    noyau invité                   :0, 60
    VMM + extinction               :60, 155
    section QEMU q35
    noyau invité                   :0, 270
    VMM + firmware + extinction    :270, 456
```

Trois constats :

1. **minibox est ~50× plus rapide que Docker**, alors que le cœur est le même
   (namespaces + cgroups). Le temps de Docker, c'est la *chaîne* : le client
   parle au démon par une socket, qui délègue à containerd, qui lance un shim,
   qui lance runc ; plus la préparation de l'overlay et du réseau (veth,
   bridge). Le conteneur lui-même ne coûte que quelques millisecondes.
2. **Une micro-VM démarre plus vite qu'un `docker run`**. Pas besoin de
   « démarrer un ordinateur » si l'ordinateur est minuscule.
3. **Firecracker vs QEMU, même noyau : 60 ms contre 270 ms** dans le noyau. La
   différence, c'est le matériel à découvrir :

| | QEMU q35 | Firecracker |
|---|---|---|
| Firmware | SeaBIOS (un vrai BIOS émulé) | aucun : il charge le noyau et saute dedans |
| Bus | PCI Express, ACPI | aucun : le disque est annoncé sur la ligne de commande (`virtio_mmio.device=4K@0xc0001000:5`) |
| Périphériques | chipset Intel complet, des dizaines de périphériques possibles | 5 : virtio-blk, virtio-net, virtio-vsock, port série, i8042 minimal (sert juste à éteindre la VM) |
| Code du VMM | > 1,4 million de lignes (C) | ~50 000 lignes (Rust) |

Moins de matériel = moins à détecter au démarrage, **et moins de code exposé à
un attaquant** qui sortirait du noyau invité. C'est pour ça qu'AWS a écrit
Firecracker pour Lambda et Fargate (Agache et al., *Firecracker: Lightweight
Virtualization for Serverless Applications*, NSDI 2020, d'où viennent les
tailles de code ci-dessus).

---

## 6. Lecture n° 3 : la mémoire et les appels système

**Mémoire côté hôte** : ~12 Mo pour l'API dans un conteneur, ~110 Mo dans une
VM. Où partent les ~95 Mo de plus ?

```mermaid
flowchart LR
    subgraph HOTE["Hôte"]
        CACHE["cache de fichiers de l'hôte<br/>(binaire node lu une fois)"]
        C1["conteneur 1<br/>tas de Node ~12 Mo"] --> CACHE
        C2["conteneur 2<br/>tas de Node ~12 Mo"] --> CACHE
        subgraph VM1["VM 1 : ~106 Mo"]
            K1["noyau invité"]
            CA1["son propre cache<br/>55 Mo (node relu)"]
            N1["tas de Node"]
        end
    end
```

- Un conteneur **partage le cache de fichiers de l'hôte** : le binaire `node`
  (~55 Mo) est en mémoire une seule fois, quel que soit le nombre de conteneurs.
- Une VM a **son propre noyau et son propre cache** : elle relit `node` depuis
  son disque virtuel, dans *sa* RAM. Pour l'hôte, c'est de la mémoire
  anonyme du processus `firecracker`, **dupliquée dans chaque VM**.
- La RAM de la VM n'est allouée que quand l'invité la touche : 512 Mo donnés,
  ~110 Mo réellement utilisés.

**Appels système** : `stat("/")` coûte à peu près pareil partout (2,3 à
2,8 µs). Avec KVM, un appel système **ne sort pas de la VM** : le processeur
exécute le noyau invité directement, sans passer par l'hyperviseur. Ce qui coûte
cher dans une VM, ce sont les **sorties vers le VMM** (« VM exits »), à chaque
accès à un périphérique émulé. La preuve (§7, piège n° 4) : sans l'option
`quiet`, la VM QEMU mettait 1,7 s au lieu de 0,46 s, car **chaque caractère**
écrit sur le port série émulé est une sortie vers QEMU.

> [!tip] À retenir
> Conteneur : isolation **logique**, quasi gratuite, mais un seul noyau partagé
> (une faille du noyau = tout le monde est touché).
> VM : isolation **matérielle** (le processeur la garantit), payée surtout en
> mémoire (~100 Mo par VM) et en périphériques émulés.

---

## 7. Les pièges rencontrés (et ce qu'ils apprennent)

| # | Symptôme | Cause | Leçon |
|---|---|---|---|
| 1 | La sonde met 5 s dans minibox, 0,4 s dans Docker | `os.hostname()` → recherche DNS de « minibox », sans `/etc/hosts` ni DNS : 5 s de timeout | Docker écrit `/etc/hosts` et `/etc/resolv.conf` dans chaque conteneur. minibox le fait maintenant aussi |
| 2 | Le noyau plante (`divide error`) dans QEMU `microvm` | la console série de ce mode ne convient pas au noyau Firecracker | un VMM, c'est un contrat précis avec le noyau ; passage en `q35` |
| 3 | Firecracker plus lent que QEMU (660 ms) | le noyau attend 0,5 s un clavier PS/2 que Firecracker n'émule pas | options `i8042.noaux i8042.nomux i8042.nopnp i8042.dumbkbd` (doc Firecracker) → 155 ms |
| 4 | QEMU : 1,7 s | les messages du noyau sur le port série : une sortie VM par caractère | option `quiet` → 0,46 s |
| 5 | `stat()` 25 % plus rapide sans isolation ?! | l'hôte utilisait son Node v26 (glibc), les autres le v20 de l'image (musl) | **comparer à armes égales** : lancer le Node de l'image sur l'hôte via `ld-musl-x86_64.so.1` → l'écart disparaît |

Le piège n° 5 est le plus important : sans lui, on aurait « prouvé » que
l'isolation ralentit les appels système de 25 %. **Une mesure ne vaut que si on
ne change qu'une chose à la fois.**

---

## 8. Reproduire

```sh
./preparer-rootfs.sh            # build/rootfs depuis l'image Docker
vm/preparer-disque.sh           # build/disque.ext4 pour les VM
# noyau : vmlinux-6.1.155 de la CI Firecracker, dans build/noyau/
./mesurer.sh firecracker        # une ligne JSON par niveau
./memoire.sh firecracker
```

Niveaux : `processus minibox docker qemu firecracker`. Aucun n'a besoin de root
(`/dev/kvm` accessible à l'utilisateur, Docker déjà installé).

---

## 9. Questions pour vérifier

<details><summary>1. Pourquoi la sonde voit-elle 15 Go de mémoire dans Docker mais 482 Mo dans Firecracker ?</summary>
Dans Docker, <code>/proc/meminfo</code> est produit par le noyau de l'hôte, qui décrit la machine entière (les namespaces ne cachent pas la mémoire). Dans Firecracker, c'est le noyau invité qui répond, et sa machine n'a que 512 Mo (moins sa réserve).
</details>

<details><summary>2. Pourquoi ~50 processus dans la VM et 2 dans minibox ?</summary>
Dans la VM, la sonde voit les threads du noyau invité (kworker…). Dans minibox, le namespace PID ne montre que les processus créés dedans ; les threads du noyau de l'hôte en sont exclus.
</details>

<details><summary>3. Comment savoir, depuis l'intérieur, si on est dans un conteneur ou une VM ?</summary>
Regarder le noyau et son uptime : même noyau que l'hôte, démarré il y a longtemps → conteneur ; noyau différent démarré il y a quelques instants → VM. Aussi : les CPU et la mémoire vus.
</details>

<details><summary>4. Pourquoi minibox démarre-t-il 50× plus vite que Docker ?</summary>
Le cœur est identique (clone avec namespaces, cgroup, pivot_root, exec). Docker ajoute une chaîne de démons (dockerd, containerd, shim, runc) reliés par des sockets, plus la préparation de l'overlay et du réseau.
</details>

<details><summary>5. Pourquoi le même noyau démarre-t-il 4× plus vite dans Firecracker que dans QEMU q35 ?</summary>
Moins de matériel à découvrir : pas de BIOS, pas de PCI ni d'ACPI à énumérer, 5 périphériques. Le disque est annoncé directement sur la ligne de commande du noyau.
</details>

<details><summary>6. Pourquoi un appel système ne coûte-t-il presque rien de plus dans une VM ?</summary>
Avec la virtualisation matérielle (KVM, AMD-V), le processeur exécute le noyau invité directement. Un appel système va du programme au noyau invité sans sortir de la VM. Seuls les accès aux périphériques émulés provoquent une sortie vers le VMM.
</details>

<details><summary>7. Où partent les ~95 Mo de plus d'une VM ?</summary>
Dans son propre noyau et son propre cache de fichiers (le binaire node relu depuis le disque virtuel, 55 Mo). Des conteneurs partagent le cache de l'hôte ; chaque VM a le sien, dupliqué.
</details>

<details><summary>8. Pourquoi Azure (TD4) met-il les conteneurs dans des micro-VM ?</summary>
Des conteneurs de clients différents tournent sur les mêmes serveurs. Partager le noyau = une faille du noyau permettrait de sortir vers les autres clients. Une micro-VM garde le démarrage rapide (~150 ms) tout en ajoutant la frontière matérielle de l'hyperviseur.
</details>

<details><summary>9. Pourquoi la mesure de stat() était-elle fausse au début ?</summary>
Deux choses changeaient en même temps : l'isolation et la version de Node (v26 glibc sur l'hôte, v20 musl ailleurs). En lançant le Node de l'image sur l'hôte, l'écart disparaît : c'était Node, pas l'isolation.
</details>

<details><summary>10. Pourquoi « quiet » accélère-t-il autant le démarrage de QEMU ?</summary>
Chaque caractère écrit sur le port série émulé est une écriture sur un port d'E/S, qui provoque une sortie de la VM vers QEMU (VM exit). Des milliers de caractères = des milliers d'allers-retours.
</details>
