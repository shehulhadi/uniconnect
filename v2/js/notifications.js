// v2/js/notifications.js — bell + panel + realtime.
// Mounts into any element with class `topbar__right` (or `.topbar__actions`).
// Opt out with <body data-no-notifications="1">.

import { supabase } from './supabase.js';

const POLL_MS = 30000;

const ICONS = {
  announcement: '<path d="M3 11l18-8v18L3 13v-2z"/><path d="M11.6 16.8a3 3 0 1 1-5.8-1.6"/>',
  material:     '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/>',
  group:        '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/>',
  system:       '<circle cx="12" cy="12" r="10"/><path d="M12 8v4M12 16h.01"/>',
};

const svg = (paths, size = 16) =>
  `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" ` +
  `stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" ` +
  `aria-hidden="true">${paths}</svg>`;

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, c => ({
  '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
}[c]));

function timeAgo(iso) {
  if (!iso) return '';
  const diff = (Date.now() - new Date(iso).getTime()) / 1000;
  if (diff < 60) return 'just now';
  if (diff < 3600) return Math.floor(diff / 60) + 'm ago';
  if (diff < 86400) return Math.floor(diff / 3600) + 'h ago';
  if (diff < 604800) return Math.floor(diff / 86400) + 'd ago';
  return new Date(iso).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

async function init() {
  if (document.body.dataset.noNotifications === '1') return;

  // ---- Session ----
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return;
  const meId = session.user.id;

  // ---- Mount point ----
  const container = document.querySelector('.topbar__right');
  if (!container) {
    console.warn('[notif] no .topbar__right element found — bell not mounted');
    return;
  }

  // ---- Bell button ----
  const bell = document.createElement('button');
  bell.className = 'notif-bell';
  bell.setAttribute('aria-label', 'Notifications');
  bell.innerHTML =
    svg('<path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/>', 20) +
    '<span class="notif-bell__badge" id="notif-badge"></span>';

  // Insert as first child of topbar__right so it sits left of the avatar
  container.insertBefore(bell, container.firstChild);

  // ---- Panel ----
  const panel = document.createElement('div');
  panel.className = 'notif-panel';
  panel.setAttribute('data-role', 'notif-panel');
  panel.innerHTML = `
    <div class="notif-panel__inner" role="dialog" aria-modal="true" aria-label="Notifications">
      <div class="notif-panel__head">
        <div class="notif-panel__title">Notifications</div>
        <div class="notif-panel__actions">
          <button class="notif-panel__btn" data-action="mark-all">Mark all read</button>
          <button class="notif-panel__btn" data-action="close" aria-label="Close">Close</button>
        </div>
      </div>
      <div class="notif-panel__list" id="notif-list"></div>
    </div>`;
  document.body.appendChild(panel);

  const listEl = panel.querySelector('#notif-list');
  const badge = bell.querySelector('#notif-badge');

  // ---- Data ----
  let items = [];

  async function load() {
    const { data, error } = await supabase
      .from('notifications')
      .select('id, kind, title, body, link, read, created_at')
      .eq('user_id', meId)
      .order('created_at', { ascending: false })
      .limit(50);
    if (error) { console.error('[notif]', error); return; }
    items = data || [];
    render();
  }

  function unreadCount() { return items.filter(n => !n.read).length; }

  function updateBadge() {
    const n = unreadCount();
    if (n > 0) {
      badge.textContent = n > 99 ? '99+' : String(n);
      badge.setAttribute('data-show', '1');
    } else {
      badge.removeAttribute('data-show');
    }
  }

  function render() {
    updateBadge();

    if (items.length === 0) {
      listEl.innerHTML = `
        <div class="notif-empty">
          ${svg('<path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/>', 32)}
          <div>No notifications yet</div>
        </div>`;
      return;
    }

    listEl.innerHTML = items.map(n => {
      const icon = ICONS[n.kind] || ICONS.system;
      return `
        <div class="notif-item" data-id="${esc(n.id)}" ${!n.read ? 'data-unread="1"' : ''}>
          <div class="notif-item__icon">${svg(icon)}</div>
          <div class="notif-item__body">
            <div class="notif-item__title">${esc(n.title)}</div>
            ${n.body ? `<div class="notif-item__sub">${esc(n.body)}</div>` : ''}
            <div class="notif-item__time">${timeAgo(n.created_at)}</div>
          </div>
        </div>`;
    }).join('');
  }

  // ---- Actions ----
  async function markRead(id) {
    const n = items.find(x => x.id === id);
    if (!n || n.read) return;
    n.read = true;
    updateBadge();
    // Optimistic render
    const el = listEl.querySelector(`[data-id="${id}"]`);
    if (el) el.removeAttribute('data-unread');
    const { error } = await supabase
      .from('notifications')
      .update({ read: true })
      .eq('id', id)
      .eq('user_id', meId);
    if (error) console.error('[notif] mark read', error);
    window.dispatchEvent(new CustomEvent('matric:notifications-changed'));
  }

  async function markAllRead() {
    const unreadIds = items.filter(n => !n.read).map(n => n.id);
    if (unreadIds.length === 0) return;
    items.forEach(n => { n.read = true; });
    render();
    const { error } = await supabase
      .from('notifications')
      .update({ read: true })
      .eq('user_id', meId)
      .in('id', unreadIds);
    if (error) console.error('[notif] mark all', error);
    window.dispatchEvent(new CustomEvent('matric:notifications-changed'));
  }

  // ---- Open / close ----
  function openPanel() {
    panel.setAttribute('data-open', '1');
    document.body.style.overflow = 'hidden';
    // Refresh on open — cheap query, 50 rows max
    load();
  }
  function closePanel() {
    panel.removeAttribute('data-open');
    document.body.style.overflow = '';
  }

  bell.addEventListener('click', openPanel);
  panel.addEventListener('click', (e) => {
    if (e.target === panel) return closePanel();
    const action = e.target.closest('[data-action]')?.dataset.action;
    if (action === 'close') return closePanel();
    if (action === 'mark-all') return markAllRead();

    const item = e.target.closest('.notif-item');
    if (item) {
      const id = item.dataset.id;
      const n = items.find(x => x.id === id);
      markRead(id);
      if (n?.link) {
        // Delay slightly so the read state shows before navigation
        setTimeout(() => { location.href = n.link; }, 120);
      }
    }
  });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && panel.hasAttribute('data-open')) closePanel();
  });

  // ---- Realtime ----
  supabase
    .channel('notifications:' + meId)
    .on(
      'postgres_changes',
      {
        event: 'INSERT',
        schema: 'public',
        table: 'notifications',
        filter: `user_id=eq.${meId}`,
      },
      (payload) => {
        items.unshift(payload.new);
        items = items.slice(0, 50);
        render();
      }
    )
    .subscribe();

  // ---- Fallback poll (in case realtime drops) ----
  setInterval(() => { if (!panel.hasAttribute('data-open')) load(); }, POLL_MS);

  // ---- Initial load ----
  load();
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
