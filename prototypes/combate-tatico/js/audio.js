// =====================================================================
// AUDIO MANAGER — efeitos sintetizados com Web Audio API (sem arquivos
// externos: nada de licença a verificar). Cada som varia levemente de
// tom/intensidade para golpes seguidos não soarem idênticos.
// Só começa a tocar depois da primeira interação do usuário.
// =====================================================================
(function (G) {
  'use strict';
  const STORE = 'duelo-audio';

  class AudioManager {
    constructor() {
      this.ctx = null; this.unlocked = false;
      this.settings = { master: 0.7, sfx: 0.8, muted: false };
      try { Object.assign(this.settings, JSON.parse(localStorage.getItem(STORE) || '{}')); } catch (e) { /* sem storage */ }
      this._last = {};
      const unlock = () => this.unlock();
      window.addEventListener('pointerdown', unlock, { once: false });
      window.addEventListener('keydown', unlock, { once: false });
    }
    unlock() {
      if (this.unlocked && this.ctx && this.ctx.state === 'running') return;
      try {
        this.ctx = this.ctx || new (window.AudioContext || window.webkitAudioContext)();
        this.out = this.out || this.ctx.createGain();
        if (!this.out._connected) {
          // compressor suave evita picos quando vários sons coincidem
          const comp = this.ctx.createDynamicsCompressor();
          comp.threshold.value = -16; comp.ratio.value = 4;
          this.out.connect(comp); comp.connect(this.ctx.destination); this.out._connected = true;
          this.noise = this._noiseBuffer();
        }
        this.ctx.resume();
        this.unlocked = true;
        this._applyVolume();
      } catch (e) { this.unlocked = false; }
    }
    set(key, value) {
      this.settings[key] = value;
      try { localStorage.setItem(STORE, JSON.stringify(this.settings)); } catch (e) { /* ok */ }
      this._applyVolume();
    }
    _applyVolume() { if (this.out) this.out.gain.value = this.settings.muted ? 0 : this.settings.master * this.settings.sfx; }
    _noiseBuffer() {
      const len = this.ctx.sampleRate * 1.0, buf = this.ctx.createBuffer(1, len, this.ctx.sampleRate), d = buf.getChannelData(0);
      for (let i = 0; i < len; i++) d[i] = Math.random() * 2 - 1;
      return buf;
    }

    // ---------------------------------------------------- primitivas
    _env(g, t, a, peak, d) { g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(peak, t + a); g.gain.exponentialRampToValueAtTime(0.0001, t + a + d); }
    _noise(t, dur, { type = 'bandpass', f0 = 1200, f1 = f0, q = 1, peak = 0.4, a = 0.005 } = {}) {
      const c = this.ctx, src = c.createBufferSource(), flt = c.createBiquadFilter(), g = c.createGain();
      src.buffer = this.noise; flt.type = type; flt.Q.value = q;
      flt.frequency.setValueAtTime(f0, t); flt.frequency.exponentialRampToValueAtTime(Math.max(40, f1), t + dur);
      this._env(g, t, a, peak, dur);
      src.connect(flt); flt.connect(g); g.connect(this.out);
      src.start(t, Math.random() * 0.5); src.stop(t + a + dur + 0.05);
    }
    _tone(t, dur, { type = 'sine', f0 = 440, f1 = f0, peak = 0.3, a = 0.004 } = {}) {
      const c = this.ctx, o = c.createOscillator(), g = c.createGain();
      o.type = type; o.frequency.setValueAtTime(f0, t); o.frequency.exponentialRampToValueAtTime(Math.max(20, f1), t + dur);
      this._env(g, t, a, peak, dur);
      o.connect(g); g.connect(this.out); o.start(t); o.stop(t + a + dur + 0.05);
    }

    // ---------------------------------------------------- catálogo
    play(name, { vol = 1, pitch = 1 } = {}) {
      if (!this.unlocked || !this.ctx || this.settings.muted) return;
      // evita empilhar o mesmo som no mesmo instante
      const now = this.ctx.currentTime;
      if (this._last[name] && now - this._last[name] < 0.03) return;
      this._last[name] = now;
      const v = vol * (0.85 + Math.random() * 0.3), p = pitch * (0.92 + Math.random() * 0.16), t = now + 0.005;
      const N = (dur, o) => this._noise(t, dur, Object.assign({}, o, { peak: (o.peak || 0.4) * v, f0: (o.f0 || 1200) * p, f1: (o.f1 || o.f0 || 1200) * p }));
      const T = (dur, o, dt = 0) => this._tone(t + dt, dur, Object.assign({}, o, { peak: (o.peak || 0.3) * v, f0: (o.f0 || 440) * p, f1: (o.f1 || o.f0 || 440) * p }));
      switch (name) {
        case 'swish': N(0.16, { f0: 900, f1: 3200, q: 1.4, peak: 0.25, a: 0.03 }); break;              // movimento de lâmina
        case 'slash': N(0.12, { f0: 2600, f1: 900, q: 0.9, peak: 0.4 }); T(0.12, { type: 'triangle', f0: 180, f1: 90, peak: 0.25 }); break;
        case 'shield': T(0.2, { type: 'sine', f0: 110, f1: 55, peak: 0.55 }); N(0.08, { type: 'lowpass', f0: 900, peak: 0.35 }); break;
        case 'punch': T(0.1, { type: 'sine', f0: 150, f1: 60, peak: 0.5 }); N(0.05, { type: 'lowpass', f0: 1400, peak: 0.3 }); break;
        case 'thrust': N(0.1, { f0: 1600, f1: 4200, q: 2, peak: 0.25, a: 0.01 }); T(0.08, { type: 'triangle', f0: 240, f1: 120, peak: 0.2 }, 0.06); break;
        case 'heavy': T(0.35, { type: 'sine', f0: 80, f1: 38, peak: 0.6 }); N(0.2, { type: 'lowpass', f0: 600, f1: 200, peak: 0.4 }); break;
        case 'clash':  // choque metálico: parciais inarmônicas
          [1, 2.76, 5.4, 8.9].forEach((m, i) => T(0.5 - i * 0.08, { type: 'sine', f0: 520 * m, peak: 0.16 / (i + 1) }));
          N(0.08, { type: 'highpass', f0: 3000, peak: 0.35 }); break;
        case 'clashWin': T(0.18, { type: 'triangle', f0: 523, peak: 0.16 }); T(0.26, { type: 'triangle', f0: 784, peak: 0.16 }, 0.08); break;
        case 'clashLose': T(0.3, { type: 'triangle', f0: 330, f1: 220, peak: 0.16 }); break;
        case 'block': T(0.14, { type: 'square', f0: 140, f1: 90, peak: 0.12 }); N(0.06, { type: 'bandpass', f0: 2200, q: 3, peak: 0.3 }); break;
        case 'dodge': N(0.22, { f0: 500, f1: 1800, q: 0.8, peak: 0.18, a: 0.04 }); break;
        case 'parry': [1, 2.4, 4.1].forEach((m, i) => T(0.6, { type: 'sine', f0: 1250 * m, peak: 0.14 / (i + 1) })); N(0.05, { type: 'highpass', f0: 4000, peak: 0.3 }); break;
        case 'magicCharge': T(0.5, { type: 'sine', f0: 300, f1: 900, peak: 0.12, a: 0.15 }); T(0.5, { type: 'sine', f0: 305, f1: 910, peak: 0.08, a: 0.15 }); break;
        case 'magicCast': T(0.22, { type: 'sawtooth', f0: 900, f1: 300, peak: 0.08 }); N(0.2, { f0: 2000, f1: 600, q: 4, peak: 0.15 }); break;
        case 'magicHit': T(0.35, { type: 'sine', f0: 200, f1: 60, peak: 0.4 }); N(0.3, { type: 'lowpass', f0: 2400, f1: 300, peak: 0.35 }); break;
        case 'whoosh': N(0.3, { f0: 400, f1: 1600, q: 1.2, peak: 0.12, a: 0.08 }); break;          // projétil em voo
        case 'bowDraw': T(0.35, { type: 'sawtooth', f0: 70, f1: 110, peak: 0.05, a: 0.1 }); N(0.35, { f0: 600, f1: 900, q: 6, peak: 0.06, a: 0.1 }); break;
        case 'bowRelease': T(0.25, { type: 'triangle', f0: 220, f1: 180, peak: 0.25 }); N(0.06, { type: 'highpass', f0: 2500, peak: 0.2 }); break;
        case 'arrowHit': N(0.05, { type: 'bandpass', f0: 1800, q: 2, peak: 0.35 }); T(0.08, { type: 'sine', f0: 260, f1: 120, peak: 0.3 }); break;
        case 'thud': T(0.3, { type: 'sine', f0: 70, f1: 40, peak: 0.55 }); N(0.25, { type: 'lowpass', f0: 500, f1: 150, peak: 0.35 }); break; // queda
        case 'defeat': T(0.6, { type: 'triangle', f0: 220, f1: 110, peak: 0.15 }); break;
        // interface
        case 'uiSelect': T(0.07, { type: 'triangle', f0: 660, peak: 0.1 }); break;
        case 'uiSkill': T(0.08, { type: 'triangle', f0: 880, peak: 0.09 }); break;
        case 'uiConnect': T(0.08, { type: 'triangle', f0: 660, peak: 0.1 }); T(0.12, { type: 'triangle', f0: 990, peak: 0.1 }, 0.06); N(0.05, { type: 'highpass', f0: 5000, peak: 0.08 }); break;
        case 'uiCancel': T(0.12, { type: 'triangle', f0: 440, f1: 300, peak: 0.08 }); break;
        case 'uiConfirm': [523, 659, 784].forEach((f, i) => T(0.18, { type: 'triangle', f0: f, peak: 0.09 }, i * 0.06)); break;
      }
    }
  }

  G.SFX = new AudioManager();
})(window);
