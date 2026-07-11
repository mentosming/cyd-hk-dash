/* CYD-DASH — live screen replica.
 *
 * Faithful to the firmware: same 320x240 canvas, same palette, same layout
 * coordinates as firmware/src/ui/*.cpp, and — where it matters — the same
 * DATA. Tolls are computed here with a straight port of
 * firmware/src/model/toll_engine.cpp, so the price on this page is the price
 * you'd actually pay right now. Journey times are the live Transport
 * Department feed (its CORS header lets a browser read it directly).
 */

const S = {
  page: 0,
  autoAdvance: true,
  lastInteract: 0,
  journey: {},        // slot -> {minutes, colour}
  prevJourney: {},
  journeyAt: null,
  holidays: new Set(),
  fuel: null,         // [brand][type] cents
  fuelAt: null,
  metersState: 'idle', // idle | scanning | done
};

/* ---------- Hong Kong time ---------- */
function hk() {
  // HKT is UTC+8 year-round.
  return new Date(Date.now() + (8 * 60 + new Date().getTimezoneOffset()) * 60000);
}
const pad = n => String(n).padStart(2, '0');

/* ---------- Toll engine (port of firmware/src/model/toll_engine.cpp) ------- */
const T = (h, m) => h * 3600 + m * 60;
// {from, to, v0, dir}  — toll(t) = v0 + dir*2*floor((t-from)/120)
const PROFILE_W = [ // 西隧, Mon–Sat
  [0, T(7, 30), 20, 0], [T(7, 30), T(8, 8), 22, +1], [T(8, 8), T(10, 15), 60, 0],
  [T(10, 15), T(10, 43), 58, -1], [T(10, 43), T(16, 30), 30, 0],
  [T(16, 30), T(16, 58), 32, +1], [T(16, 58), T(19, 0), 60, 0],
  [T(19, 0), T(19, 38), 58, -1], [T(19, 38), 86400, 20, 0],
];
const PROFILE_C = [ // 紅隧 / 東隧, Mon–Sat
  [0, T(7, 30), 20, 0], [T(7, 30), T(7, 48), 22, +1], [T(7, 48), T(10, 15), 40, 0],
  [T(10, 15), T(10, 23), 38, -1], [T(10, 23), T(16, 30), 30, 0],
  [T(16, 30), T(16, 38), 32, +1], [T(16, 38), T(19, 0), 40, 0],
  [T(19, 0), T(19, 18), 38, -1], [T(19, 18), 86400, 20, 0],
];
const PROFILE_S = [ // Sundays & public holidays, all three
  [0, T(10, 11), 20, 0], [T(10, 11), T(10, 13), 21, 0], [T(10, 13), T(10, 15), 23, 0],
  [T(10, 15), T(19, 15), 25, 0], [T(19, 15), T(19, 17), 23, 0],
  [T(19, 17), T(19, 19), 21, 0], [T(19, 19), 86400, 20, 0],
];

const evalSeg = (s, t) => s[3] === 0 ? s[2] : s[2] + s[3] * 2 * Math.floor((t - s[0]) / 120);
const segAt = (p, t) => p.find(s => t >= s[0] && t < s[1]);

function toll(crossing, sec, sunPH) {
  const p = sunPH ? PROFILE_S : (crossing === 'W' ? PROFILE_W : PROFILE_C);
  const seg = segAt(p, sec);
  if (!seg) return { dollars: 20, next: 86400, nextDollars: 20 };
  const dollars = evalSeg(seg, sec);

  let next = seg[1];
  if (seg[3] !== 0) {
    const step = seg[0] + (Math.floor((sec - seg[0]) / 120) + 1) * 120;
    if (step < seg[1]) next = step;
  }
  if (next >= 86400) return { dollars, next: 86400, nextDollars: dollars };

  // skip value-neutral boundaries
  let nd = evalSeg(segAt(p, next), next);
  let guard = 0;
  while (nd === dollars && next < 86400 && guard++ < 40) {
    const deeper = toll(crossing, next, sunPH);
    next = deeper.next; nd = deeper.nextDollars;
  }
  return { dollars, next, nextDollars: nd };
}

/** Imminent → count down; hours away → give the wall-clock time.
 *  ("283分後" is technically true and completely useless.) */
