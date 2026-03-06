const app = document.getElementById('app');
const closeBtn = document.getElementById('closeBtn');
const weatherText = document.getElementById('weatherText');
const temp = document.getElementById('temp');
const wind = document.getElementById('wind');
const gametime = document.getElementById('gametime');
const updated = document.getElementById('updated');

function pad(n) {
  const x = Number(n) || 0;
  return x < 10 ? `0${x}` : `${x}`;
}

function fmtTime(t) {
  if (!t) return '—';
  return `${pad(t.hour)}:${pad(t.minute)}:${pad(t.second)}`;
}

function fmtUpdated(meta) {
  if (!meta) return '—';
  // Server sends unix seconds in meta.fetchedAt
  if (meta.fetchedAt) {
    const d = new Date(Number(meta.fetchedAt) * 1000);
    return d.toLocaleString();
  }
  if (meta.localTime) return meta.localTime;
  return '—';
}

function toTitle(s) {
  return String(s || '').replace(/_/g, ' ');
}

window.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.action === 'open') {
    app.classList.remove('hidden');

    weatherText.textContent = toTitle(data.weather || 'UNKNOWN');

    const meta = data.meta || {};
    temp.textContent = meta.temperatureF != null ? `${meta.temperatureF}°F` : '—';
    wind.textContent = meta.windSpeedMph != null ? `${meta.windSpeedMph} mph` : '—';
    gametime.textContent = fmtTime(data.gameTime);

    updated.textContent = `Updated: ${fmtUpdated(meta)}`;
  }

  if (data.action === 'close') {
    app.classList.add('hidden');
  }
});

async function close() {
  try {
    await fetch(`https://${GetParentResourceName()}/tpwx_close`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify({})
    });
  } catch (e) {
    // ignore
  }
}

closeBtn.addEventListener('click', close);

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') close();
});
