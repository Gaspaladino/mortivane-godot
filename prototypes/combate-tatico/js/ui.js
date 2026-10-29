// =====================================================================
// INTERFACE (DOM) — planejamento coletivo + prévia de Clashes.
// Só exibe; quem decide é a lógica (combat.js).
// =====================================================================
(function (G) {
  'use strict';
  const { SKILLS, STATUS } = G;
  const $ = sel => document.querySelector(sel);
  const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
  const TAG = { melee: 'corpo a corpo', magic: 'magia', heavy: 'lento', fast: 'rápido', support: 'prioridade' };
  const CAT = { favorable: ['Favorável', '#6fd890'], even: ['Equilibrado', '#ffd36a'], unfavorable: ['Desfavorável', '#ff7a6a'] };
  const pct = x => Math.round(x * 100) + '%';

  function chips(u) {
    return Object.keys(u.statuses).map(k => STATUS[k] && u.statuses[k] !== 'used' ?
      `<span class="chip" style="--c:${STATUS[k].color}" title="${STATUS[k].desc}">${STATUS[k].name}</span>` : '').join('');
  }
  function hpBar(u) {
    const r = Math.max(0, u.hp / u.maxHp);
    return `<div class="hp"><div class="hpfill ${r < 0.3 ? 'low' : ''}" style="width:${r * 100}%"></div><span>${u.hp}/${u.maxHp}</span></div>`;
  }
  function skillLine(battle, u, sk) {
    if (sk.kind === 'attack') return `Força <b>${sk.force}</b> · Dano <b>${sk.dmg}</b> · Vel ${battle.actionSpeed(u, sk)}${sk.tags.filter(t => TAG[t] && t !== 'melee').map(t => ' · ' + TAG[t]).join('')}`;
    if (sk.kind === 'support') return `Suporte · Vel ${battle.actionSpeed(u, sk)}`;
    return 'Defesa · antes de tudo';
  }
  const catTag = (cat, odds) => `<span class="cat" style="--c:${CAT[cat][1]}">${CAT[cat][0]}</span>` +
    (odds ? ` <small>vence ${pct(odds.win)} · empata ${pct(odds.tie)}</small>` : '');

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

    // ------------------------------------------------------------ PLANEJAMENTO
    // view: { choices, active, plan, preview }
    renderPlan(battle, view, cb) {
      const panel = $('#panel'); panel.innerHTML = '';
      const row = el('div', 'cards');
      const intents = battle.intents;
      for (const u of battle.units.filter(x => x.side === 'ally')) {
        const ch = view.choices[u.id] || {};
        const card = el('div', 'card' + (u.hp <= 0 ? ' dead' : '') + (view.active === u.id ? ' active' : ''));
        card.innerHTML = `<div class="card-h"><b>${u.name}</b> <small>${u.def.role} · Vel ${u.def.spd}</small></div>${hpBar(u)}<div class="chips">${chips(u)}</div>`;
        if (u.hp > 0) {
          const threats = intents.filter(it => it.targetId === u.id && SKILLS[it.skillId].kind === 'attack');
          if (threats.length) card.appendChild(el('div', 'threat', threats.map(it => {
            const sk = SKILLS[it.skillId];
            return `⚠ <b>${battle.unit(it.actorId).name}</b>: ${sk.name} <small>F${sk.force} · D${sk.dmg}${sk.applies ? ' · enfraquece' : ''}</small>`;
          }).join('<br>')));
          const skills = el('div', 'skills');
          for (const id of u.def.skills) {
            const sk = SKILLS[id], ready = battle.skillReady(u, id);
            const b = el('button', 'skill' + (ch.skillId === id ? ' sel' : '') + ' k-' + sk.kind,
              `<b>${sk.name}</b><small>${skillLine(battle, u, sk)}</small>${ready ? '' : `<em>recarga: ${u.cooldowns[id]}</em>`}`);
            b.disabled = !ready; b.title = sk.desc;
            b.onmouseenter = () => cb.hint(`<b>${sk.name}</b> — ${sk.desc}`);
            b.onclick = () => cb.pickSkill(u.id, id);
            skills.appendChild(b);
          }
          card.appendChild(skills);
          if (ch.skillId) card.appendChild(this._targets(battle, u, ch, view, cb));
          card.appendChild(el('div', 'trait', u.def.trait));
          card.onclick = ev => { if (ev.target === card || ev.target.closest('.card-h')) cb.activate(u.id); };
        }
        row.appendChild(card);
      }
      panel.appendChild(row);
      panel.appendChild(this._side(battle, view, cb));
    },

    _targets(battle, u, ch, view, cb) {
      const sk = SKILLS[ch.skillId];
      const box = el('div', 'targets');
      if (sk.kind === 'defense') { box.innerHTML = '<span class="muted">Postura própria — sem alvo.</span>'; return box; }
      box.appendChild(el('span', null, sk.kind === 'attack' ? 'Alvo:' : 'Aliado:'));
      const pool = battle.units.filter(t => sk.kind === 'attack' ? t.side === 'enemy' : (t.side === 'ally' && t !== u));
      for (const t of pool) {
        let tag = '';
        if (sk.kind === 'attack' && t.hp > 0) {
          const it = battle.intents.find(i => i.actorId === t.id);
          if (it && it.targetId === u.id && SKILLS[it.skillId].kind === 'attack') tag = ' <small class="tclash">⚔ Clash</small>';
          else if (it && SKILLS[it.skillId].kind === 'attack') tag = ` <small>mira ${battle.unit(it.targetId).name}</small>`;
          else if (it) tag = ' <small>defende</small>';
        }
        const b = el('button', 'target' + (ch.targetId === t.id ? ' sel' : ''), t.name + tag);
        b.disabled = t.hp <= 0;
        b.onclick = () => cb.pickTarget(u.id, t.id);
        box.appendChild(b);
      }
      // prévia do Clash / interceptação deste personagem
      const mine = view.plan && view.plan.actions.find(a => a.actorId === u.id);
      if (mine && sk.kind === 'attack') {
        const pv = view.preview.find(e => e.type === 'clash' && (e.a.id === mine.id || e.b.id === mine.id));
        const info = mine.interceptInfo;
        const pre = el('div', 'preview');
        if (pv) {
          const meFirst = pv.a.id === mine.id;
          const other = meFirst ? pv.b : pv.a;
          const fMe = meFirst ? pv.fa : pv.fb, fOt = meFirst ? pv.fb : pv.fa;
          const odds = meFirst ? pv.odds : { win: pv.odds.lose, tie: pv.odds.tie };
          pre.innerHTML = `<b>${pv.link.type === 'intercept' ? 'Interceptação' : 'Clash'}</b> contra ${battle.unit(other.actorId).name} (${SKILLS[other.skillId].name})<br>` +
            `Força ${fMe} + (0–3) × ${fOt} + (0–3) → ${catTag(battle.category(odds.win), odds)}`;
        } else if (info) {
          pre.innerHTML = `Sem Clash: ${battle.unit(mine.targetId).name} vai atacar ${battle.unit(info.protects).name}.`;
        } else pre.innerHTML = `Ataque sem oposição: dano ${sk.dmg} (se o alvo não bloquear/esquivar/aparar).`;
        if (info) {
          const ok = info.valid;
          const tb = el('button', 'react protect' + (ch.intercept ? ' sel' : ''),
            `<b>⚔ Interceptar ataque contra ${battle.unit(info.protects).name}</b><small>${ok ? `válido: Vel ${info.mySpeed}${info.reach ? ' +' + info.reach + ' alcance' : ''} ≥ ${info.enemySpeed}` : `lento demais: Vel ${info.mySpeed}${info.reach ? ' +' + info.reach : ''} < ${info.enemySpeed}`}</small>`);
          tb.disabled = !ok;
          tb.onclick = () => cb.toggleIntercept(u.id);
          pre.appendChild(tb);
        }
        box.appendChild(pre);
      }
      return box;
    },

    _side(battle, view, cb) {
      const side = el('div', 'side');
      let html = '<div class="sh">Ordem prevista</div>';
      if (view.preview && view.preview.length) {
        html += '<ol class="order">' + view.preview.map(ev => this._orderLine(battle, ev)).join('') + '</ol>';
      }
      html += '<div class="sh">Inimigos</div>' + battle.units.filter(u => u.side === 'enemy').map(e => {
        const it = battle.intents.find(i => i.actorId === e.id);
        const sk = it && SKILLS[it.skillId];
        return `<div class="foe ${e.hp <= 0 ? 'dead' : ''}"><b>${e.name}</b> <small>${sk ? (sk.kind === 'attack' ? `→ ${battle.unit(it.targetId).name}: ${sk.name} (F${sk.force}, D${sk.dmg}, Vel ${battle.actionSpeed(e, sk)})` : `${sk.name} (defesa)`) : ''}</small>${hpBar(e)}<div class="chips">${chips(e)}</div></div>`;
      }).join('');
      side.innerHTML = html;
      const hint = el('div', 'hint', view.hint || 'Escolha uma ação para cada personagem. Atacar quem ataca você gera um Clash; você também pode interceptar ataques contra aliados.');
      hint.id = 'hint';
      side.appendChild(hint);
      const ok = el('button', 'confirm', 'Confirmar rodada ▶');
      ok.disabled = !view.complete;
      ok.onclick = cb.confirm;
      side.appendChild(ok);
      return side;
    },

    _orderLine(battle, ev) {
      const n = id => battle.unit(id).name, sn = id => SKILLS[id].name;
      if (ev.type === 'stances') return `<li class="o-def">Defesas: ${ev.actions.map(a => SKILLS[a.skillId].kind === 'protect' ? `${n(a.actorId)} protege ${n(a.targetId)}` : `${n(a.actorId)} (${sn(a.skillId)})`).join(', ')}</li>`;
      if (ev.type === 'support') return `<li class="o-sup">${n(ev.a.actorId)}: ${sn(ev.a.skillId)} → ${n(ev.a.targetId)}</li>`;
      if (ev.type === 'clash') {
        const ally = ev.a.side === 'ally' ? ev.a : ev.b, foe = ally === ev.a ? ev.b : ev.a;
        const p = ally === ev.a ? ev.odds.win : ev.odds.lose;
        return `<li class="o-clash">⚔ ${ev.link.type === 'intercept' ? 'Interceptação' : 'Clash'}: ${n(ally.actorId)} (${sn(ally.skillId)}) × ${n(foe.actorId)} (${sn(foe.skillId)}) ${catTag(battle.category(p))}</li>`;
      }
      const a = ev.a, t = battle.unit(a.targetId), sk = SKILLS[a.skillId];
      if (a.side === 'enemy') {
        const prot = t.side === 'ally' && this._protector(battle, ev, t);
        return `<li class="o-foe">${n(a.actorId)}: ${sn(a.skillId)} → ${t.name} <small>(sem oposição, D${sk.dmg}${prot ? ` · ${prot}` : ''})</small></li>`;
      }
      return `<li>${n(a.actorId)}: ${sn(a.skillId)} → ${t.name} <small>(sem oposição, D${sk.dmg})</small></li>`;
    },
    _protector(battle, ev, t) { return this._defenseNote && this._defenseNote[t.id]; },

    hint(html) { const h = $('#hint'); if (h) h.innerHTML = html; },

    renderEnd(result, onRestart) {
      const o = $('#overlay');
      o.innerHTML = `<div class="end ${result}"><h1>${result === 'victory' ? 'VITÓRIA' : 'DERROTA'}</h1><p>${result === 'victory' ? 'Os três inimigos caíram.' : 'Seu grupo foi derrotado.'}</p></div>`;
      const b = el('button', 'confirm', 'Reiniciar batalha ↻');
      b.onclick = onRestart;
      o.firstChild.appendChild(b);
      o.classList.add('show');
    },
    hideEnd() { $('#overlay').classList.remove('show'); $('#overlay').innerHTML = ''; },
  };

  G.UI = UI;
})(window);