function nextChangeText(r, sec) {
  if (r.next >= 86400) return '';
  const mins = Math.ceil((r.next - sec) / 60);
  if (mins < 60) return `${mins}分後 $${r.nextDollars}`;
  return `${pad(Math.floor(r.next / 3600))}:${pad(Math.floor((r.next % 3600) / 60))} $${r.nextDollars}`;
}

function isSunOrPH(d) {
  if (d.getDay() === 0) return true;
  const key = `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}`;
  return S.holidays.has(key);
}

/* ---------- Data ---------- */
const SLOTS = { // slot -> [LOCATION_ID, DESTINATION_ID]
  1: ['H2', 'CH'], 2: ['H2', 'EH'], 3: ['H2', 'WH'],
  4: ['K03', 'CH'], 5: ['K03', 'EH'], 6: ['K03', 'WH'],
  7: ['SJ1', 'LRT'], 8: ['SJ2', 'TCT'], 9: ['SJ2', 'TSCA'],
};
const NA = 255, CONGESTION = 254, CLOSED = 253;

async function fetchJourney() {
  try {
    const r = await fetch('https://resource.data.one.gov.hk/td/jss/Journeytimev2.xml',
                          { cache: 'no-store' });
    const xml = new DOMParser().parseFromString(await r.text(), 'text/xml');
    const byPair = {};
    for (const rec of xml.getElementsByTagName('jtis_journey_time')) {
      const g = t => rec.getElementsByTagName(t)[0]?.textContent?.trim() ?? '';
      byPair[`${g('LOCATION_ID')}|${g('DESTINATION_ID')}`] =
        { type: g('JOURNEY_TYPE'), data: g('JOURNEY_DATA'), colour: g('COLOUR_ID') };
    }
    S.prevJourney = S.journey;
    const out = {};
    for (const [slot, [loc, dest]] of Object.entries(SLOTS)) {
      const f = byPair[`${loc}|${dest}`];
      if (!f) { out[slot] = { minutes: NA, colour: 0 }; continue; }
      const colour = ['1', '2', '3'].includes(f.colour) ? +f.colour : 0;
      let minutes = NA;
      if (f.type === '1' && +f.data >= 0) minutes = Math.min(+f.data, 250);
      else if (f.type === '2' && f.data === '1') minutes = CONGESTION;
      else if (f.type === '2' && f.data === '3') minutes = CLOSED;
      out[slot] = { minutes, colour };
    }
    S.journey = out;
    S.journeyAt = Date.now();
    render();
  } catch (e) {
    /* offline / blocked — the screen keeps showing "--", exactly like the real
       device before a phone connects. */
  }
}

async function loadStatic() {
  try {
    const h = await (await fetch('data/holidays.json')).json();
    S.holidays = new Set(h);
  } catch {}
  try {
    const f = await (await fetch('data/fuel.json')).json();
    const BRANDS = ['Sinopec', 'PetroChina', 'Caltex', 'Esso', 'Shell'];
    const TYPES = ['Standard Petrol', 'Premium Petrol', 'Diesel'];
    const cents = Array.from({ length: 5 }, () => [null, null, null]);
    for (const entry of f.prices) {
      const t = TYPES.indexOf(entry.type.en);
      if (t < 0) continue;
      for (const p of entry.prices) {
        const b = BRANDS.indexOf(p.vendor.en);
        if (b >= 0) cents[b][t] = Math.round(parseFloat(p.price) * 100);
      }
    }
    S.fuel = cents;
    S.fuelAt = new Date(f.fetchedAt);
  } catch {}
}

/* ---------- Rendering ---------- */
const PAGES = ['過海隧道', '主要幹道', '附近咪錶', '油價'];
const TABS = ['過海', '幹道', '咪錶', '油價'];

function minutesHTML(m, colour, big) {
  const cls = big ? 'num num-lg' : 'num';
  if (m === undefined || m === NA) return `<span class="${cls} dim">--</span>`;
  if (m === CONGESTION) return `<span class="cjk red">擠塞</span>`;
  if (m === CLOSED) return `<span class="cjk red">封閉</span>`;
  const c = { 1: 'red', 2: 'amber', 3: 'green' }[colour] || '';
  return `<span class="${cls} ${c}">${m}</span>`;
}

