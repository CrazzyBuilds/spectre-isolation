// Sonde : ce que voit un programme dans son environnement d'exécution.
// La même sonde est lancée à chaque niveau du spectre (processus, conteneur,
// gVisor, micro-VM, VM) et affiche une ligne JSON.
'use strict';

const fs = require('node:fs');
const os = require('node:os');
const si = require('systeminformation');

// Coût moyen d'un appel système, mesuré avec stat("/") : c'est le chemin
// programme → noyau que chaque niveau d'isolation rallonge (ou pas).
function statCostNs(iterations) {
  const start = process.hrtime.bigint();
  for (let i = 0; i < iterations; i++) fs.statSync('/');
  return Number(process.hrtime.bigint() - start) / iterations;
}

async function main() {
  const [osInfo, mem, cpu, procs] = await Promise.all([
    si.osInfo(),
    si.mem(),
    si.cpu(),
    si.processes(),
  ]);

  console.log(
    JSON.stringify({
      noyau: os.release(),
      hostname: os.hostname(),
      distro: osInfo.distro,
      memoireMo: Math.round(mem.total / 2 ** 20),
      // Le cache de fichiers du noyau vu par la sonde : celui de l'hôte (partagé
      // par tous les conteneurs) ou celui, propre, du noyau invité d'une VM.
      cacheMo: Math.round(mem.buffcache / 2 ** 20),
      cpus: cpu.cores,
      processus: procs.all,
      // Depuis combien de temps le noyau vu par la sonde tourne : quelques
      // secondes dans une VM qui vient de démarrer, des heures sur l'hôte.
      uptimeNoyauS: Math.round(os.uptime() * 100) / 100,
      statNs: Math.round(statCostNs(200000)),
    }),
  );
}

main();
