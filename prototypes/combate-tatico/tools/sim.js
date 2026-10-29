// Simulação headless do combate (balanceamento): node tools/sim.js [N]
require('../js/data.js'); require('../js/ai.js'); require('../js/combat.js');
const G = globalThis, N = +process.argv[2] || 500;
let wins = 0, rounds = 0, outcomes = {};
for (let s = 1; s <= N; s++) {
  const b = new G.Battle(s);
  while (!b.outcome() && b.round < 40) {
    const plans = b.alive('ally').map(u => {
      const ready = u.def.skills.filter(id => b.skillReady(u, id));
      const t = b.alive('enemy').sort((x, y) => x.hp - y.hp)[0];
      return { attackerId: u.id, skillId: ready[Math.floor(b.rand() * ready.length)], targetId: t.id };
    });
    for (const r of b.resolvePlayerPhase(plans)) outcomes[r.outcome] = (outcomes[r.outcome] || 0) + 1;
    if (b.outcome()) break;
    const intents = b.planEnemyIntents();
    for (const r of b.resolveEnemyPhase(intents, {})) outcomes[r.outcome] = (outcomes[r.outcome] || 0) + 1;
    if (b.outcome()) break;
    b.endRound();
  }
  if (b.outcome() === 'victory') wins++;
  rounds += b.round;
}
console.log(`IA-vs-IA simples (jogador aleatório, defesas padrão): vitórias ${(wins / N * 100).toFixed(1)}%, rodadas médias ${(rounds / N).toFixed(1)}`);
console.log(outcomes);
