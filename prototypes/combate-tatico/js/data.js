// =====================================================================
// DADOS DE BALANCEAMENTO — edite aqui sem tocar no sistema de combate.
// =====================================================================
(function (G) {
  'use strict';

  const CONFIG = {
    clash: {
      rollMin: 0, rollMax: 3,     // bônus aleatório inteiro, chances iguais
      closeMargin: 1,             // diferença <= 1 → Clash "equilibrado" (destaque maior)
      favorable: 0.60,            // chance de vitória >= 60% → Favorável
      unfavorable: 0.35,          // chance de vitória < 35% → Desfavorável
    },
    speed: { fast: 2, heavy: -2, support: 3, defense: 4 }, // prioridade por tag
    block: 0.5,                   // redução padrão do bloqueio (unidade pode sobrescrever)
    dodge: { base: 0.45, speedFactor: 0.05, heavy: 0.20, fast: -0.20, min: 0.10, max: 0.85 },
    parry: { base: 0.55, heavy: -0.20, fast: 0.10, min: 0.10, max: 0.90, counterDmg: 6 },
    // Intensidade visual do impacto (dano / vida máxima do alvo). Só apresentação, por enquanto;
    // 'knockdown' (derrubada) só acontece com habilidades que têm essa propriedade (impact).
    impact: { medium: 0.14, heavy: 0.26 },
    weaken: { amount: 2, rounds: 2 },  // -2 de força; dura até o fim da próxima rodada
    support: { amount: 2 },            // +2 de força na próxima habilidade ofensiva do aliado
  };

  // kind: attack | defense | protect | support
  // tags: melee | magic | heavy | fast
  const SKILLS = {
    // --- Cavaleiro
    k_basic: { name: 'Ataque Básico', icon: 'sword', kind: 'attack', force: 6, dmg: 8, tags: ['melee'],
      desc: 'Golpe de espada equilibrado.' },
    k_shield: { name: 'Golpe de Escudo', icon: 'shieldbash', kind: 'attack', force: 8, dmg: 6, tags: ['melee'],
      desc: 'Muito confiável em Clashes, pouco dano.' },
    k_heavy: { name: 'Golpe Pesado', windup: 1.5, icon: 'hammer', impact: 'knockdown', kind: 'attack', force: 5, dmg: 14, tags: ['melee', 'heavy'], cooldown: 2,
      desc: 'Lento e devastador. Arriscado em Clashes.' },
    k_guard: { name: 'Postura de Escudo', icon: 'shield', kind: 'defense', reaction: 'block', tags: [],
      desc: 'Bloqueia todos os golpes recebidos nesta rodada (-60% de dano).' },
    k_protect: { name: 'Proteção', icon: 'protect', kind: 'protect', reaction: 'block', tags: [],
      desc: 'Fica na frente de um aliado: recebe e bloqueia os golpes sem oposição destinados a ele.' },
    // --- Espadachim
    s_basic: { name: 'Corte Rápido', hits: [{ share: 0.5, motion: 'h', react: 'light' }, { share: 0.5, motion: 'h2', react: 'light' }], icon: 'slash', kind: 'attack', force: 6, dmg: 7, tags: ['melee', 'fast'],
      desc: 'Corte veloz: age cedo na rodada.' },
    s_precise: { name: 'Golpe Preciso', icon: 'precise', kind: 'attack', force: 9, dmg: 6, tags: ['melee'],
      desc: 'Força alta: vence a maioria dos Clashes.' },
    s_risky: { name: 'Ataque Arriscado', hits: [{ share: 0.25, motion: 'h', react: 'light' }, { share: 0.3, motion: 'd', react: 'medium' }, { share: 0.45, motion: 'over', react: 'final' }], icon: 'risky', impact: 'stagger', kind: 'attack', force: 4, dmg: 15, tags: ['melee'], cooldown: 2,
      desc: 'Força baixa, dano enorme. Ótimo contra quem não vai reagir.' },
    s_parry: { name: 'Aparar', icon: 'parry', kind: 'defense', reaction: 'parry', tags: [],
      desc: 'Tenta aparar o primeiro golpe físico recebido; se der certo, anula e contra-ataca. Não funciona contra magia.' },
    // --- Mago
    m_bolt: { name: 'Projétil Mágico', hits: [{ share: 0.5, motion: 'proj', react: 'light' }, { share: 0.5, motion: 'proj', react: 'final' }], icon: 'bolt', kind: 'attack', force: 6, dmg: 7, tags: ['magic'],
      desc: 'Ataque à distância.' },
    m_blast: { name: 'Explosão Arcana', icon: 'blast', impact: 'knockdown', kind: 'attack', force: 5, dmg: 13, tags: ['magic'], cooldown: 2,
      desc: 'Magia de dano elevado.' },
    m_weaken: { name: 'Enfraquecimento', icon: 'weaken', kind: 'attack', force: 7, dmg: 3, tags: ['magic', 'support'], applies: 'weaken',
      desc: 'Pouco dano, mas o alvo perde 2 de força nos Clashes até o fim da próxima rodada. Age cedo.' },
    m_support: { name: 'Suporte', icon: 'support', kind: 'support', tags: ['support'],
      desc: 'Um aliado ganha +2 de força na próxima habilidade ofensiva. Age cedo.' },
    m_dodge: { name: 'Passo Etéreo', icon: 'dodge', kind: 'defense', reaction: 'dodge', tags: [],
      desc: 'Tenta esquivar de cada golpe recebido nesta rodada.' },

    // --- Brutamontes (prioriza ataques fortes)
    b_smash: { name: 'Esmagar', windup: 1.5, icon: 'hammer', impact: 'knockdown', kind: 'attack', force: 5, dmg: 16, tags: ['melee', 'heavy'], cooldown: 2 },
    b_bash: { name: 'Pancada', icon: 'hammer', kind: 'attack', force: 8, dmg: 9, tags: ['melee'] },
    b_guard: { name: 'Couraça', icon: 'shield', kind: 'defense', reaction: 'block', tags: [] },
    // --- Duelista (prefere alvos vulneráveis)
    d_flurry: { name: 'Lâmina Veloz', hits: [{ share: 0.5, motion: 'h', react: 'light' }, { share: 0.5, motion: 'h2', react: 'final' }], icon: 'slash', kind: 'attack', force: 8, dmg: 7, tags: ['melee', 'fast'] },
    d_lunge: { name: 'Investida Feroz', icon: 'precise', impact: 'stagger', kind: 'attack', force: 6, dmg: 12, tags: ['melee'], cooldown: 2 },
    d_parry: { name: 'Contra-guarda', icon: 'parry', kind: 'defense', reaction: 'parry', tags: [] },
    // --- Conjurador (magias e suporte)
    c_ray: { name: 'Raio Sombrio', icon: 'bolt', kind: 'attack', force: 7, dmg: 10, tags: ['magic'] },
    c_curse: { name: 'Maldição', icon: 'weaken', kind: 'attack', force: 6, dmg: 4, tags: ['magic', 'support'], applies: 'weaken', cooldown: 2 },
    c_veil: { name: 'Véu Sombrio', icon: 'dodge', kind: 'defense', reaction: 'dodge', tags: [] },
  };

  // ATAQUES COMBINADOS — uma ação que consome a ação principal dos dois membros,
  // disputa UM Clash e, se vencer, executa a sequência coreografada.
  // members[0] lidera (é quem aparece como autor da ação).
  //   by: índice do membro que executa o golpe; share: fração do dano total; react: reação daquele impacto
  const COMBOS = {
    combo_ks: { name: 'Investida Conjunta', kind: 'attack', icon: 'combo', tags: ['melee'], combo: true,
      side: 'ally', members: ['knight', 'swordsman'], force: 10, dmg: 15, impact: 'knockdown', cooldown: 3,
      desc: 'Cavaleiro + Espadachim: escudo abre a guarda, dois cortes e o golpe final. Gasta a ação dos dois. Força alta e derruba; dano um pouco menor que dois ataques separados.',
      hits: [{ by: 0, share: 0.3, motion: 'bash', react: 'medium' }, { by: 1, share: 0.2, motion: 'h', react: 'light' },
             { by: 1, share: 0.2, motion: 'd', react: 'light' }, { by: 0, share: 0.3, motion: 'over', react: 'final' }] },
    combo_bd: { name: 'Pressão Brutal', kind: 'attack', icon: 'combo', tags: ['melee'], combo: true,
      side: 'enemy', members: ['brute', 'duelist'], force: 10, dmg: 17, impact: 'knockdown', cooldown: 3,
      hits: [{ by: 0, share: 0.4, motion: 'over', react: 'medium' }, { by: 1, share: 0.15, motion: 'h', react: 'light' },
             { by: 1, share: 0.15, motion: 'h2', react: 'light' }, { by: 0, share: 0.3, motion: 'bash', react: 'final' }] },
  };
  Object.assign(SKILLS, COMBOS);
  const AI_COMBO_CHANCE = 0.3; // frequência moderada de combinações inimigas

  const REACTIONS = {
    block: { name: 'Bloqueio' }, dodge: { name: 'Esquiva' }, parry: { name: 'Aparo' }, none: { name: '—' },
  };

  const STATUS = {
    weaken: { name: 'Enfraquecido', icon: '−', color: '#b58cff', desc: '-2 de força nos Clashes.' },
    support: { name: 'Apoiado', icon: '+', color: '#7fe0a0', desc: '+2 de força na próxima habilidade ofensiva.' },
    block: { name: 'Bloqueando', icon: 'B', color: '#8fc4ff', desc: 'Reduz o dano dos golpes sem oposição.' },
    dodge: { name: 'Esquivando', icon: 'E', color: '#cfe9ff', desc: 'Chance de evitar cada golpe.' },
    parry: { name: 'Aparando', icon: 'A', color: '#ffe28a', desc: 'Tenta aparar o primeiro golpe físico.' },
    protect: { name: 'Protegido', icon: '🛡', color: '#9fd0ff', desc: 'O Cavaleiro recebe os golpes por ele.' },
  };

  // interceptReach: bônus de velocidade só para interceptar ataques contra aliados
  const UNITS = {
    knight: { name: 'Cavaleiro', role: 'Defensor', side: 'ally', art: 'knight',
      hp: 62, spd: 3, interceptReach: 4, blockPower: 0.6,
      skills: ['k_basic', 'k_shield', 'k_heavy', 'k_guard', 'k_protect'],
      trait: 'Intercepta ataques mesmo sendo lento (+4 de alcance). Bloqueio de 60%.' },
    swordsman: { name: 'Espadachim', role: 'Duelista', side: 'ally', art: 'swordsman',
      hp: 44, spd: 8, interceptReach: 0, dodgeSkill: 0.10, parrySkill: 0.10,
      skills: ['s_basic', 's_precise', 's_risky', 's_parry'],
      trait: 'Muito rápido: age cedo e intercepta golpes mais lentos.' },
    mage: { name: 'Mago', role: 'Conjurador', side: 'ally', art: 'mage',
      hp: 34, spd: 5, interceptReach: 0,
      skills: ['m_bolt', 'm_blast', 'm_weaken', 'm_support', 'm_dodge'],
      trait: 'Frágil. Enfraquecimento e Suporte agem cedo e preparam os Clashes dos aliados.' },

    brute: { name: 'Brutamontes', role: 'Força bruta', side: 'enemy', art: 'brute',
      hp: 56, spd: 2, blockPower: 0.5, skills: ['b_smash', 'b_bash', 'b_guard'],
      ai: { prefers: 'strong', defendBelow: 0.35 } },
    duelist: { name: 'Duelista', role: 'Lâminas', side: 'enemy', art: 'duelist',
      hp: 40, spd: 7, dodgeSkill: 0.05, parrySkill: 0.05, skills: ['d_lunge', 'd_flurry', 'd_parry'],
      ai: { prefers: 'weak', defendBelow: 0.30 } },
    conjurer: { name: 'Conjurador', role: 'Magia negra', side: 'enemy', art: 'conjurer',
      hp: 32, spd: 4, skills: ['c_curse', 'c_ray', 'c_veil'],
      ai: { prefers: 'threat', defendBelow: 0.30 } },
  };

  const PARTY = ['knight', 'swordsman', 'mage'];
  const FOES = ['brute', 'duelist', 'conjurer'];
  const AI_THREAT = { mage: 0.6, swordsman: 0.4, knight: 0.0 };

  Object.assign(G, { CONFIG, REACTIONS, STATUS, SKILLS, COMBOS, AI_COMBO_CHANCE, UNITS, PARTY, FOES, AI_THREAT });
})(typeof window !== 'undefined' ? window : globalThis);
