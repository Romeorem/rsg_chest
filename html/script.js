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
};

function post(name, data = {}) {
    return fetch(`https://${resource}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    }).then((r) => r.json()).catch(() => ({}));
}

const isLockpick = () => state.mode === 'lockpick';

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
        cryptex.classList.add('success');
        showMsg(res.msg || '', 'ok');
        return;
    }
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
            cryptex.classList.add('success');
            render();
            post('lockpickSuccess');
            return;
        }
        setActive(nextUnlocked(i));
        return;
    }

    state.busy = true;
    const res = await post('lockpickFail');
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
    state.open = true;
    state.busy = false;
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
    cryptex.classList.remove('success', 'shake');
    showMsg('');
    buildWheels();
    app.classList.remove('hidden');
    if (isLockpick()) startTimer();
}

function close() {
    state.open = false;
    stopTimer();
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
