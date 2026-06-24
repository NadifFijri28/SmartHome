import { auth, db } from './firebase.js';
import {
  signInWithEmailAndPassword,
  signOut as fbSignOut,
  onAuthStateChanged
} from 'https://www.gstatic.com/firebasejs/9.22.1/firebase-auth.js';
import {
  ref,
  onValue,
  update,
  get,
  set
} from 'https://www.gstatic.com/firebasejs/9.22.1/firebase-database.js';

// DOM nodes
const loginForm = document.getElementById('login-form');
const signoutBtn = document.getElementById('signout');
const authMsg = document.getElementById('auth-msg');
const appRoot = document.getElementById('app');
const deviceListEl = document.getElementById('device-list');
const deviceCountEl = document.getElementById('device-count');

// Local cache of device snapshots for quick lookup when editing schedules
const localDevicesData = {};

// Auth form submit (login)
if (loginForm) {
  loginForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    const email = document.getElementById('email').value.trim();
    const password = document.getElementById('password').value;
    authMsg.textContent = 'Signing in...';
    authMsg.classList.remove('success');
    try {
      await signInWithEmailAndPassword(auth, email, password);
      authMsg.textContent = 'Signed in successfully.';
      authMsg.classList.add('success');
    } catch (err) {
      console.error('Sign-in failed', err);
      const code = err && err.code ? err.code : 'unknown';
      let friendly = err && err.message ? err.message : 'Sign in failed';
      if (code === 'auth/invalid-email' || code === 'auth/wrong-password' || code === 'auth/user-not-found' || code === 'auth/invalid-login-credentials') {
        friendly = 'Email atau password salah.';
      } else if (code === 'auth/network-request-failed') {
        friendly = 'Gagal koneksi jaringan. Coba lagi.';
      } else if (code === 'auth/too-many-requests') {
        friendly = 'Terlalu banyak percobaan. Coba nanti.';
      }
      authMsg.textContent = `Sign in error (${code}): ${friendly}`;
    }
  });
}

// Sign out button
if (signoutBtn) {
  signoutBtn.addEventListener('click', async () => {
    await fbSignOut(auth);
  });
}

// Listener housekeeping
let userDevicesUnsub = null;
let deviceUnsubs = {};

// onAuthStateChanged: single-page auth flow without page redirects
onAuthStateChanged(auth, (user) => {
  if (user) {
    // show app
    if (document.getElementById('auth-card')) document.getElementById('auth-card').style.display = 'none';
    if (signoutBtn) signoutBtn.style.display = 'inline-flex';
    if (appRoot) appRoot.style.display = 'block';
    startDevicesListener(user.uid);
  } else {
    // show login form on this single-page app
    if (document.getElementById('auth-card')) document.getElementById('auth-card').style.display = 'block';
    if (signoutBtn) signoutBtn.style.display = 'none';
    if (appRoot) appRoot.style.display = 'none';
    stopDevicesListener();
    if (authMsg) authMsg.textContent = '';
  }
});

// Start listening to user's associated devices and attach per-device listeners
function startDevicesListener(uid) {
  const userRef = ref(db, `users/${uid}`);
  if (userDevicesUnsub) try { userDevicesUnsub(); } catch (e) {}

  userDevicesUnsub = onValue(userRef, (userSnapshot) => {
    const container = deviceListEl;
    if (!userSnapshot.exists()) {
      if (container) container.innerHTML = `<p style="color:red;">Error: UID Anda (${uid}) tidak terdaftar di node /users database.</p>`;
      if (deviceCountEl) deviceCountEl.textContent = '0 devices';
      return;
    }

    const userData = userSnapshot.val();
    const associatedDevices = userData.associated_devices;
    if (!associatedDevices) {
      if (container) container.innerHTML = '<p>Akun Anda terdaftar, tetapi belum memiliki perangkat terasosiasi.</p>';
      if (deviceCountEl) deviceCountEl.textContent = '0 devices';
      return;
    }

    // compute device IDs (handle both array and object map)
    const deviceIds = [];
    if (Array.isArray(associatedDevices)) {
      for (const id of associatedDevices) if (id) deviceIds.push(id);
    } else if (typeof associatedDevices === 'object') {
      deviceIds.push(...Object.keys(associatedDevices));
    }

    if (deviceCountEl) deviceCountEl.textContent = `${deviceIds.length} devices`;
    if (container) container.innerHTML = '';

    for (const deviceId of deviceIds) {
      if (associatedDevices[deviceId] !== true && Array.isArray(associatedDevices)) {
        // if stored as array, accept values directly
      }
      if (deviceUnsubs[deviceId]) continue; // already listening

      const deviceRef = ref(db, `devices/${deviceId}`);
      deviceUnsubs[deviceId] = onValue(deviceRef, (deviceSnapshot) => {
        if (deviceSnapshot.exists()) {
          const normalizedData = normalizeDeviceData(deviceSnapshot.val());
          localDevicesData[deviceId] = normalizedData;
          renderDeviceCard(deviceId, normalizedData);
        }
      }, (error) => {
        console.error(`Gagal memuat perangkat ${deviceId}:`, error);
        if (container) container.innerHTML += `<p style="color:red;">Akses ditolak untuk device: ${deviceId}</p>`;
      });
    }

    // unsubscribe removed devices
    for (const knownId of Object.keys(deviceUnsubs)) {
      if (!deviceIds.includes(knownId)) {
        try { deviceUnsubs[knownId](); } catch (e) {}
        delete deviceUnsubs[knownId];
        delete localDevicesData[knownId];
        const el = document.getElementById(`card-${knownId}`);
        if (el) el.remove();
      }
    }
  }, (error) => {
    if (deviceListEl) deviceListEl.innerHTML = `<p style="color:red;">Unable to load associated devices: ${escapeHtml(error.message || error)}</p>`;
    if (deviceCountEl) deviceCountEl.textContent = 'Error loading devices';
  });
}

