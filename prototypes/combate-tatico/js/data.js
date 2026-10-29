// =====================================================================
// DADOS DE BALANCEAMENTO — edite aqui sem tocar no sistema de combate.
// =====================================================================
(function (G) {
  'use strict';

  // Fórmulas gerais (todas configuráveis)
  const CONFIG = {
    damage: {
      atkRef: 7,         // dano = power * (atk / atkRef) * (defRef / (defRef + def))
      defRef: 20,
      variance: 0.10,    // ±10% de aleatoriedade no dano
      min: 1,
    },
    vulnerableMult: 1.5, // próximo golpe recebido por um alvo Vulnerável
    markMult: 1.4,       // próximo golpe aliado num alvo Marcado (e não pode esquivar/aparar)
    dodge: {
      base: 0.40,
      speedFactor: 0.04, // por ponto de velocidade do defensor acima do atacante
      tagMods: { heavy: 0.20, fast: -0.20, magic: -0.05 },
      min: 0.05, max: 0.85,
    },
    parry: {
      base: 0.40,
      tagMods: { heavy: -0.20, fast: 0.10 },
      min: 0.05, max: 0.85,
      failMult: 1.25,     // aparar errado custa caro
      counterPower: 10,   // poder do contra-ataque (não pode ser reagido)
    },
    decisiveRatio: 0.30,  // golpe que tira >=30% da vida máx. (ou mata) é "decisivo"
    seedRandom: true,
  };

  // Reações defensivas
  const REACTIONS = {
    block: { name: 'Bloquear', short: 'Bloq.', desc: 'Sempre funciona. Reduz o dano.' },
    barrier: { name: 'Barreira', short: 'Barr.', desc: 'Escudo mágico. Sempre funciona, reduz o dano.' },
    dodge: { name: 'Esquivar', short: 'Esq.', desc: 'Evita todo o dano se der certo. Falha = dano total.' },
    parry: { name: 'Aparar', short: 'Apar.', desc: 'Anula e contra-ataca se der certo. Falha = +25% de dano. Não funciona contra magia.' },
    none: { name: 'Receber', short: '—', desc: 'Sem reação.' },
  };

  // Status (apenas três, de propósito)
  const STATUS = {
    vulnerable: { name: 'Vulnerável', icon: 'V', color: '#ff9a3c', desc: 'Próximo golpe recebido causa +50% de dano.' },
    mark: { name: 'Marca Rúnica', icon: 'M', color: '#b58cff', desc: 'Próximo golpe aliado: +40% e não pode ser esquivado/aparado.' },
    taunt: { name: 'Provocado', icon: '!', color: '#ff5050', desc: 'Atacará o Cavaleiro na próxima ofensiva.' },
  };

  // Habilidades. tags: melee | magic | heavy | fast
  const SKILLS = {
    // --- Cavaleiro
    k_heavy: { name: 'Golpe Pesado', power: 20, tags: ['melee', 'heavy'], cooldown: 0,
      desc: 'Golpe lento e brutal. Fácil de esquivar, difícil de aparar.' },
    k_shield: { name: 'Quebra-Guarda', power: 11, tags: ['melee'], applies: 'vulnerable',
      desc: 'Pancada de escudo. Deixa o alvo Vulnerável (+50% no próximo golpe).' },
    k_taunt: { name: 'Desafio', power: 9, tags: ['melee'], applies: 'taunt', cooldown: 2,
      desc: 'Provoca o alvo: ele atacará o Cavaleiro na próxima ofensiva inimiga.' },
    // --- Espadachim
    s_quick: { name: 'Corte Rápido', power: 13, tags: ['melee', 'fast'],
      desc: 'Corte veloz, difícil de esquivar.' },
    s_thrust: { name: 'Estocada Precisa', power: 12, tags: ['melee', 'fast'], vulnerableBonus: 2.0,
      desc: 'Causa dano dobrado contra alvos Vulneráveis.' },
    s_ghost: { name: 'Lâmina Fantasma', power: 18, tags: ['melee'], unblockable: true, cooldown: 2,
      desc: 'Atravessa bloqueios e barreiras.' },
    // --- Mago
    m_bolt: { name: 'Seta Arcana', power: 13, tags: ['magic'],
      desc: 'Projétil mágico. Magia não pode ser aparada.' },
    m_mark: { name: 'Marca Rúnica', power: 6, tags: ['magic'], applies: 'mark',
      desc: 'Marca o alvo: o próximo aliado a atingi-lo ganha +40% e ignora esquiva/aparo.' },
    m_flame: { name: 'Chama Sombria', power: 22, tags: ['magic'], cooldown: 2,
      desc: 'Explosão de fogo negro.' },
    // --- Brutamontes
    b_smash: { name: 'Esmagar', power: 24, tags: ['melee', 'heavy'], cooldown: 2,
      telegraph: '{u} ergue a clava acima da cabeça e mira em {t}!' },
    b_bash: { name: 'Pancada', power: 14, tags: ['melee', 'heavy'],
      telegraph: '{u} bate a clava no chão e encara {t}.' },
    // --- Duelista inimigo
    d_flurry: { name: 'Lâmina Veloz', power: 14, tags: ['melee', 'fast'],
      telegraph: '{u} assume uma postura ofensiva mirando em {t}.' },
    d_lunge: { name: 'Investida Feroz', power: 19, tags: ['melee'], cooldown: 2,
      telegraph: '{u} recua o florete e prepara uma investida contra {t}!' },
    // --- Conjurador
    c_ray: { name: 'Raio Sombrio', power: 15, tags: ['magic'],
      telegraph: '{u} começa a conjurar um raio contra {t}.' },
    c_curse: { name: 'Maldição', power: 7, tags: ['magic'], applies: 'vulnerable', cooldown: 2,
      telegraph: '{u} sussurra uma maldição para {t}… (deixa Vulnerável)' },
  };

  // Personagens. reactions[0] é a defesa automática padrão.
  const UNITS = {
    knight: { name: 'Cavaleiro', role: 'Defensor', side: 'ally', art: 'knight',
      hp: 95, atk: 10, def: 9, spd: 3, dodgeSkill: -0.15, parrySkill: -0.05, blockPower: 0.55,
      reactions: ['block', 'parry'], skills: ['k_heavy', 'k_shield', 'k_taunt'], canProtect: true,
      trait: 'Escudo: bloqueia 55% do dano. Pode PROTEGER um aliado por rodada.' },
    swordsman: { name: 'Espadachim', role: 'Duelista', side: 'ally', art: 'swordsman',
      hp: 65, atk: 11, def: 4, spd: 9, dodgeSkill: 0.10, parrySkill: 0.20, blockPower: 0.35,
      reactions: ['parry', 'dodge', 'block'], skills: ['s_quick', 's_thrust', 's_ghost'],
      trait: 'Mestre do aparo: chances altas de esquivar e aparar.' },
    mage: { name: 'Mago', role: 'Suporte', side: 'ally', art: 'mage',
      hp: 52, atk: 11, def: 2, spd: 6, dodgeSkill: -0.05, parrySkill: 0, blockPower: 0.40,
      reactions: ['barrier', 'dodge'], skills: ['m_bolt', 'm_mark', 'm_flame'],
      trait: 'Barreira arcana: reduz 40% do dano. Não sabe aparar.' },

    brute: { name: 'Brutamontes', role: 'Força bruta', side: 'enemy', art: 'brute',
      hp: 95, atk: 12, def: 7, spd: 2, dodgeSkill: -0.25, parrySkill: -0.15, blockPower: 0.40,
      reactions: ['block', 'parry'], skills: ['b_smash', 'b_bash'], threat: 0, ai: { bias: { block: 0.10 } } },
    duelist: { name: 'Duelista', role: 'Lâminas', side: 'enemy', art: 'duelist',
      hp: 62, atk: 11, def: 4, spd: 8, dodgeSkill: 0.05, parrySkill: 0.15, blockPower: 0.30,
      reactions: ['parry', 'dodge'], skills: ['d_lunge', 'd_flurry'], ai: { bias: { parry: 0.15 } } },
    conjurer: { name: 'Conjurador', role: 'Magia negra', side: 'enemy', art: 'conjurer',
      hp: 52, atk: 11, def: 2, spd: 5, dodgeSkill: 0, parrySkill: 0, blockPower: 0.35,
      reactions: ['barrier', 'dodge'], skills: ['c_curse', 'c_ray'], ai: { bias: { dodge: 0.05 } } },
  };

  const PARTY = ['knight', 'swordsman', 'mage'];
  const FOES = ['brute', 'duelist', 'conjurer'];

  // Ameaça percebida pela IA ao escolher alvos
  const AI_THREAT = { mage: 0.6, swordsman: 0.4, knight: 0.0 };

  Object.assign(G, { CONFIG, REACTIONS, STATUS, SKILLS, UNITS, PARTY, FOES, AI_THREAT });
})(typeof window !== 'undefined' ? window : globalThis);
