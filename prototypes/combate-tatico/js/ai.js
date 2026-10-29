// =====================================================================
// IA — simples e coerente. Usa o RNG da batalha (determinístico).
// =====================================================================
(function (G) {
  'use strict';
  const { SKILLS, CONFIG, AI_THREAT } = G;

  const AI = {
    // Reação de um inimigo a um golpe do jogador: minimiza dano esperado,
    // com um viés de personalidade e um pouco de imprevisibilidade.
    chooseReaction(battle, d, a, skill) {
      const opts = battle.reactionOptions(d, a, skill);
      if (opts.length === 1) return opts[0].kind;
      const bias = (d.def.ai && d.def.ai.bias) || {};
      const base = Math.max(1, battle.rawDamage(a, d, skill) * battle.multipliers(a, d, skill));
      let best = null, bestScore = Infinity;
      for (const o of opts) {
        let score = o.expected / base - (bias[o.kind] || 0);
        if (o.kind === 'parry') score -= o.chance * 0.3; // valor do contra-ataque
        score += (battle.rand() - 0.5) * 0.25;
        if (score < bestScore) { bestScore = score; best = o.kind; }
      }
      return best;
    },

    targetScore(battle, u, rnd) {
      const hpRatio = u.hp / u.maxHp;
      let s = (1 - hpRatio) * 1.6 + (AI_THREAT[u.id] || 0);
      if (u.statuses.vulnerable) s += 0.8;
      if (u.hp < 25) s += 0.5; // tenta finalizar
      return s + rnd * 0.5;
    },

    planIntents(battle) {
      const allies = battle.alive('ally');
      const enemies = battle.alive('enemy');
      if (!allies.length) return [];
      // alvo "foco" da equipe inimiga para criar combos (maldição + esmagar)
      const scored = allies.map(u => ({ u, s: this.targetScore(battle, u, battle.rand()) }))
        .sort((x, y) => y.s - x.s);
      const focus = scored[0].u;
      const intents = [];
      for (const e of enemies) {
        let target = battle.rand() < 0.7 ? focus : scored[Math.floor(battle.rand() * scored.length)].u;
        // Provocação força o alvo
        if (e.statuses.taunt) {
          const k = battle.unit(e.statuses.taunt);
          if (k && k.hp > 0) target = k;
          delete e.statuses.taunt;
        }
        const ready = e.def.skills.filter(id => battle.skillReady(e, id));
        let skillId = ready[ready.length - 1];
        for (const id of ready) {
          const sk = SKILLS[id];
          if (sk.applies === 'vulnerable') {
            // só amaldiçoa se o alvo ainda não estiver vulnerável
            if (!target.statuses.vulnerable && battle.rand() < 0.75) { skillId = id; break; }
          } else if (sk.cooldown && battle.rand() < 0.7) { skillId = id; break; }
        }
        intents.push({ attackerId: e.id, skillId, targetId: target.id });
      }
      return intents;
    },
  };

  G.AI = AI;
})(typeof window !== 'undefined' ? window : globalThis);