function stopDevicesListener() {
  if (userDevicesUnsub) {
    try { userDevicesUnsub(); } catch (e) {}
    userDevicesUnsub = null;
  }
  for (const id of Object.keys(deviceUnsubs)) {
    try { deviceUnsubs[id](); } catch (e) {}
    delete deviceUnsubs[id];
  }
  for (const k of Object.keys(localDevicesData)) delete localDevicesData[k];
  if (deviceListEl) deviceListEl.innerHTML = '';
  if (deviceCountEl) deviceCountEl.textContent = '';
}

// Render device card including components and schedule management
function renderDeviceCard(deviceId, data) {
  const deviceStatus = data.metadata?.status || 'Unknown';
  const isOffline = deviceStatus.toLowerCase() === 'offline';
  let cardHtml = `
    <div class="device-card ${isOffline ? 'offline-mask' : ''}" id="card-${deviceId}">
      <div class="device-card-header">
        <div>
          <h3>${escapeHtml(data.metadata?.name || deviceId)}</h3>
          <p class="device-meta">Versi Hardware: ${escapeHtml(data.metadata?.hardware_version || '-')}</p>
        </div>
        <span class="badge ${deviceStatus.toLowerCase() === 'online' ? 'online' : 'offline'}">${escapeHtml(deviceStatus)}</span>
      </div>
      <div class="components-zone">
  `;

  if (data.components) {
    Object.keys(data.components).forEach((compKey) => {
      const comp = data.components[compKey];
      // Accept components that are explicitly OUTPUT+SWITCH, OR relay components
      // that may not have type/ui_element (e.g. created by ESP32 firmware)
      const isExplicitSwitch = comp.type === 'OUTPUT' && comp.ui_element === 'SWITCH';
      const isRelayComponent = compKey.startsWith('relay');
      if (!isExplicitSwitch && !isRelayComponent) return;

      const currentState = comp.current_state === true || comp.current_state === 1 || comp.current_state === 'true';
      const stateLabel = currentState ? 'MENYALA' : 'MATI';
      const badgeClass = currentState ? 'badge-state on' : 'badge-state off';
      const bulbIcon = currentState ? '💡' : '🔅';

      const scheduleContainerId = `schedule-add-${deviceId}-${compKey}`;
      const scheduleIndexId = `schedule-index-${deviceId}-${compKey}`;
      const scheduleLabelId = `schedule-label-${deviceId}-${compKey}`;
      const scheduleOnId = `schedule-on-${deviceId}-${compKey}`;
      const scheduleOffId = `schedule-off-${deviceId}-${compKey}`;

      cardHtml += `
        <div class="device-component-card">
          <div class="device-component-top">
            <div>
              <div class="component-title">${escapeHtml(comp.label || compKey)}</div>
              <div class="component-subtitle">Manual Override terhadap jadwal</div>
            </div>
            <div class="component-status-row">
              <span class="badge ${badgeClass}"><span class="badge-icon">${bulbIcon}</span>${stateLabel}</span>
              <label class="switch">
                <input type="checkbox" ${currentState ? 'checked' : ''} ${isOffline ? 'disabled' : ''} onchange="window.toggleRelay('${deviceId}', '${compKey}', this.checked)">
                <span class="slider"></span>
              </label>
            </div>
          </div>

          <div class="schedule-section">
            <div class="schedule-header">Jadwal Terpasang</div>
            <div class="schedule-list">
      `;

      if (Array.isArray(comp.schedules) && comp.schedules.length > 0) {
        comp.schedules.forEach((schedule, index) => {
          const activeClass = schedule.is_active ? 'schedule-chip active' : 'schedule-chip inactive';
          cardHtml += `
              <div class="schedule-item ${activeClass}">
                <div class="schedule-item-left">
                  <div class="schedule-label">${escapeHtml(schedule.label || `${schedule.on_time || '-'} → ${schedule.off_time || '-'}`)}</div>
                  <div class="schedule-time">${escapeHtml(schedule.on_time || '-')}-${escapeHtml(schedule.off_time || '-')}</div>
                </div>
                <div class="schedule-actions">
                  <span class="schedule-status ${schedule.is_active ? 'active' : 'inactive'}">${schedule.is_active ? 'Aktif' : 'Nonaktif'}</span>
                  <button class="schedule-edit" onclick="window.showEditScheduleForm('${deviceId}', '${compKey}', ${index})" type="button">✏️</button>
                  <button class="schedule-delete" onclick="window.deleteSchedule('${deviceId}', '${compKey}', ${index})" type="button">Hapus</button>
                </div>
              </div>
          `;
        });
      } else {
        cardHtml += `<div class="schedule-empty">Belum ada jadwal harian.</div>`;
      }

      cardHtml += `
            </div>
            <div class="schedule-add-container" id="${scheduleContainerId}">
              <button type="button" class="secondary-button small" onclick="window.showAddScheduleForm('${deviceId}', '${compKey}')">+ Tambah Jadwal</button>
              <div class="schedule-form hidden" id="form-${scheduleContainerId}">
                <input id="${scheduleIndexId}" type="hidden" value="-1" />
                <div class="schedule-form-grid">
                  <input id="${scheduleLabelId}" type="text" placeholder="Label Jadwal" />
                  <input id="${scheduleOnId}" type="time" />
                  <input id="${scheduleOffId}" type="time" />
                </div>
                <div class="schedule-form-actions">
                  <button type="button" class="primary-button small" onclick="window.saveScheduleProcess('${deviceId}', '${compKey}')">Simpan</button>
                  <button type="button" class="secondary-button small" onclick="window.cancelAddSchedule('${deviceId}', '${compKey}')">Batal</button>
                </div>
              </div>
            </div>
          </div>
        </div>
      `;
    });
  } else {
    cardHtml += `<div class="device-empty">Tidak ada komponen yang dapat dikontrol.</div>`;
  }

  cardHtml += `</div></div>`;

  const existingCard = document.getElementById(`card-${deviceId}`);
  if (existingCard) {
    existingCard.outerHTML = cardHtml;
  } else {
    deviceListEl.insertAdjacentHTML('beforeend', cardHtml);
  }
}

