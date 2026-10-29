// Simulação headless (balanceamento + checagens de integridade): node tools/sim.js [N]
require('../js/data.js'); require('../js/ai.js'); require('../js/combat.js');
const G = globalThis, N = +process.argv[2] || 500;
const { SKILLS } = G;
const PARTIES = [['knight', 'swordsman', 'mage'], ['knight', 'mage', 'archer'], ['swordsman', 'lancer', 'brawler'], ['knight', 'brawler', 'mage'], ['lancer', 'archer', 'brawler']];

// Jogador simples: tenta Clashes favoráveis, protege o mago se ele for alvo, senão ataca o mais fraco.
function smartChoices(b) {
  const choices = {};
  const enemies = b.alive('enemy');
  for (const u of b.alive('ally')) {
    const ready = u.def.skills.filter(id => b.skillReady(u, id));
    const atk = ready.filter(id => SKILLS[id].kind === 'attack');
    const threat = b.intents.find(it => it.targetId === u.id && SKILLS[it.skillId].kind === 'attack' && b.unit(it.actorId).hp > 0);
    if (threat) choices[u.id] = { skillId: atk.sort((x, y) => SKILLS[y].force - SKILLS[x].force)[0], targetId: threat.actorId };
    else choices[u.id] = { skillId: atk[Math.floor(b.rand() * atk.length)], targetId: enemies.sort((x, y) => x.hp - y.hp)[0].id, intercept: true };
  }
  // às vezes usa a combinação Cavaleiro + Espadachim no inimigo mais fraco
  if (b.unit('knight') && b.combosFor('knight').length && b.rand() < 0.35) {
    choices.knight = { skillId: 'combo_ks', targetId: enemies.sort((x, y) => x.hp - y.hp)[0].id };
    choices.swordsman = { comboWith: 'knight' };
  }
  return choices;
}
function randomChoices(b) {
  const choices = {};
  for (const u of b.alive('ally')) {
    const atk = u.def.skills.filter(id => b.skillReady(u, id) && SKILLS[id].kind === 'attack');
    const es = b.alive('enemy');
    choices[u.id] = { skillId: atk[Math.floor(b.rand() * atk.length)], targetId: es[Math.floor(b.rand() * es.length)].id };
  }
  return choices;
}

for (const [label, pick] of [['aleatório', randomChoices], ['simples', smartChoices]]) {
  let wins = 0, rounds = 0; const types = {}, byParty = {};
  for (let s = 1; s <= N; s++) {
    const party = PARTIES[s % PARTIES.length];
    const b = new G.Battle(s, party);
    while (!b.outcome() && b.round < 40) {
      b.planEnemyIntents();
      const plan = b.buildPlan(pick(b));
      const acted = new Set();
      const brokenBefore = new Set(b.units.filter(u => u.broken).map(u => u.id));
      for (const ev of b.resolveRound(plan)) {
        if (ev.type === 'stagger') {
          types.lostActions = (types.lostActions || 0) + ev.unitIds.length;
          for (const id of ev.cancelled) { if (acted.has(id)) throw new Error('quebra cancelou ação já usada: ' + id); acted.add(id); }
        }
        if (ev.type === 'clash' && ev.posture) { types.pressure = (types.pressure || 0) + 1; if (ev.posture.broke) types.breaks = (types.breaks || 0) + 1; if (ev.posture.held) types.held = (types.held || 0) + 1; }
        if (ev.crit || (ev.hit && ev.hit.crit)) types.crit = (types.crit || 0) + 1;
        for (const u of b.units) if (u.post < 0 || u.post > u.postMax) throw new Error('postura fora do limite');
        types[ev.type] = (types[ev.type] || 0) + 1;
        // integridade: cada personagem age no máximo uma vez por rodada (combinação conta para os dois)
        const actors = ev.type === 'clash' ? [ev.a, ev.b].flatMap(x => [x.actorId, ...x.partners])
          : ev.type === 'attack' ? [ev.attackerId, ...ev.partners] : ev.type === 'support' ? [ev.actorId] : [];
        for (const id of actors) { if (acted.has(id)) throw new Error('ação duplicada: ' + id); acted.add(id); }
        if (ev.skillId && SKILLS[ev.skillId].combo) types.combo = (types.combo || 0) + 1;
        if (ev.type === 'clash' && [ev.a, ev.b].some(x => SKILLS[x.skillId].combo)) types.comboClash = (types.comboClash || 0) + 1;
        // integridade: ninguém morto age, hp nunca negativo
        for (const u of b.units) if (u.hp < 0) throw new Error('hp negativo');
      }
      if (b.outcome()) break;
      b.endRound();
    }
    const key = party.join('+'); byParty[key] = byParty[key] || [0, 0]; byParty[key][1]++;
    if (b.outcome() === 'victory') { wins++; byParty[key][0]++; }
    rounds += b.round;
  }
  console.log(`jogador ${label}: vitórias ${(wins / N * 100).toFixed(1)}%, rodadas médias ${(rounds / N).toFixed(1)}`, JSON.stringify(types));
  for (const k in byParty) console.log(`   ${k.padEnd(28)} ${(byParty[k][0] / byParty[k][1] * 100).toFixed(0)}%`);
}
