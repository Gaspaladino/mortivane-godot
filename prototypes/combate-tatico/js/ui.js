// =====================================================================
// INTERFACE (DOM) — muda conforme a fase. Não decide nada do combate.
// =====================================================================
(function (G) {
  'use strict';
  const { SKILLS, REACTIONS, STATUS } = G;
  const $ = sel => document.querySelector(sel);
  const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
  const TAG_LABEL = { melee: 'corpo a corpo', magic: 'magia', heavy: 'pesado', fast: 'rápido' };
  const pct = c => Math.round(c * 100) + '%';

  function statusChips(u) {
    return Object.keys(u.statuses).map(k => STATUS[k] ?
      `<span class="chip" style="--c:${STATUS[k].color}" title="${STATUS[k].desc}">${STATUS[k].name}</span>` : '').join('');
  }
  function hpBar(u) {
    const r = Math.max(0, u.hp / u.maxHp);
    return `<div class="hp"><div class="hpfill ${r < 0.3 ? 'low' : ''}" style="width:${r * 100}%"></div><span>${u.hp}/${u.maxHp}</span></div>`;
  }
  function skillTags(sk) {
    const t = sk.tags.map(x => TAG_LABEL[x]).join(' · ');
    return t + (sk.unblockable ? ' · ignora bloqueio' : '') + (sk.cooldown ? ` · recarga ${sk.cooldown - 1}r` : '');
  }

  const UI = {
    setTop(battle, phaseLabel, resolving) {
      $('#round').textContent = `Rodada ${battle.round}`;
      $('#phase').textContent = phaseLabel;
      $('#btn-skip').disabled = !resolving;
      document.body.classList.toggle('resolving', !!resolving);
    },
    setSpeed(s) {
      document.querySelectorAll('[data-speed]').forEach(b => b.classList.toggle('on', +b.dataset.speed === s));
    },

    // ------------------------------------------------------------ PLANEJAMENTO
    renderPlan(battle, state, cb) {
      const panel = $('#panel'); panel.innerHTML = '';
      const row = el('div', 'cards');
      const enemies = battle.units.filter(u => u.side === 'enemy');
      for (const u of battle.units.filter(x => x.side === 'ally')) {
        const plan = state.plans[u.id] || {};
        const card = el('div', 'card' + (u.hp <= 0 ? ' dead' : '') + (state.active === u.id ? ' active' : ''));
        card.innerHTML = `<div class="card-h"><b>${u.name}</b> <small>${u.def.role} · Vel ${u.def.spd}</small></div>${hpBar(u)}<div class="chips">${statusChips(u)}</div>`;
        if (u.hp > 0) {
          const sk = el('div', 'skills');
          for (const id of u.def.skills) {
            const s = SKILLS[id], ready = battle.skillReady(u, id);
            const b = el('button', 'skill' + (plan.skillId === id ? ' sel' : ''),
              `<b>${s.name}</b><small>Poder ${s.power} · ${skillTags(s)}</small>${ready ? '' : `<em>recarga: ${u.cooldowns[id]}</em>`}`);
            b.disabled = !ready;
            b.title = s.desc;
            b.onmouseenter = () => cb.hint(`<b>${s.name}</b> — ${s.desc}`);
            b.onclick = () => cb.pickSkill(u.id, id);
            sk.appendChild(b);
          }
          card.appendChild(sk);
          const tg = el('div', 'targets', '<span>Alvo:</span>');
          for (const e of enemies) {
            const prev = plan.skillId && e.hp > 0 ? battle.previewHit(u, e, SKILLS[plan.skillId]) : null;
            const b = el('button', 'target' + (plan.targetId === e.id ? ' sel' : ''), `${e.name}${prev != null ? ` <small>≈${prev}</small>` : ''}`);
            b.disabled = e.hp <= 0 || !plan.skillId;
            b.onclick = () => cb.pickTarget(u.id, e.id);
            tg.appendChild(b);
          }
          card.appendChild(tg);
          card.appendChild(el('div', 'trait', u.def.trait));
          card.onclick = (ev) => { if (ev.target === card || ev.target.closest('.card-h')) cb.activate(u.id); };
        }
        row.appendChild(card);
      }
      panel.appendChild(row);

      // ordem prevista
      const side = el('div', 'side');
      const order = state.order;
      side.innerHTML = `<div class="sh">Ordem prevista (velocidade)</div>` + (order.length ? '<ol>' + order.map(p => {
        const a = battle.unit(p.attackerId), t = battle.unit(p.targetId);
        return `<li><b>${a.name}</b> · ${SKILLS[p.skillId].name} → ${t.name}</li>`;
      }).join('') + '</ol>' : '<p class="muted">Escolha habilidade e alvo de cada personagem.</p>') +
        `<div class="sh">Inimigos</div>` + enemies.map(e => `<div class="foe ${e.hp <= 0 ? 'dead' : ''}"><b>${e.name}</b> <small>Vel ${e.def.spd}</small>${hpBar(e)}<div class="chips">${statusChips(e)}</div></div>`).join('');
      const hint = el('div', 'hint', state.hint || 'Clique num personagem e depois num inimigo (também funciona clicando na arena).');
      hint.id = 'hint';
      side.appendChild(hint);
      const ok = el('button', 'confirm', 'Confirmar ataques ▶');
      ok.disabled = !state.complete;
      ok.onclick = cb.confirm;
      side.appendChild(ok);
      panel.appendChild(side);
    },
    hint(html) { const h = $('#hint'); if (h) h.innerHTML = html; },

    // ------------------------------------------------------------ DEFESA
    renderDefense(battle, intents, choices, cb) {
      const panel = $('#panel'); panel.innerHTML = '';
      const list = el('div', 'intents');
      const knight = battle.units.find(u => u.def.canProtect);
      const protectIdx = Object.keys(choices).find(k => choices[k].protect);
      intents.forEach((it, i) => {
        const a = battle.unit(it.attackerId), t = battle.unit(it.targetId), sk = SKILLS[it.skillId];
        const ch = choices[i];
        const row = el('div', 'intent');
        const fx = sk.applies ? ` · aplica <span style="color:${STATUS[sk.applies].color}">${STATUS[sk.applies].name}</span>` : '';
        row.innerHTML = `<div class="ih"><span class="ord">${i + 1}</span><b class="foe-n">${a.name}</b> — ${sk.name} <small>(${skillTags(sk)}${fx})</small> → <b>${t.name}</b> <small>${t.hp}/${t.maxHp} PV · golpe ≈${battle.previewHit(a, t, sk)}</small></div>`;
        const opts = el('div', 'opts');
        const options = battle.reactionOptions(t, a, sk);
        options.forEach((o, oi) => {
          const r = REACTIONS[o.kind];
          const b = el('button', 'react' + (!ch.protect && ch.reaction === o.kind ? ' sel' : ''),
            `<b>${r.name}</b><small>${o.kind === 'dodge' || o.kind === 'parry' ? 'chance ' + pct(o.chance) + ' · ' : ''}dano esp. ≈${Math.round(o.expected)}${oi === 0 ? ' · padrão' : ''}</small>`);
          b.title = r.desc;
          b.disabled = !!ch.protect;
          b.onclick = () => cb.pickReaction(i, o.kind);
          opts.appendChild(b);
        });
        if (sk.tags.includes('magic') && t.def.reactions.includes('parry')) opts.appendChild(el('span', 'note', 'magia não pode ser aparada'));
        if (knight && knight !== t) {
          const can = knight.hp > 0 && !battle.protectUsed && (protectIdx == null || +protectIdx === i);
          const exp = knight.hp > 0 ? Math.round(battle.expectedDamage(a, knight, sk, 'block')) : 0;
          const b = el('button', 'react protect' + (ch.protect ? ' sel' : ''),
            `<b>🛡 Cavaleiro protege</b><small>${knight.hp > 0 ? `recebe ≈${exp} bloqueando · 1x por rodada` : 'Cavaleiro caído'}</small>`);
          b.disabled = !can;
          b.onclick = () => cb.toggleProtect(i);
          opts.appendChild(b);
        }
        row.appendChild(opts);
        list.appendChild(row);
      });
      panel.appendChild(list);
      const side = el('div', 'side');
      side.innerHTML = `<div class="sh">Ofensiva inimiga</div><p class="muted">Os inimigos revelaram suas intenções. Cada personagem já tem uma defesa padrão — mude se quiser. Esquivar e Aparar são apostas; Bloquear é seguro. O Cavaleiro pode interceptar <b>um</b> ataque por rodada.</p>` +
        `<div class="sh">Seu grupo</div>` + battle.units.filter(u => u.side === 'ally').map(u => `<div class="foe mate ${u.hp <= 0 ? 'dead' : ''}"><b>${u.name}</b>${hpBar(u)}<div class="chips">${statusChips(u)}</div></div>`).join('');
      const ok = el('button', 'confirm', 'Resolver ofensiva ▶');
      ok.onclick = cb.confirm;
      side.appendChild(ok);
      panel.appendChild(side);
    },

    renderWaiting(text) {
      $('#panel').innerHTML = `<div class="waiting">${text}</div>`;
    },

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
