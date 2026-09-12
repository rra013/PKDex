// Dumps @smogon/calc's resolved data tables to JSON for the Swift port.
// Run:  npx tsx tools/gen_showdown_data.ts
// Imports the calc's own bundled data (data/*.ts) so the output matches what
// @smogon/calc computes against (parity). MIT — data © Smogon calc contributors.
// See PKDex/ShowdownPort-NOTES.md. Emits PKDex/showdown-champions-data.json
// (inside the synchronized source folder so it auto-bundles).
import { writeFileSync } from 'node:fs';
import { Generations } from './vendor/damage-calc/calc/src/data/index.ts';

// Item/ability *behavior* is encoded in the ported mechanics (name checks), not
// in data — so we only need species, moves and the type chart.
function abilitiesArray(a: any): string[] {
  if (!a) return [];
  return ['0', '1', 'H', 'S'].filter(k => a[k]).map(k => a[k]);
}

function dumpMove(m: any) {
  const out: any = {
    name: m.name,
    basePower: m.basePower ?? 0,
    type: m.type || '???',
  };
  if (m.category) out.category = m.category;
  if (m.flags && Object.keys(m.flags).length) out.flags = m.flags;
  if (m.priority) out.priority = m.priority;
  if (m.target) out.target = m.target;
  if (m.multihit !== undefined) out.multihit = Array.isArray(m.multihit) ? m.multihit : [m.multihit];
  if (m.multiaccuracy) out.multiaccuracy = true;
  if (m.drain) out.drain = m.drain;
  if (m.recoil) out.recoil = m.recoil;
  if (m.hasCrashDamage) out.hasCrashDamage = true;
  if (m.mindBlownRecoil) out.mindBlownRecoil = true;
  if (m.struggleRecoil) out.struggleRecoil = true;
  if (m.willCrit) out.willCrit = true;
  if (m.breaksProtect) out.breaksProtect = true;
  if (m.ignoreDefensive) out.ignoreDefensive = true;
  if (m.overrideOffensiveStat) out.overrideOffensiveStat = m.overrideOffensiveStat;
  if (m.overrideDefensiveStat) out.overrideDefensiveStat = m.overrideDefensiveStat;
  if (m.overrideOffensivePokemon) out.overrideOffensivePokemon = m.overrideOffensivePokemon;
  if (m.overrideDefensivePokemon) out.overrideDefensivePokemon = m.overrideDefensivePokemon;
  if (m.isZ) out.isZ = true;
  if (m.isMax) out.isMax = true;
  if (m.secondaries) out.secondaries = true;
  if (m.self?.boosts) out.selfBoosts = m.self.boosts;
  if (m.zMove?.basePower) out.zMoveBasePower = m.zMove.basePower;
  if (m.maxMove?.basePower) out.maxMoveBasePower = m.maxMove.basePower;
  return out;
}

function dumpSpecies(s: any) {
  const out: any = {
    name: s.name,
    types: s.types,
    baseStats: s.baseStats,
    weightkg: s.weightkg ?? 0,
    abilities: abilitiesArray(s.abilities),
  };
  if (s.gender) out.gender = s.gender;
  if (s.nfe) out.nfe = true;
  if (s.otherFormes) out.otherFormes = s.otherFormes;
  if (s.canGigantamax) out.canGigantamax = true;
  if (s.baseSpecies) out.baseSpecies = s.baseSpecies;
  if (s.name.includes('-Mega') || s.name.includes('-Primal')) out.isMega = true;
  return out;
}

function dumpGen(num: number) {
  const gen: any = (Generations as any).get(num);
  const species: Record<string, any> = {};
  for (const s of gen.species) species[s.name] = dumpSpecies(s);
  const moves: Record<string, any> = {};
  for (const m of gen.moves) moves[m.name] = dumpMove(m);
  const typechart: Record<string, any> = {};
  for (const t of gen.types) typechart[t.name] = t.effectiveness;
  return { generation: num, species, moves, typechart };
}

// Champions is upstream "gen 0". Bundle it (Gen 9 can be added later if the
// mainline calculator is exposed — see ShowdownPort-NOTES.md).
const data = dumpGen(0);
const path = 'PKDex/showdown-champions-data.json';
writeFileSync(path, JSON.stringify(data));
console.error(`wrote ${path}: ${Object.keys(data.species).length} species, ` +
  `${Object.keys(data.moves).length} moves, ${Object.keys(data.typechart).length} types`);
