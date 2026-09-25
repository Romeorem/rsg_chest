const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'rsg_chest';

const $ = (id) => document.getElementById(id);
const app = $('app');
const cryptex = $('cryptex');
const wheelsEl = $('wheels');
const msgEl = $('msg');

const state = {
    open: false,
    busy: false,
    mode: 'code',        // 'code' | 'lockpick'
    length: 4,
    steps: [],
    stepIndex: 0,
    values: [],
    digits: [],
    active: 0,
    text: {},
    // crochetage
    secret: [],
    locked: [],
    lockOrder: [],
    deadline: 0,
    duration: 0,
    timer: null,
    succeeded: false,
    closeTimer: null,
};

function post(name, data = {}) {
    return fetch(`https://${resource}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    }).then((r) => r.json()).catch(() => ({}));
}

const isLockpick = () => state.mode === 'lockpick';

// ---------------------------------------------------------------- sons (synthétisés, aucun fichier)
const Sound = {
    ctx: null,
    volume: 0.5,
    get() {
        if (this.volume <= 0) return null;
        try {
            if (!this.ctx) this.ctx = new (window.AudioContext || window.webkitAudioContext)();
            if (this.ctx.state === 'suspended') this.ctx.resume();
        } catch (e) { return null; }
        return this.ctx;
    },
    noise(dur, freq, gain, when = 0) {
        const ctx = this.get(); if (!ctx) return;
        const t = ctx.currentTime + when;
        const buf = ctx.createBuffer(1, Math.ceil(ctx.sampleRate * dur), ctx.sampleRate);
        const data = buf.getChannelData(0);
        for (let i = 0; i < data.length; i++) data[i] = (Math.random() * 2 - 1) * (1 - i / data.length);
        const src = ctx.createBufferSource(); src.buffer = buf;
        const filter = ctx.createBiquadFilter(); filter.type = 'bandpass'; filter.frequency.value = freq; filter.Q.value = 2;
        const g = ctx.createGain(); g.gain.value = gain * this.volume;
        src.connect(filter).connect(g).connect(ctx.destination);
        src.start(t);
    },
    tone(freq, dur, gain, type = 'sine', when = 0, endFreq) {
        const ctx = this.get(); if (!ctx) return;
        const t = ctx.currentTime + when;
        const osc = ctx.createOscillator(); osc.type = type;
        osc.frequency.setValueAtTime(freq, t);
        if (endFreq) osc.frequency.exponentialRampToValueAtTime(endFreq, t + dur);
        const g = ctx.createGain();
        g.gain.setValueAtTime(gain * this.volume, t);
        g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
        osc.connect(g).connect(ctx.destination);
        osc.start(t); osc.stop(t + dur + 0.02);
    },
    tick() { this.noise(0.025, 3200, 0.35); },
    click(strong) { this.noise(0.03, strong ? 1800 : 2400, strong ? 0.9 : 0.45); if (strong) this.tone(900, 0.05, 0.12, 'square'); },
    lock() { this.noise(0.06, 900, 0.7); this.tone(160, 0.12, 0.35, 'triangle', 0, 70); },
    fail() { this.tone(110, 0.25, 0.5, 'sawtooth', 0, 45); this.noise(0.12, 500, 0.5); },
    open() {
        this.lock();
        this.noise(0.25, 1400, 0.35, 0.12);
        this.tone(1320, 0.7, 0.12, 'sine', 0.2);
        this.tone(1980, 0.5, 0.06, 'sine', 0.22);
    },
};

function buildWheels() {
    wheelsEl.innerHTML = '';
    for (let i = 0; i < state.length; i++) {
        const wheel = document.createElement('div');
        wheel.className = 'wheel';

        const up = document.createElement('button');
        up.className = 'arrow';
        up.type = 'button';
        up.textContent = '▲';
        up.addEventListener('click', () => { setActive(i); turn(i, 1); });

        const win = document.createElement('div');
        win.className = 'window';
        const strip = document.createElement('div');
        strip.className = 'strip';
        for (let d = 0; d < 10; d++) {
            const s = document.createElement('span');
            s.textContent = d;
            strip.appendChild(s);
        }
        win.appendChild(strip);
        win.addEventListener('click', () => setActive(i));
        win.addEventListener('wheel', (e) => {
            e.preventDefault();
            setActive(i);
            turn(i, e.deltaY < 0 ? 1 : -1);
        }, { passive: false });

        const down = document.createElement('button');
        down.className = 'arrow';
        down.type = 'button';
        down.textContent = '▼';
        down.addEventListener('click', () => { setActive(i); turn(i, -1); });

        wheel.append(up, win, down);
        wheelsEl.appendChild(wheel);
    }
    render();
}

function feedback(i) {
    if (!isLockpick() || state.locked[i] || i !== state.active) return '';
    const diff = Math.abs(state.digits[i] - state.secret[i]);
    const dist = Math.min(diff, 10 - diff);
    if (dist === 0) return 'click-strong';
    if (dist === 1) return 'click-weak';
    return '';
}

function render() {
    const h = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--digit-h')) || 74;
    wheelsEl.querySelectorAll('.wheel').forEach((w, i) => {
        w.querySelector('.strip').style.transform = `translateY(${-state.digits[i] * h}px)`;
        w.classList.toggle('active', i === state.active);
        w.classList.toggle('locked', !!state.locked[i]);
        const win = w.querySelector('.window');
        win.classList.remove('click-weak', 'click-strong');
        const fb = feedback(i);
        if (fb) win.classList.add(fb);
    });

    if (isLockpick()) {
        $('step').textContent = `${state.locked.filter(Boolean).length} / ${state.length}`;
        $('btn-validate').textContent = state.text.lock || 'Bloquer';
        return;
    }
    const total = state.steps.length;
    const label = state.steps[state.stepIndex] || '';
    $('step').textContent = total > 1
        ? `${(state.text.step || 'Étape %d / %d').replace('%d', state.stepIndex + 1).replace('%d', total)} · ${label}`
        : label;
    $('btn-validate').textContent = state.stepIndex < total - 1
        ? (state.text.next || 'Suivant')
        : (state.text.validate || 'Valider');
}

function setActive(i) {
    state.active = (i + state.length) % state.length;
    render();
}

function nextUnlocked(from, dir = 1) {
    for (let n = 1; n <= state.length; n++) {
        const i = (from + dir * n + state.length * 2) % state.length;
        if (!state.locked[i]) return i;
    }
    return from;
}

function turn(i, dir) {
    if (state.busy || state.locked[i]) return;
    state.digits[i] = (state.digits[i] + dir + 10) % 10;
    const fb = feedback(i);
    if (fb) Sound.click(fb === 'click-strong'); else Sound.tick();
    clearMsg();
    render();
}

function resetDigits() {
    state.digits = new Array(state.length).fill(0);
    setActive(0);
}

function showMsg(text, type) {
    msgEl.textContent = text || '';
    msgEl.className = 'msg' + (type ? ' ' + type : '');
}
function clearMsg() { if (!state.busy) showMsg(''); }

function shake() {
    cryptex.classList.remove('shake');
    void cryptex.offsetWidth;
    cryptex.classList.add('shake');
}

// ---------------------------------------------------------------- code
async function validate() {
    if (state.busy) return;
    if (isLockpick()) return lockWheel();

    state.values[state.stepIndex] = state.digits.join('');
    if (state.stepIndex < state.steps.length - 1) {
        state.stepIndex++;
        resetDigits();
        return;
    }

    state.busy = true;
    const res = await post('submit', { values: state.values });
    state.busy = false;

    if (res && res.ok) {
        succeed(res.msg || '');
        return;
    }
    Sound.fail();
    shake();
    showMsg(res && res.msg ? res.msg : '', 'bad');
    state.values = [];
    state.stepIndex = 0;
    resetDigits();
}

// ---------------------------------------------------------------- crochetage
async function lockWheel() {
    const i = state.active;
    if (state.locked[i]) return;

    if (state.digits[i] === state.secret[i]) {
        state.locked[i] = true;
        state.lockOrder.push(i);
        if (state.locked.filter(Boolean).length === state.length) {
            state.busy = true;
            stopTimer();
            render();
            succeed('');
            post('lockpickSuccess');
            return;
        }
        Sound.lock();
        setActive(nextUnlocked(i));
        return;
    }

    state.busy = true;
    const res = await post('lockpickFail');
    Sound.fail();
    shake();
    showMsg(res && res.msg ? res.msg : '', 'bad');
    if (res && res.broken) {
        stopTimer();
        return; // le client Lua ferme l'interface
    }
    state.busy = false;
    // le crochet glisse : la dernière molette bloquée se libère
    const last = state.lockOrder.pop();
    if (last !== undefined) {
        state.locked[last] = false;
        state.digits[last] = Math.floor(Math.random() * 10);
        setActive(last);
    } else {
        render();
    }
}

function succeed(msg) {
    state.succeeded = true;
    cryptex.classList.add('success');
    showMsg(msg, 'ok');
    Sound.open();
}

function startTimer() {
    stopTimer();
    const bar = $('timer-bar');
    state.timer = setInterval(() => {
        const left = state.deadline - Date.now();
        bar.style.transform = `scaleX(${Math.max(left, 0) / state.duration})`;
        if (left <= 0) {
            stopTimer();
            if (!state.busy) {
                state.busy = true;
                shake();
                post('lockpickTimeout');
            }
        }
    }, 100);
}

function stopTimer() {
    if (state.timer) clearInterval(state.timer);
    state.timer = null;
}

// ---------------------------------------------------------------- ouverture
function cancel() {
    if (!state.open) return;
    stopTimer();
    post('cancel');
    close();
}

function open(data) {
    clearTimeout(state.closeTimer);
    state.open = true;
    state.busy = false;
    state.succeeded = false;
    Sound.volume = typeof data.volume === 'number' ? data.volume : 0.5;
    state.mode = data.mode === 'lockpick' ? 'lockpick' : 'code';
    state.text = data.text || {};
    state.values = [];
    state.stepIndex = 0;
    state.locked = [];
    state.lockOrder = [];

    if (isLockpick()) {
        state.secret = (data.digits || [0, 0, 0, 0]).map((d) => parseInt(d, 10) || 0);
        state.length = state.secret.length;
        // départ aléatoire, jamais sur le bon chiffre
        state.digits = state.secret.map((d) => (d + 2 + Math.floor(Math.random() * 7)) % 10);
        state.locked = new Array(state.length).fill(false);
        state.duration = Math.max(parseInt(data.time, 10) || 45, 5) * 1000;
        state.deadline = Date.now() + state.duration;
        state.steps = [];
    } else {
        state.length = Math.min(Math.max(parseInt(data.length, 10) || 4, 3), 8);
        state.steps = data.steps && data.steps.length ? data.steps : ['Code'];
        state.digits = new Array(state.length).fill(0);
    }
    state.active = 0;

    $('title').textContent = data.title || '';
    $('btn-reset').textContent = state.text.reset || 'Remettre';
    $('btn-reset').classList.toggle('hidden', isLockpick());
    $('timer').classList.toggle('hidden', !isLockpick());
    $('timer-bar').style.transform = 'scaleX(1)';
    $('btn-cancel').setAttribute('aria-label', state.text.cancel || 'Annuler');
    $('help').textContent = isLockpick() ? (state.text.lockHelp || '') : (state.text.help || '');
    cryptex.classList.remove('success', 'shake', 'opening');
    showMsg('');
    buildWheels();
    app.classList.remove('hidden');
    if (isLockpick()) startTimer();
}

function close() {
    state.open = false;
    stopTimer();
    clearTimeout(state.closeTimer);
    if (state.succeeded && !window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
        // le verrou coulisse et le couvercle s'ouvre avant de disparaître
        cryptex.classList.add('opening');
        state.closeTimer = setTimeout(() => app.classList.add('hidden'), 750);
        return;
    }
    app.classList.add('hidden');
}

$('btn-validate').addEventListener('click', validate);
$('btn-reset').addEventListener('click', () => { if (!state.busy) { resetDigits(); clearMsg(); } });
$('btn-cancel').addEventListener('click', cancel);

window.addEventListener('message', (e) => {
    const data = e.data || {};
    if (data.action === 'open') open(data);
    else if (data.action === 'close') close();
});

window.addEventListener('keydown', (e) => {
    if (!state.open) return;
    const k = e.key;
    if (k === 'Escape') { e.preventDefault(); cancel(); return; }
    if (state.busy) return;

    if (isLockpick()) {
        if (k === ' ' || k === 'Enter') { e.preventDefault(); lockWheel(); }
        else if (k === 'ArrowUp') { e.preventDefault(); turn(state.active, 1); }
        else if (k === 'ArrowDown') { e.preventDefault(); turn(state.active, -1); }
        else if (k === 'ArrowLeft') { e.preventDefault(); setActive(nextUnlocked(state.active, -1)); }
        else if (k === 'ArrowRight' || k === 'Tab') { e.preventDefault(); setActive(nextUnlocked(state.active, 1)); }
        return;
    }

    if (/^[0-9]$/.test(k)) {
        state.digits[state.active] = parseInt(k, 10);
        clearMsg();
        setActive(state.active + 1);
    } else if (k === 'ArrowUp') { e.preventDefault(); turn(state.active, 1); }
    else if (k === 'ArrowDown') { e.preventDefault(); turn(state.active, -1); }
    else if (k === 'ArrowLeft') { e.preventDefault(); setActive(state.active - 1); }
    else if (k === 'ArrowRight' || k === 'Tab') { e.preventDefault(); setActive(state.active + 1); }
    else if (k === 'Backspace') { e.preventDefault(); state.digits[state.active] = 0; setActive(state.active - 1); }
    else if (k === 'Enter') { e.preventDefault(); validate(); }
});
