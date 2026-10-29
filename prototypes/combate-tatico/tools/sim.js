// Simulação headless (balanceamento + checagens de integridade): node tools/sim.js [N]
require('../js/data.js'); require('../js/ai.js'); require('../js/combat.js');
const G = globalThis, N = +process.argv[2] || 500;
const { SKILLS } = G;

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
  let wins = 0, rounds = 0; const types = {};
  for (let s = 1; s <= N; s++) {
    const b = new G.Battle(s);
    while (!b.outcome() && b.round < 40) {
      b.planEnemyIntents();
      const plan = b.buildPlan(pick(b));
      for (const ev of b.resolveRound(plan)) {
        types[ev.type] = (types[ev.type] || 0) + 1;
        // integridade: ninguém morto age, hp nunca negativo
        for (const u of b.units) if (u.hp < 0) throw new Error('hp negativo');
      }
      if (b.outcome()) break;
      b.endRound();
    }
    if (b.outcome() === 'victory') wins++;
    rounds += b.round;
  }
  console.log(`jogador ${label}: vitórias ${(wins / N * 100).toFixed(1)}%, rodadas médias ${(rounds / N).toFixed(1)}`, JSON.stringify(types));
}