function arrowHTML(slot) {
  const now = S.journey[slot]?.minutes, prev = S.prevJourney[slot]?.minutes;
  if (now === undefined || prev === undefined || now >= CLOSED || prev >= CLOSED) return '';
  const d = now - prev;
  if (d >= 2) return '<span class="arrow red">↑</span>';
  if (d <= -2) return '<span class="arrow green">↓</span>';
  return '';
}

function pageHarbour() {
  const d = hk();
  const sec = d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds();
  const sunPH = isSunOrPH(d);
  const tunnels = [
    { name: '紅隧', code: 'C', toKln: 1, toHK: 4 },
    { name: '東隧', code: 'C', toKln: 2, toHK: 5 },
    { name: '西隧', code: 'W', toKln: 3, toHK: 6 },
  ];
  return tunnels.map((t, i) => {
    const r = toll(t.code, sec, sunPH);
    const nextTxt = nextChangeText(r, sec);
    return `
      <div class="card harbour" style="top:${2 + i * 58}px;height:54px">
        <div class="hname cjk">${t.name}</div>
        <div class="dir" style="left:62px">
          <div class="lbl cjk">港→九</div>
          <div class="mrow">${minutesHTML(S.journey[t.toKln]?.minutes, S.journey[t.toKln]?.colour)}${arrowHTML(t.toKln)}</div>
        </div>
        <div class="dir" style="left:142px">
          <div class="lbl cjk">九→港</div>
          <div class="mrow">${minutesHTML(S.journey[t.toHK]?.minutes, S.journey[t.toHK]?.colour)}${arrowHTML(t.toHK)}</div>
        </div>
        <div class="pill">$${r.dollars}</div>
        <div class="next cjk">${nextTxt}</div>
      </div>`;
  }).join('');
}

function pageRoutes() {
  const routes = [
    { name: '獅隧', slot: 7 }, { name: '大老山', slot: 8 }, { name: '青沙', slot: 9 },
  ];
  return routes.map((r, i) => `
    <div class="card route" style="top:${2 + i * 58}px;height:54px">
      <div class="rname cjk">${r.name}</div>
      <div class="rsub cjk">往九龍</div>
      <div class="rarrow">${arrowHTML(r.slot)}</div>
      <div class="rmin">${minutesHTML(S.journey[r.slot]?.minutes, S.journey[r.slot]?.colour, true)}</div>
      <div class="rsuf cjk">分鐘</div>
    </div>`).join('');
}

// Sample results — the real device gets these from the phone's GPS + the TD
// occupancy feed; a landing page has neither, so this shows the layout.
const SAMPLE_METERS = [
  { street: '謝斐道', dist: 120, lpp: 120, vacant: 3, total: 16 },
  { street: '駱克道', dist: 210, lpp: 60, vacant: 0, total: 12 },
  { street: '軒尼詩道', dist: 260, lpp: 120, vacant: 5, total: 8 },
  { street: '盧押道', dist: 340, lpp: 30, vacant: 2, total: 6 },
];

function pageMeters() {
  const scanning = S.metersState === 'scanning';
  const rows = S.metersState === 'done' ? SAMPLE_METERS : [];
  const status = scanning ? '搜尋中...'
    : S.metersState === 'done' ? '更新 0分前' : '撳掣搜尋空位';
  return `
    <button class="scan cjk ${scanning ? 'busy' : ''}" id="scanBtn">${scanning ? '搜尋中' : '掃一掃'}</button>
    <div class="mstatus cjk">${status}</div>
    ${rows.map((r, i) => `
      <div class="card mrow2" style="top:${44 + i * 33}px;height:31px">
        <div class="mname cjk">${r.street}</div>
        <div class="mdist cjk">${r.dist}米</div>
        <div class="mlpp cjk">${r.lpp}分</div>
        <div class="mvac num ${r.vacant ? 'green' : 'red'}">${r.vacant}</div>
        <div class="mtot cjk">/${r.total}</div>
      </div>`).join('')}`;
}

