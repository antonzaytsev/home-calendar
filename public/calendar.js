'use strict';

const DAYS_IN_PAST = 1;
const DAY_OPTIONS = [3, 4, 5, 7];
const DEFAULT_TOTAL_DAYS = 4;
const MINUTES_PER_DAY = 24 * 60;
const MIN_EVENT_MINUTES = 20;
const TICK_MS = 60 * 1000;
const FALLBACK_REFRESH_MS = 5 * 60 * 1000;
const REQUEST_TIMEOUT_MS = 15 * 1000;
const UPDATES_SILENCE_MS = 70 * 1000;
const IDLE_SCROLL_MS = 2 * 60 * 1000;
const IDLE_RETURN_TODAY_MS = 10 * 60 * 1000;
const STORAGE_KEY = 'calendar-settings';
const RELOAD_KEY = 'calendar-reloaded-at';
const MIN_RELOAD_INTERVAL_MS = 60 * 1000;

const MONTHS = ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'];
const WEEKDAYS = ['ВС', 'ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ'];

const state = {
  anchor: startOfDay(new Date()),
  totalDays: DEFAULT_TOTAL_DAYS,
  events: {},
  loadedAt: null,
  error: null,
  stale: false,
  request: null,
  lastFetchAt: 0,
  today: dateKey(new Date()),
  lastInteraction: Date.now(),
  updates: null,
  lastUpdateMessage: 0,
};

const $ = (id) => document.getElementById(id);

// ---- Dates ----

function startOfDay(date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function addDays(date, days) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() + days);
}

function pad(value) {
  return String(value).padStart(2, '0');
}

function dateKey(date) {
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

function parseDateKey(value) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value || '');
  if (!match) return null;
  const date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
  return dateKey(date) === value ? date : null;
}

