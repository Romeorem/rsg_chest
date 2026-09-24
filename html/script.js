const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'rsg_chest';

const $ = (id) => document.getElementById(id);
const app = $('app');
const cryptex = $('cryptex');
const wheelsEl = $('wheels');
const msgEl = $('msg');

const state = {
    open: false,
    busy: false,
    length: 4,
    steps: [],
    stepIndex: 0,
    values: [],
    digits: [],
    active: 0,
    text: {},
};

function post(name, data = {}) {
    return fetch(`https://${resource}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    }).then((r) => r.json()).catch(() => ({}));
}

function buildWheels() {
    wheelsEl.innerHTML = '';
    state.digits = new Array(state.length).fill(0);
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
    setActive(0);
    render();
}

function render() {
    const h = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--digit-h')) || 74;
    wheelsEl.querySelectorAll('.wheel').forEach((w, i) => {
        w.querySelector('.strip').style.transform = `translateY(${-state.digits[i] * h}px)`;
        w.classList.toggle('active', i === state.active);
    });
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

function turn(i, dir) {
    if (state.busy) return;
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

async function validate() {
    if (state.busy) return;
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

function cancel() {
    if (!state.open) return;
    post('cancel');
    close();
}

function open(data) {
    state.open = true;
    state.busy = false;
    state.length = Math.min(Math.max(parseInt(data.length, 10) || 4, 3), 8);
    state.steps = data.steps && data.steps.length ? data.steps : ['Code'];
    state.stepIndex = 0;
    state.values = [];
    state.text = data.text || {};

    $('title').textContent = data.title || '';
    $('btn-reset').textContent = state.text.reset || 'Remettre';
    $('btn-cancel').setAttribute('aria-label', state.text.cancel || 'Annuler');
    $('help').textContent = state.text.help || '';
    cryptex.classList.remove('success', 'shake');
    showMsg('');
    buildWheels();
    app.classList.remove('hidden');
}

function close() {
    state.open = false;
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