function pageFuel() {
  const brands = ['中石化', '中國石油', '加德士', '埃索', '蜆殼'];
  const types = ['無鉛', '特級', '柴油'];
  if (!S.fuel) return `<div class="mstatus cjk" style="top:70px">冇數據</div>`;
  const cheapest = types.map((_, t) =>
    Math.min(...S.fuel.map(b => b[t]).filter(v => v != null)));
  const age = S.fuelAt
    ? `${Math.max(1, Math.round((Date.now() - S.fuelAt) / 3600000))}時前` : '';
  return `
    <div class="fhead">
      <span class="fage cjk">${age}</span>
      ${types.map((t, i) => `<span class="ftype cjk" style="left:${82 + i * 77}px">${t}</span>`).join('')}
    </div>
    ${brands.map((b, bi) => `
      <div class="card frow" style="top:${22 + bi * 31}px;height:29px">
        <div class="fbrand cjk">${b}</div>
        ${types.map((_, t) => {
          const c = S.fuel[bi][t];
          const best = c != null && c === cheapest[t];
          return `<span class="fprice num ${best ? 'teal' : ''} ${c == null ? 'dim' : ''}"
                        style="left:${76 + t * 77}px">${c == null ? '--' : '$' + (c / 100).toFixed(2)}</span>`;
        }).join('')}
      </div>`).join('')}`;
}

function render() {
  const d = hk();
  const connected = S.journeyAt !== null;
  const ageMin = S.journeyAt ? Math.floor((Date.now() - S.journeyAt) / 60000) : null;

  document.getElementById('title').textContent = PAGES[S.page];
  document.getElementById('clock').textContent = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  document.getElementById('btdot').className = connected ? 'btdot on' : 'btdot';
  document.getElementById('updated').textContent =
    ageMin === null ? '等待數據' : `更新 ${ageMin}分前`;
  document.getElementById('updated').className =
    'updated cjk' + (ageMin !== null && ageMin > 5 ? ' amber' : '');

  const body = [pageHarbour, pageRoutes, pageMeters, pageFuel][S.page]();
  const page = document.getElementById('page');
  page.className = 'page p' + S.page;
  page.innerHTML = body;

  document.querySelectorAll('.tab').forEach((el, i) => {
    el.className = 'tab cjk' + (i === S.page ? ' active' : '');
  });

  const btn = document.getElementById('scanBtn');
  if (btn) btn.onclick = () => { touch(); runScan(); };
}

/* ---------- Interaction ---------- */
function touch() { S.lastInteract = Date.now(); }

function go(i) {
  S.page = (i + 4) % 4;
  touch();
  render();
  // Show, don't tell: the first time the meter page appears, run the scan for
  // the visitor so they see the result rather than an empty screen.
  if (S.page === 2 && S.metersState === 'idle') setTimeout(runScan, 700);
}

function runScan() {
  if (S.metersState === 'scanning') return;
  S.metersState = 'scanning';
  render();
  setTimeout(() => { S.metersState = 'done'; render(); }, 1400);
}

function init() {
  document.querySelectorAll('.tab').forEach((el, i) => {
    el.addEventListener('click', () => go(i));
  });
  // Swipe, like the real thing
  let x0 = null;
  const scr = document.getElementById('screen');
  scr.addEventListener('pointerdown', e => { x0 = e.clientX; });
  scr.addEventListener('pointerup', e => {
    if (x0 === null) return;
    const dx = e.clientX - x0; x0 = null;
    if (Math.abs(dx) > 40) go(S.page + (dx < 0 ? 1 : -1));
  });

  // ?p=N pins a page (used by the screenshot tooling and handy for linking)
  const forced = new URLSearchParams(location.search).get('p');
  if (forced !== null) { S.page = Math.max(0, Math.min(3, +forced)); S.autoAdvance = false; }

  loadStatic().then(render);
  fetchJourney();
  // Landing straight on the meter page (?p=2, or a deep link) should still run
  // the scan — otherwise the visitor stares at an empty list.
  if (S.page === 2) setTimeout(runScan, 700);
  setInterval(fetchJourney, 120000);     // the TD feed moves every 2 min
  setInterval(render, 1000);             // clock + toll countdown
  setInterval(() => {                    // idle auto-advance
    if (!S.autoAdvance) return;
    if (Date.now() - S.lastInteract < 12000) return;
    go(S.page + 1);
    S.lastInteract = 0;                  // keep cycling
  }, 5000);
  render();
}

document.addEventListener('DOMContentLoaded', init);