function formatTime(date) {
  return `${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function minutesSinceMidnight(date) {
  return date.getHours() * 60 + date.getMinutes();
}

// 7 days: the Monday-Sunday week containing the anchor; otherwise start one day before it
function visibleDates() {
  const first = state.totalDays === 7
    ? addDays(state.anchor, -((state.anchor.getDay() + 6) % 7))
    : addDays(state.anchor, -DAYS_IN_PAST);
  return Array.from({ length: state.totalDays }, (_, i) => addDays(first, i));
}

function isTodayVisible() {
  return visibleDates().some((date) => dateKey(date) === state.today);
}

// ---- Rendering ----

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (char) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[char]));
}

function renderTitle(dates) {
  const first = dates[0];
  const last = dates[dates.length - 1];
  let title;
  if (first.getFullYear() !== last.getFullYear()) {
    title = `${MONTHS[first.getMonth()]} ${first.getFullYear()} – ${MONTHS[last.getMonth()]} ${last.getFullYear()}`;
  } else if (first.getMonth() !== last.getMonth()) {
    title = `${MONTHS[first.getMonth()]}-${MONTHS[last.getMonth()]} ${first.getFullYear()}`;
  } else {
    title = `${MONTHS[first.getMonth()]} ${first.getFullYear()}`;
  }
  $('title').textContent = title;
}

function dayClasses(date) {
  const day = date.getDay();
  return [
    dateKey(date) === state.today ? 'today' : '',
    day === 0 || day === 6 ? 'weekend' : '',
  ].join(' ');
}

function renderDayHeaders(dates) {
  $('day-headers').innerHTML = '<div></div>' + dates.map((date) =>
    `<div class="day-header ${dayClasses(date)}">${WEEKDAYS[date.getDay()]} ${date.getDate()}</div>`
  ).join('');
}

function renderAllDayRow(dates) {
  const columns = dates.map((date) => {
    const events = (state.events[dateKey(date)] || []).filter((event) => event.all_day);
    const html = events.map((event) => {
      const past = event.end <= state.today ? ' past' : '';
      return `<div class="all-day-event${past}" title="${escapeHtml(event.summary)}">${escapeHtml(event.summary)}</div>`;
    }).join('');
    return { html, count: events.length, today: dateKey(date) === state.today };
  });

  const row = $('all-day-row');
  row.hidden = !columns.some((column) => column.count > 0);
  row.innerHTML = '<div class="all-day-label">Весь день</div>' + columns.map((column) =>
    `<div class="all-day-column${column.today ? ' today' : ''}">${column.html}</div>`
  ).join('');
}

// Assign overlapping events to side-by-side columns, per cluster of overlaps
function layoutTimedEvents(events, dayStart) {
  const dayEnd = dayStart.getTime() + MINUTES_PER_DAY * 60000;
  const items = events.map((event) => {
    const start = new Date(event.start);
    const end = new Date(event.end);
    const top = Math.max(0, (start - dayStart) / 60000);
    const bottom = Math.min(MINUTES_PER_DAY, (Math.min(end, dayEnd) - dayStart) / 60000);
    const height = Math.max(bottom - top, MIN_EVENT_MINUTES);
    return { event, start, end, top, height, visualEnd: top + height };
  }).sort((a, b) => a.top - b.top || b.height - a.height);

  let cluster = [];
  let columnEnds = [];
  let clusterEnd = -1;
  const finishCluster = () => {
    cluster.forEach((item) => { item.columns = columnEnds.length; });
    cluster = [];
    columnEnds = [];
  };

  for (const item of items) {
    if (item.top >= clusterEnd) finishCluster();
    let column = columnEnds.findIndex((end) => end <= item.top);
    if (column === -1) {
      column = columnEnds.length;
      columnEnds.push(item.visualEnd);
    } else {
      columnEnds[column] = item.visualEnd;
    }
    item.column = column;
    cluster.push(item);
    clusterEnd = Math.max(clusterEnd, item.visualEnd);
  }
  finishCluster();
  return items;
}

function renderTimedEvents(date, now) {
  const events = (state.events[dateKey(date)] || []).filter((event) => !event.all_day);
  return layoutTimedEvents(events, date).map((item) => {
    const past = item.end < now ? ' past' : '';
    let position = `top:${item.top + 1}px;height:${item.height - 2}px;`;
    if (item.columns > 1) {
      const width = 98 / item.columns;
      position += `left:${1 + item.column * width}%;width:${width}%;`;
    }
    const summary = escapeHtml(item.event.summary);
    return `<div class="event${past}" style="${position}" title="${summary}">` +
             `<div class="event-title">${summary}</div>` +
             `<div class="event-time">${formatTime(item.start)} - ${formatTime(item.end)}</div>` +
           '</div>';
  }).join('');
}

function renderGrid(dates) {
  const now = new Date();
  let html = '<div class="time-column">';
  for (let hour = 0; hour < 24; hour++) html += `<div class="time-slot">${hour}:00</div>`;
  html += '</div>';

  for (const date of dates) {
    const isToday = dateKey(date) === state.today;
    const timeLine = isToday ? `<div class="current-time-line" style="top:${minutesSinceMidnight(now)}px"></div>` : '';
    html += `<div class="day-column ${dayClasses(date)}">${timeLine}${renderTimedEvents(date, now)}</div>`;
  }
  $('grid').innerHTML = html;
}

function renderStatus() {
  const status = $('status');
  const parts = [];
  if (state.loadedAt) {
    parts.push(`Обновлено: ${pad(state.loadedAt.getDate())}.${pad(state.loadedAt.getMonth() + 1)} ${formatTime(state.loadedAt)}`);
  }
  if (state.error) parts.push(`⚠ ${state.error}`);
  else if (state.stale) parts.push('⚠ Календарь давно не синхронизировался с iCloud');
  status.textContent = parts.join(' · ') || 'Загрузка…';
  status.classList.toggle('warning', Boolean(state.error || state.stale));
}

function render() {
  const dates = visibleDates();
  document.documentElement.style.setProperty('--days', dates.length);
  renderTitle(dates);
  renderDayHeaders(dates);
  renderAllDayRow(dates);
  renderGrid(dates);
  renderStatus();
}

function scrollToNow() {
  if (!isTodayVisible()) return;
  // The grid starts right below the sticky header, so scroll offset equals minutes shown above the fold
  window.scrollTo({ top: Math.max(0, minutesSinceMidnight(new Date()) - 3 * 60) });
}

// ---- Data ----

async function loadEvents() {
  const dates = visibleDates();
  const from = dateKey(dates[0]);
  const to = dateKey(dates[dates.length - 1]);

  state.request?.abort();
  const controller = new AbortController();
  state.request = controller;
  state.lastFetchAt = Date.now();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  try {
    const response = await fetch(`/events?start_date=${from}&end_date=${to}`, {
      signal: controller.signal,
      cache: 'no-store',
    });
    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.error || `Ошибка сервера (${response.status})`);
    }
    const data = await response.json();
    if (state.request !== controller) return; // superseded by a newer request

    state.events = data.events || {};
    state.stale = Boolean(data.stale);
    reloadIfFrontendChanged(data.version);
    state.loadedAt = new Date();
    state.error = null;
  } catch (error) {
    if (state.request !== controller) return; // superseded by a newer request
    if (error.name === 'AbortError') state.error = 'Сервер не отвечает';
    else if (error instanceof SyntaxError) state.error = 'Некорректный ответ сервера';
    else if (error instanceof TypeError) state.error = 'Нет связи с сервером';
    else state.error = error.message;
  } finally {
    clearTimeout(timeout);
  }

  if (state.request === controller) {
    state.request = null;
    render();
  }
}

// The server reports the deployed frontend version; reload to pick up new HTML, CSS and JS
function reloadIfFrontendChanged(version) {
  if (!version || version === document.documentElement.dataset.version) return;
  if ($('settings').open) return; // do not interrupt; the next ping retries

  try {
    // Guard against a reload loop if the page keeps arriving with an old version
    const lastReload = Number(sessionStorage.getItem(RELOAD_KEY)) || 0;
    if (Date.now() - lastReload < MIN_RELOAD_INTERVAL_MS) return;
    sessionStorage.setItem(RELOAD_KEY, String(Date.now()));
  } catch (error) {
    // sessionStorage unavailable; reload anyway
  }
  window.location.reload();
}

// Server-sent events: the server pushes a message whenever the calendar data changes
function connectUpdates() {
  // A replacement connection may have missed changes, so reload once it opens
  let reconnected = Boolean(state.updates);
  state.updates?.close();
  const source = new EventSource('/updates');
  state.updates = source;
  state.lastUpdateMessage = Date.now();

  source.addEventListener('open', () => {
    state.lastUpdateMessage = Date.now();
    // Catch up on anything missed while disconnected
    if (reconnected) loadEvents();
    reconnected = true;
  });
  source.addEventListener('ping', (event) => {
    state.lastUpdateMessage = Date.now();
    reloadIfFrontendChanged(event.data);
  });
  source.addEventListener('changed', () => {
    state.lastUpdateMessage = Date.now();
    loadEvents();
  });
}

function checkUpdatesConnection() {
  const source = state.updates;
  const silent = Date.now() - state.lastUpdateMessage > UPDATES_SILENCE_MS;
  if (!source || source.readyState === EventSource.CLOSED || silent) connectUpdates();
}

// ---- Navigation and settings ----

function updateUrl() {
  const url = new URL(window.location.href);
  if (dateKey(state.anchor) === state.today) url.searchParams.delete('date');
  else url.searchParams.set('date', dateKey(state.anchor));
  window.history.replaceState(null, '', url);
}

function navigate(anchor) {
  state.anchor = startOfDay(anchor);
  updateUrl();
  render();
  scrollToNow();
  loadEvents();
}

function loadSettings() {
  try {
    const settings = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}');
    if (DAY_OPTIONS.includes(settings.totalDays)) state.totalDays = settings.totalDays;
  } catch (error) {
    // Ignore unreadable settings and keep defaults
  }
}

function openSettings() {
  const dialog = $('settings');
  for (const input of dialog.querySelectorAll('input[name="totalDays"]')) {
    input.checked = Number(input.value) === state.totalDays;
  }
  dialog.returnValue = '';
  dialog.showModal();
}

function applySettings() {
  const dialog = $('settings');
  if (dialog.returnValue !== 'save') return;

  const selected = Number(dialog.querySelector('input[name="totalDays"]:checked')?.value);
  if (!DAY_OPTIONS.includes(selected) || selected === state.totalDays) return;

  state.totalDays = selected;
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({ totalDays: selected }));
  } catch (error) {
    // Storage unavailable; the setting applies until reload
  }
  render();
  loadEvents();
}

// ---- Periodic work ----

function tick() {
  const today = dateKey(new Date());
  const dayChanged = today !== state.today;
  const idle = Date.now() - state.lastInteraction;

  if (dayChanged) {
    const wasShowingToday = dateKey(state.anchor) === state.today;
    state.today = today;
    if (wasShowingToday) {
      navigate(new Date());
      return;
    }
  }

  if (idle > IDLE_RETURN_TODAY_MS && dateKey(state.anchor) !== state.today) {
    navigate(new Date());
    return;
  }

  render();
  if (idle > IDLE_SCROLL_MS) scrollToNow();
  if (dayChanged || Date.now() - state.lastFetchAt > FALLBACK_REFRESH_MS) loadEvents();
  checkUpdatesConnection();
}

function init() {
  loadSettings();
  const dateParam = parseDateKey(new URLSearchParams(window.location.search).get('date'));
  if (dateParam) state.anchor = dateParam;

  document.addEventListener('click', (event) => {
    const action = event.target.closest('[data-action]')?.dataset.action;
    if (action === 'prev') navigate(addDays(state.anchor, -state.totalDays));
    else if (action === 'next') navigate(addDays(state.anchor, state.totalDays));
    else if (action === 'today') navigate(new Date());
    else if (action === 'settings') openSettings();
  });

  const dialog = $('settings');
  dialog.addEventListener('close', applySettings);
  // Close when tapping the backdrop around the dialog
  dialog.addEventListener('click', (event) => {
    if (event.target === dialog) dialog.close('cancel');
  });

  for (const type of ['pointerdown', 'keydown', 'wheel', 'touchstart']) {
    window.addEventListener(type, () => { state.lastInteraction = Date.now(); }, { passive: true });
  }

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      tick();
      loadEvents();
    }
  });

  render();
  scrollToNow();
  loadEvents();
  connectUpdates();
  setInterval(tick, TICK_MS);
}

init();