// toggleRelay: ensure strict boolean is sent to RTDB to match ESP32 expectations
window.toggleRelay = function(deviceId, componentId, newState) {
  const relayRef = ref(db, `devices/${deviceId}/components/${componentId}`);
  const strictBool = newState === true || newState === 'true' || newState === 1 || newState === '1';
  update(relayRef, { current_state: strictBool }).catch((err) => {
    console.error('Gagal update saklar:', err);
    alert('Gagal mengubah status relay: ' + (err && err.message ? err.message : err));
  });
};

// show add/edit form helpers
window.showAddScheduleForm = function(deviceId, componentId) {
  const form = document.getElementById(`form-schedule-add-${deviceId}-${componentId}`);
  const indexInput = document.getElementById(`schedule-index-${deviceId}-${componentId}`);
  const labelInput = document.getElementById(`schedule-label-${deviceId}-${componentId}`);
  const onInput = document.getElementById(`schedule-on-${deviceId}-${componentId}`);
  const offInput = document.getElementById(`schedule-off-${deviceId}-${componentId}`);
  if (indexInput) indexInput.value = '-1';
  if (labelInput) labelInput.value = '';
  if (onInput) onInput.value = '';
  if (offInput) offInput.value = '';
  if (form) form.classList.remove('hidden');
};

