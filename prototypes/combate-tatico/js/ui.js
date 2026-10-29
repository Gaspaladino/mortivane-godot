// =====================================================================
// INTERFACE (DOM) — barra compacta. A seleção acontece na arena
// (planner.js); aqui ficam só: dica, ordem prevista, ações e confirmar.
// =====================================================================
(function (G) {
  'use strict';
  const { SKILLS } = G;
  const $ = sel => document.querySelector(sel);
  const CAT = { favorable: ['Favorável', '#6fd890'], even: ['Equilibrado', '#ffd36a'], unfavorable: ['Desfavorável', '#ff7a6a'] };

  const UI = {
    CAT,
    setTop(battle, phaseLabel, resolving) {
      $('#round').textContent = `Rodada ${battle.round}`;
      $('#phase').textContent = phaseLabel;
      $('#btn-skip').disabled = !resolving;
      document.body.classList.toggle('resolving', !!resolving);
    },
    setSpeed(s) { document.querySelectorAll('[data-speed]').forEach(b => b.classList.toggle('on', +b.dataset.speed === s)); },
    renderWaiting(text) { $('#panel').innerHTML = `<div class="waiting">${text}</div>`; },

    // view: { choices, plan, preview, complete, hint }
    renderBar(battle, view, onConfirm) {
      const n = id => battle.unit(id).name, sn = id => SKILLS[id].name;
      const who = a => [a.actorId, ...(a.partners || [])].map(n).join(' + ');
      const chips = (view.preview || []).map((ev, i) => {
        let cls = '', txt = '';
        if (ev.type === 'stances') { cls = 'o-def'; txt = '🛡 ' + ev.actions.map(a => SKILLS[a.skillId].kind === 'protect' ? `${n(a.actorId)} protege ${n(a.targetId)}` : `${n(a.actorId)}: ${sn(a.skillId)}`).join(' · '); }
        else if (ev.type === 'support') { cls = 'o-sup'; txt = `${n(ev.a.actorId)} ✚ ${n(ev.a.targetId)}`; }
        else if (ev.type === 'clash') {
          const ally = ev.a.side === 'ally' ? ev.a : ev.b, foe = ally === ev.a ? ev.b : ev.a;
          const c = CAT[battle.category(ally === ev.a ? ev.odds.win : ev.odds.lose)];
          cls = 'o-clash'; txt = `⚔ ${who(ally)} × ${who(foe)} <b style="color:${c[1]}">${c[0]}</b>`;
        } else {
          const a = ev.a, sk = SKILLS[a.skillId];
          cls = a.side === 'enemy' ? 'o-foe' : 'o-ally';
          txt = `${who(a)} → ${n(a.targetId)} <small>${sk.name} · D${sk.dmg}${a.side === 'enemy' ? (UI.defenseNote[a.targetId] ? ' · ' + UI.defenseNote[a.targetId] : ' · sem defesa') : ''}</small>`;
        }
        return `<span class="ochip ${cls}"><i>${i + 1}</i>${txt}</span>`;
      }).join('');
      const done = battle.alive('ally').filter(u => view.choices[u.id]).length; // parceiro de combinação conta
      $('#panel').innerHTML = `<div class="bar-hint">${view.hint}</div><div class="order-strip">${chips}</div>` +
        `<button class="confirm" ${view.complete ? '' : 'disabled'}>Executar rodada ▶ <small>${done}/${battle.alive('ally').length}</small></button>`;
      $('#panel .confirm').onclick = onConfirm;
    },
    defenseNote: {},

    renderEnd(result, onRestart) {
      const o = $('#overlay');
      o.innerHTML = `<div class="end ${result}"><h1>${result === 'victory' ? 'VITÓRIA' : 'DERROTA'}</h1><p>${result === 'victory' ? 'Os três inimigos caíram.' : 'Seu grupo foi derrotado.'}</p></div>`;
      const b = document.createElement('button'); b.className = 'confirm'; b.textContent = 'Reiniciar batalha ↻';
      b.onclick = onRestart;
      o.firstChild.appendChild(b);
      o.classList.add('show');
    },
    hideEnd() { $('#overlay').classList.remove('show'); $('#overlay').innerHTML = ''; },
  };

  G.UI = UI;
})(window);
