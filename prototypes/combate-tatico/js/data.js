// =====================================================================
// DADOS DE BALANCEAMENTO — edite aqui sem tocar no sistema de combate.
// =====================================================================
(function (G) {
  'use strict';

  const CONFIG = {
    clash: {
      // CLASH EM BATIDAS: cada habilidade tem 'beats' (1–3) e 'impulse' (bônus 0..impulse por batida).
      // Força acumulada = força base + soma dos impulsos; o Clash dura o maior número de batidas.
      // Habilidade com menos batidas mantém o valor acumulado nas batidas seguintes.
      rollMin: 0, rollMax: 3,     // (impulso padrão de habilidades sem 'impulse')
      closeMargin: 1,             // diferença <= 1 → Clash "equilibrado" (destaque maior)
      favorable: 0.60,            // (legado)
      unfavorable: 0.35,          // (legado)
      evenBand: 0.12,             // |P(vitória) − P(derrota)| <= 12 pontos → Equilibrado; acima, Favorável/Desfavorável
    },
    speed: { fast: 2, heavy: -2, support: 3, defense: 4 }, // prioridade por tag
    block: 0.5,                   // redução padrão do bloqueio (unidade pode sobrescrever)
    dodge: { base: 0.45, speedFactor: 0.05, heavy: 0.20, fast: -0.20, min: 0.10, max: 0.85 },
    parry: { base: 0.55, heavy: -0.20, fast: 0.10, min: 0.10, max: 0.90, counterDmg: 6 },
    // Intensidade visual do impacto (dano / vida máxima do alvo). Só apresentação, por enquanto;
    // 'knockdown' (derrubada) só acontece com habilidades que têm essa propriedade (impact).
    impact: { medium: 0.14, heavy: 0.26 },
    weaken: { amount: 2, rounds: 2 },
    // POSTURA: só o perdedor de um Clash perde Postura (Pressão da habilidade vencedora, uma vez por habilidade).
    // Em 0 → Quebra: perde a próxima ação; depois volta ao máximo e fica protegido até agir.
    posture: { protectedMin: 1 },
    // CRÍTICO: rolado uma vez por habilidade que acerta; não afeta o Clash.
    crit: { chance: 0.10, mult: 1.5, hitstop: 130 },  // -2 de força; dura até o fim da próxima rodada
    support: { amount: 2 },            // +2 de força na próxima habilidade ofensiva do aliado
  };

  // kind: attack | defense | protect | support
  // tags: melee | magic | heavy | fast
  const SKILLS = {
    // --- Cavaleiro
    k_basic: { name: 'Ataque Básico', pressure: 15, icon: 'sword', kind: 'attack', beats: 2, impulse: 2, force: 5, dmg: 8, tags: ['melee'],
      desc: 'Golpe de espada equilibrado.' },
    k_shield: { name: 'Golpe de Escudo', pressure: 10, icon: 'shieldbash', kind: 'attack', beats: 1, impulse: 3, force: 8, dmg: 6, tags: ['melee'],
      desc: 'Muito confiável em Clashes, pouco dano.' },
    k_heavy: { name: 'Golpe Pesado', pressure: 35, windup: 1.5, icon: 'hammer', impact: 'knockdown', kind: 'attack', beats: 1, impulse: 3, force: 5, dmg: 14, tags: ['melee', 'heavy'], cooldown: 2,
      desc: 'Lento e devastador. Arriscado em Clashes.' },
    k_guard: { name: 'Firmar Guarda', postureHeal: 25, icon: 'shield', kind: 'defense', reaction: 'block', tags: [],
      desc: 'Bloqueia os golpes desta rodada (-60% de dano) e recupera 25 de Postura.' },
    k_protect: { name: 'Proteção', icon: 'protect', kind: 'protect', reaction: 'block', tags: [],
      desc: 'Fica na frente de um aliado: recebe e bloqueia os golpes sem oposição destinados a ele.' },
    // --- Espadachim
    s_basic: { name: 'Corte Rápido', pressure: 12, hits: [{ share: 0.5, motion: 'h', react: 'light' }, { share: 0.5, motion: 'h2', react: 'light' }], icon: 'slash', kind: 'attack', beats: 2, impulse: 2, force: 5, dmg: 7, tags: ['melee', 'fast'],
      desc: 'Corte veloz: age cedo na rodada.' },
    s_precise: { name: 'Golpe Preciso', pressure: 8, icon: 'precise', kind: 'attack', beats: 1, impulse: 3, force: 9, dmg: 6, tags: ['melee'],
      desc: 'Força alta: vence a maioria dos Clashes.' },
    s_risky: { name: 'Ataque Arriscado', pressure: 20, hits: [{ share: 0.25, motion: 'h', react: 'light' }, { share: 0.3, motion: 'd', react: 'medium' }, { share: 0.45, motion: 'over', react: 'final' }], icon: 'risky', impact: 'stagger', kind: 'attack', beats: 3, impulse: 2, force: 2, dmg: 15, tags: ['melee'], cooldown: 2,
      desc: 'Força baixa, dano enorme. Ótimo contra quem não vai reagir.' },
    s_parry: { name: 'Aparar', icon: 'parry', kind: 'defense', reaction: 'parry', tags: [],
      desc: 'Tenta aparar o primeiro golpe físico recebido; se der certo, anula e contra-ataca. Não funciona contra magia.' },
    // --- Mago
    m_bolt: { name: 'Projétil Mágico', pressure: 10, hits: [{ share: 0.5, motion: 'proj', react: 'light' }, { share: 0.5, motion: 'proj', react: 'final' }], icon: 'bolt', kind: 'attack', beats: 2, impulse: 2, force: 5, dmg: 7, tags: ['magic'],
      desc: 'Ataque à distância.' },
    m_blast: { name: 'Explosão Arcana', pressure: 20, icon: 'blast', impact: 'knockdown', kind: 'attack', beats: 1, impulse: 3, force: 5, dmg: 13, tags: ['magic'], cooldown: 2,
      desc: 'Magia de dano elevado.' },
    m_weaken: { name: 'Enfraquecimento', pressure: 12, icon: 'weaken', kind: 'attack', beats: 1, impulse: 3, force: 7, dmg: 3, tags: ['magic', 'support'], applies: 'weaken',
      desc: 'Pouco dano, mas o alvo perde 2 de força nos Clashes até o fim da próxima rodada. Age cedo.' },
    m_support: { name: 'Reforço Arcano', postureHeal: 15, icon: 'support', kind: 'support', tags: ['support'],
      desc: 'Um aliado ganha +2 de força na próxima habilidade ofensiva e recupera 15 de Postura. Age cedo.' },
    // --- Lanceiro (alcance e controle de distância)
    l_thrust: { name: 'Estocada', pressure: 12, icon: 'spear', kind: 'attack', beats: 1, impulse: 3, force: 8, dmg: 7, tags: ['melee', 'fast'],
      hits: [{ share: 1, motion: 'thrust', react: 'final' }], desc: 'Estocada rápida de longo alcance. Boa força de Clash.' },
    l_sweep: { name: 'Varredura', pressure: 30, icon: 'sweep', impact: 'push', kind: 'attack', beats: 2, impulse: 2, force: 5, dmg: 9, tags: ['melee'],
      hits: [{ share: 1, motion: 'sweep', react: 'final' }], desc: 'Arco amplo com a haste: empurra o alvo para longe.' },
    l_pierce: { name: 'Investida Perfurante', pressure: 25, icon: 'pierce', impact: 'stagger', kind: 'attack', beats: 1, impulse: 3, force: 5, dmg: 14, tags: ['melee'], cooldown: 2, windup: 1.3,
      hits: [{ share: 1, motion: 'lunge', react: 'final' }], desc: 'Avança e perfura com força. Dano alto, força de Clash moderada.' },
    l_parry: { name: 'Guarda da Lança', icon: 'parry', kind: 'defense', reaction: 'parry', tags: [],
      desc: 'Apara o primeiro golpe físico com a haste e contra-ataca.' },
    // --- Lutador (pressão e múltiplos impactos)
    f_jab: { name: 'Soco Direto', pressure: 10, icon: 'fist', kind: 'attack', beats: 1, impulse: 3, force: 7, dmg: 6, tags: ['melee', 'fast'],
      hits: [{ share: 1, motion: 'punch', react: 'final' }], desc: 'Soco rápido e simples.' },
    f_flurry: { name: 'Sequência de Golpes', pressure: 25, icon: 'flurry', kind: 'attack', beats: 3, impulse: 2, force: 4, dmg: 12, tags: ['melee'],
      hits: [{ share: 0.3, motion: 'punch', react: 'light' }, { share: 0.3, motion: 'punch2', react: 'light' }, { share: 0.4, motion: 'punch', react: 'final' }],
      desc: 'Três socos seguidos (um único Clash). O dano é dividido entre os impactos.' },
    f_upper: { name: 'Golpe Ascendente', pressure: 35, icon: 'upper', impact: 'knockdown', kind: 'attack', beats: 1, impulse: 3, force: 5, dmg: 12, tags: ['melee'], cooldown: 2, windup: 1.3,
      hits: [{ share: 1, motion: 'upper', react: 'final' }], desc: 'De baixo para cima: pode derrubar o alvo.' },
    f_dodge: { name: 'Esquiva Lateral', icon: 'dodge', kind: 'defense', reaction: 'dodge', tags: [],
      desc: 'Esquiva ágil de cada golpe recebido nesta rodada (chance alta).' },
    // --- Arqueira (precisão à distância)
    a_shot: { name: 'Flecha Precisa', pressure: 10, icon: 'arrow', kind: 'attack', beats: 1, impulse: 3, force: 8, dmg: 7, tags: ['ranged'],
      hits: [{ share: 1, motion: 'arrow', react: 'final' }], desc: 'Flecha certeira: boa força de Clash, dano moderado.' },
    a_double: { name: 'Disparo Duplo', pressure: 15, icon: 'arrow2', kind: 'attack', beats: 2, impulse: 2, force: 5, dmg: 10, tags: ['ranged'],
      hits: [{ share: 0.5, motion: 'arrow', react: 'light' }, { share: 0.5, motion: 'arrow', react: 'final' }], desc: 'Duas flechas em sequência; o dano é dividido.' },
    a_pierce: { name: 'Flecha Perfurante', pressure: 20, icon: 'arrowp', impact: 'stagger', kind: 'attack', beats: 1, impulse: 3, force: 5, dmg: 14, tags: ['ranged'], cooldown: 2, windup: 1.6,
      hits: [{ share: 1, motion: 'arrowp', react: 'final' }], desc: 'Tensiona o arco ao máximo: dano alto, preparação longa.' },
    a_evade: { name: 'Recuo Ágil', icon: 'dodge', kind: 'defense', reaction: 'dodge', tags: [],
      desc: 'Salta para trás tentando esquivar de cada golpe.' },
    m_dodge: { name: 'Passo Etéreo', icon: 'dodge', kind: 'defense', reaction: 'dodge', tags: [],
      desc: 'Tenta esquivar de cada golpe recebido nesta rodada.' },

    // --- Brutamontes (prioriza ataques fortes)
    b_smash: { name: 'Esmagar', pressure: 40, windup: 1.5, icon: 'hammer', impact: 'knockdown', kind: 'attack', beats: 1, impulse: 3, force: 5, dmg: 16, tags: ['melee', 'heavy'], cooldown: 2 },
    b_bash: { name: 'Pancada', pressure: 20, icon: 'hammer', kind: 'attack', beats: 2, impulse: 2, force: 8, dmg: 9, tags: ['melee'] },
    b_guard: { name: 'Couraça', icon: 'shield', kind: 'defense', reaction: 'block', tags: [] },
    // --- Duelista (prefere alvos vulneráveis)
    d_flurry: { name: 'Lâmina Veloz', pressure: 15, hits: [{ share: 0.5, motion: 'h', react: 'light' }, { share: 0.5, motion: 'h2', react: 'final' }], icon: 'slash', kind: 'attack', beats: 2, impulse: 2, force: 8, dmg: 7, tags: ['melee', 'fast'] },
    d_lunge: { name: 'Investida Feroz', pressure: 25, icon: 'precise', impact: 'stagger', kind: 'attack', beats: 1, impulse: 3, force: 6, dmg: 12, tags: ['melee'], cooldown: 2 },
    d_parry: { name: 'Contra-guarda', icon: 'parry', kind: 'defense', reaction: 'parry', tags: [] },
    // --- Conjurador (magias e suporte)
    c_ray: { name: 'Raio Sombrio', pressure: 15, icon: 'bolt', kind: 'attack', beats: 2, impulse: 2, force: 6, dmg: 10, tags: ['magic'] },
    c_curse: { name: 'Maldição', pressure: 10, icon: 'weaken', kind: 'attack', beats: 1, impulse: 3, force: 6, dmg: 4, tags: ['magic', 'support'], applies: 'weaken', cooldown: 2 },
    c_veil: { name: 'Véu Sombrio', icon: 'dodge', kind: 'defense', reaction: 'dodge', tags: [] },
  };

  // ATAQUES COMBINADOS — uma ação que consome a ação principal dos dois membros,
  // disputa UM Clash e, se vencer, executa a sequência coreografada.
  // members[0] lidera (é quem aparece como autor da ação).
  //   by: índice do membro que executa o golpe; share: fração do dano total; react: reação daquele impacto
  const COMBOS = {
    combo_ks: { name: 'Investida Conjunta', pressure: 40, kind: 'attack', icon: 'combo', tags: ['melee'], combo: true,
      side: 'ally', members: ['knight', 'swordsman'], beats: 3, impulse: 2, force: 8, dmg: 15, impact: 'knockdown', cooldown: 3,
      desc: 'Cavaleiro + Espadachim: escudo abre a guarda, dois cortes e o golpe final. Gasta a ação dos dois. Força alta e derruba; dano um pouco menor que dois ataques separados.',
      hits: [{ by: 0, share: 0.3, motion: 'bash', react: 'medium' }, { by: 1, share: 0.2, motion: 'h', react: 'light' },
             { by: 1, share: 0.2, motion: 'd', react: 'light' }, { by: 0, share: 0.3, motion: 'over', react: 'final' }] },
    combo_bd: { name: 'Pressão Brutal', pressure: 45, kind: 'attack', icon: 'combo', tags: ['melee'], combo: true,
      side: 'enemy', members: ['brute', 'duelist'], beats: 3, impulse: 2, force: 8, dmg: 17, impact: 'knockdown', cooldown: 3,
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
    knight: { name: 'Cavaleiro', element: 'blue', good: 'Segura a linha de frente, protege aliados frágeis e intercepta golpes.', bestVs: 'Brutamontes (Azul > Vermelho)', limits: 'Lento; pouco dano por ação.', offense: 'Golpes firmes; Golpe Pesado derruba.', defense: 'Bloqueio de 60%, Proteção de aliados, Firmar Guarda recupera Postura.', specialty: 'Proteção e bloqueio', accent: '#7fb0e0', glyph: 'shield', role: 'Defensor', side: 'ally', art: 'knight', posture: 100, formation: 0,
      style: 'Linha de frente: resiste, bloqueia e protege os aliados.',
      hp: 62, spd: 3, interceptReach: 4, blockPower: 0.6,
      skills: ['k_basic', 'k_shield', 'k_heavy', 'k_guard', 'k_protect'],
      trait: 'Intercepta ataques mesmo sendo lento (+4 de alcance). Bloqueio de 60%.' },
    swordsman: { name: 'Espadachim', element: 'red', good: 'Vence Clashes com Golpe Preciso e pune com o Ataque Arriscado.', bestVs: 'Duelista (Vermelho > Amarelo)', limits: 'Postura média; frágil contra Esmagar.', offense: 'Rápido e preciso; vence Clashes com Golpe Preciso.', defense: 'Aparo com contra-ataque.', specialty: 'Aparo e precisão', accent: '#3fc0b0', glyph: 'parry', role: 'Duelista', side: 'ally', art: 'swordsman', posture: 70, formation: 1,
      style: 'Duelos rápidos e precisos; vence Clashes com Golpe Preciso.',
      hp: 44, spd: 8, interceptReach: 0, dodgeSkill: 0.10, parrySkill: 0.10,
      skills: ['s_basic', 's_precise', 's_risky', 's_parry'],
      trait: 'Muito rápido: age cedo e intercepta golpes mais lentos.' },
    mage: { name: 'Mago', element: 'purple', good: 'Dano mágico à distância; Enfraquecimento e Reforço Arcano preparam a equipe.', bestVs: 'Alvos Verdes (Roxo > Verde)', limits: 'Pouca vida e Postura; sofre contra o Duelista.', offense: 'Magia à distância (não pode ser aparada).', defense: 'Esquiva etérea; frágil de perto.', specialty: 'Magia e suporte', accent: '#9f8fff', glyph: 'blast', role: 'Conjurador', side: 'ally', art: 'mage', posture: 40, formation: 2,
      style: 'Magia à distância e preparação: enfraquece inimigos e apoia aliados.',
      hp: 34, spd: 5, interceptReach: 0,
      skills: ['m_bolt', 'm_blast', 'm_weaken', 'm_support', 'm_dodge'],
      trait: 'Frágil. Enfraquecimento e Suporte agem cedo e preparam os Clashes dos aliados.' },

    lancer: { name: 'Lanceiro', element: 'green', good: 'Controla a distância e desgasta Postura com a Varredura.', bestVs: 'Alvos Azuis (Verde > Azul)', limits: 'Perde para magia roxa (Conjurador).', offense: 'Alcance longo; Varredura empurra, Investida desequilibra.', defense: 'Aparo com a haste.', specialty: 'Alcance e controle de distância', accent: '#6fbf7f', glyph: 'spear', role: 'Alcance', side: 'ally', art: 'lancer', posture: 75, formation: 1,
      hp: 50, spd: 7, interceptReach: 2, parrySkill: 0.05,
      skills: ['l_thrust', 'l_sweep', 'l_pierce', 'l_parry'],
      style: 'Disciplinado: mantém o inimigo na ponta da lança e controla a distância.',
      trait: 'Alcance longo (+2 para interceptar). Apara com a haste.' },
    brawler: { name: 'Lutador', element: 'yellow', good: 'Pressão constante: muitos impactos e o Golpe Ascendente derruba.', bestVs: 'Conjurador (Amarelo > Roxo)', limits: 'Alcance curto; sofre contra o Brutamontes.', offense: 'Socos rápidos; Sequência de 3 golpes; Ascendente derruba.', defense: 'Esquiva lateral alta.', specialty: 'Múltiplos impactos e pressão', accent: '#e0705a', glyph: 'fist', role: 'Pressão', side: 'ally', art: 'brawler', posture: 65, formation: 0,
      hp: 48, spd: 9, interceptReach: 0, dodgeSkill: 0.20,
      skills: ['f_jab', 'f_flurry', 'f_upper', 'f_dodge'],
      style: 'Punhos rápidos e pressão constante: muitos impactos e reações no alvo.',
      trait: 'O mais rápido. Especialista em esquiva.' },
    archer: { name: 'Arqueira', element: 'green', good: 'Precisão à distância; Disparo Duplo e Flecha Perfurante de longe.', bestVs: 'Alvos Azuis (Verde > Azul)', limits: 'Frágil de perto; Conjurador tem vantagem.', offense: 'Flechas à distância; Disparo Duplo e Flecha Perfurante.', defense: 'Esquiva e reposicionamento; frágil de perto.', specialty: 'Precisão à distância', accent: '#a9d36f', glyph: 'arrow', role: 'Precisão', side: 'ally', art: 'archer', posture: 45, formation: 2,
      hp: 36, spd: 7, interceptReach: 0, dodgeSkill: 0.15,
      skills: ['a_shot', 'a_double', 'a_pierce', 'a_evade'],
      style: 'Ataca de longe com flechas físicas (podem ser aparadas). Frágil de perto.',
      trait: 'Ataques à distância. Esquiva e reposiciona.' },

    brute: { name: 'Brutamontes', element: 'red', role: 'Força bruta', side: 'enemy', art: 'brute', posture: 110,
      hp: 56, spd: 2, blockPower: 0.5, skills: ['b_smash', 'b_bash', 'b_guard'],
      ai: { prefers: 'strong', defendBelow: 0.35 } },
    duelist: { name: 'Duelista', element: 'yellow', role: 'Lâminas', side: 'enemy', art: 'duelist', posture: 70,
      hp: 40, spd: 7, dodgeSkill: 0.05, parrySkill: 0.05, skills: ['d_lunge', 'd_flurry', 'd_parry'],
      ai: { prefers: 'weak', defendBelow: 0.30 } },
    conjurer: { name: 'Conjurador', element: 'purple', role: 'Magia negra', side: 'enemy', art: 'conjurer', posture: 45,
      hp: 32, spd: 4, skills: ['c_curse', 'c_ray', 'c_veil'],
      ai: { prefers: 'threat', defendBelow: 0.30 } },
  };

  // ELEMENTOS — ciclo fechado: Vermelho > Amarelo > Roxo > Verde > Azul > Vermelho
  const ELEMENTS = {
    red:    { name: 'Vermelho', color: '#e0503c', beats: 'yellow' },
    yellow: { name: 'Amarelo',  color: '#e8c33a', beats: 'purple' },
    purple: { name: 'Roxo',     color: '#a26ae0', beats: 'green' },
    green:  { name: 'Verde',    color: '#5cc46a', beats: 'blue' },
    blue:   { name: 'Azul',     color: '#4c9ee8', beats: 'red' },
  };
  const ELEMENT_ORDER = ['red', 'yellow', 'purple', 'green', 'blue'];
  CONFIG.element = { advantage: 1.2, disadvantage: 0.8 }; // só no dano, por enquanto

  const PARTY = ['knight', 'swordsman', 'mage']; // equipe padrão
  const ROSTER = ['knight', 'swordsman', 'mage', 'lancer', 'brawler', 'archer']; // jogáveis
  const FOES = ['brute', 'duelist', 'conjurer'];
  const AI_THREAT = { mage: 0.6, archer: 0.6, swordsman: 0.4, lancer: 0.3, brawler: 0.35, knight: 0.0 };

  Object.assign(G, { ELEMENTS, ELEMENT_ORDER, CONFIG, REACTIONS, STATUS, SKILLS, COMBOS, AI_COMBO_CHANCE, UNITS, PARTY, ROSTER, FOES, AI_THREAT });
})(typeof window !== 'undefined' ? window : globalThis);