window.showEditScheduleForm = function(deviceId, componentId, scheduleIndex) {
  const form = document.getElementById(`form-schedule-add-${deviceId}-${componentId}`);
  const indexInput = document.getElementById(`schedule-index-${deviceId}-${componentId}`);
  const labelInput = document.getElementById(`schedule-label-${deviceId}-${componentId}`);
  const onInput = document.getElementById(`schedule-on-${deviceId}-${componentId}`);
  const offInput = document.getElementById(`schedule-off-${deviceId}-${componentId}`);
  const deviceData = localDevicesData[deviceId];
  const schedule = deviceData?.components?.[componentId]?.schedules?.[scheduleIndex];
  if (!schedule) {
    alert('Jadwal tidak ditemukan untuk diedit.');
    return;
  }
  if (indexInput) indexInput.value = String(scheduleIndex);
  if (labelInput) labelInput.value = schedule.label || '';
  if (onInput) onInput.value = schedule.on_time || '';
  if (offInput) offInput.value = schedule.off_time || '';
  if (form) form.classList.remove('hidden');
};

window.cancelAddSchedule = function(deviceId, componentId) {
  const form = document.getElementById(`form-schedule-add-${deviceId}-${componentId}`);
  if (form) {
    form.classList.add('hidden');
    const labelInput = document.getElementById(`schedule-label-${deviceId}-${componentId}`);
    const onInput = document.getElementById(`schedule-on-${deviceId}-${componentId}`);
    const offInput = document.getElementById(`schedule-off-${deviceId}-${componentId}`);
    const indexInput = document.getElementById(`schedule-index-${deviceId}-${componentId}`);
    if (labelInput) labelInput.value = '';
    if (onInput) onInput.value = '';
    if (offInput) offInput.value = '';
    if (indexInput) indexInput.value = '-1';
  }
};

window.saveScheduleProcess = async function(deviceId, componentId) {
  const labelInput = document.getElementById(`schedule-label-${deviceId}-${componentId}`);
  const onInput = document.getElementById(`schedule-on-${deviceId}-${componentId}`);
  const offInput = document.getElementById(`schedule-off-${deviceId}-${componentId}`);
  const indexInput = document.getElementById(`schedule-index-${deviceId}-${componentId}`);

  const label = labelInput?.value.trim();
  const onTime = onInput?.value;
  const offTime = offInput?.value;
  const scheduleIndex = indexInput ? Number(indexInput.value) : -1;

  if (!label || !onTime || !offTime) {
    alert('Semua field jadwal harus diisi.');
    return;
  }

  const scheduleRef = ref(db, `devices/${deviceId}/components/${componentId}/schedules`);
  try {
    const snapshot = await get(scheduleRef);
    const existingSchedules = snapshot.exists() && Array.isArray(snapshot.val()) ? snapshot.val() : [];

    if (scheduleIndex >= 0 && scheduleIndex < existingSchedules.length) {
      const updatedSchedule = {
        ...existingSchedules[scheduleIndex],
        label,
        on_time: onTime,
        off_time: offTime
      };
      existingSchedules[scheduleIndex] = updatedSchedule;
    } else {
      const newSchedule = {
        id: `sched_${Date.now()}`,
        label,
        is_active: true,
        on_time: onTime,
        off_time: offTime
      };
      existingSchedules.push(newSchedule);
    }

    await set(scheduleRef, existingSchedules);
    window.cancelAddSchedule(deviceId, componentId);
  } catch (err) {
    console.error('Gagal menyimpan jadwal:', err);
    alert('Gagal menyimpan jadwal. Silakan coba lagi.');
  }
};

window.deleteSchedule = async function(deviceId, componentId, scheduleIndex) {
  const scheduleRef = ref(db, `devices/${deviceId}/components/${componentId}/schedules`);
  try {
    const snapshot = await get(scheduleRef);
    if (!snapshot.exists() || !Array.isArray(snapshot.val())) {
      alert('Tidak ada jadwal untuk dihapus.');
      return;
    }
    const schedules = snapshot.val();
    if (scheduleIndex < 0 || scheduleIndex >= schedules.length) {
      alert('Index jadwal tidak valid.');
      return;
    }
    schedules.splice(scheduleIndex, 1);
    await set(scheduleRef, schedules);
  } catch (err) {
    console.error('Gagal menghapus jadwal:', err);
    alert('Gagal menghapus jadwal. Silakan coba lagi.');
  }
};

// Normalize device data: ensure all current_state values are strict booleans
function normalizeDeviceData(deviceData) {
  if (!deviceData || !deviceData.components) return deviceData;
  
  const normalized = { ...deviceData };
  normalized.components = { ...deviceData.components };
  
  Object.keys(normalized.components).forEach((compKey) => {
    const comp = normalized.components[compKey];
    normalized.components[compKey] = { ...comp };
    // Convert current_state to strict boolean for ESP32 compatibility
    normalized.components[compKey].current_state = 
      comp.current_state === true || comp.current_state === 1 || comp.current_state === 'true' || comp.current_state === '1';
  });
  
  return normalized;
}

// escape helper
function escapeHtml(s) {
  if (s == null) return '';
  return String(s)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
}
