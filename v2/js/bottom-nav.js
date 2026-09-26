// v2/js/bottom-nav.js — unified chrome for Matric.
//
// Navigation model: left drawer is the only primary navigation.
// No bottom tab bar. Hamburger top-left, avatar top-right.
// Swipe from left edge or tap the hamburger to open the drawer.
//
// Every page loads this file with:
//   <script type="module" src="../js/bottom-nav.js"></script>

import { supabase } from './supabase.js';

// ---------- Drawer navigation ----------
// Primary items — always visible at the top of the drawer.
const PRIMARY = [
  {
    tab: 'home',
    href: 'dashboard.html',
    label: 'Home',
    files: ['dashboard.html'],
    svg: '<path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/>',
  },
  {
    tab: 'connect',
    href: 'messages.html',
    label: 'Connect',
    files: ['messages.html', 'dm.html', 'groups.html', 'group-chat.html', 'connect.html', 'community.html'],
    svg: '<path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"/>',
  },
  {
    tab: 'notices',
    href: 'announcements.html',
    label: 'Notices',
    files: ['announcements.html', 'notices.html'],
    svg: '<path d="M3 11l18-8v18L3 13v-2z"/><path d="M11.6 16.8a3 3 0 1 1-5.8-1.6"/>',
  },
  {
    tab: 'library',
    href: 'materials.html',
    label: 'Library',
    files: ['materials.html', 'library.html'],
    svg: '<path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z"/><path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z"/>',
  },
];

const CHROME_SKIP_ATTR = 'data-no-chrome';

// ---------- Identity (cached) ----------
let _identity = null;
async function getIdentity() {
  if (_identity) return _identity;
  try {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) {
      _identity = { session: null, profile: null, roles: [] };
      return _identity;
    }
    const [pRes, rRes] = await Promise.all([
      supabase
        .from('profiles')
        .select(`
          id, full_name, email, role, avatar_url, institution_id,
          institutions ( name ),
          departments  ( name ),
          levels       ( display_name )
        `)
        .eq('id', session.user.id)
        .single(),
      supabase
        .from('user_role_assignments')
        .select('role_definitions(name)')
        .eq('user_id', session.user.id)
        .eq('status', 'active'),
    ]);
    _identity = {
      session,
      profile: pRes.data || null,
      roles: (rRes.data || []).map(r => r.role_definitions?.name).filter(Boolean),
    };
  } catch (_) {
    _identity = { session: null, profile: null, roles: [] };
  }
  return _identity;
}

// ---------- Utils ----------
function currentFile() {
  const parts = location.pathname.split('/');
  return parts[parts.length - 1] || 'dashboard.html';
}
function initials(name) {
  return (name || '?').split(' ').map(s => s[0]).filter(Boolean).slice(0, 2).join('').toUpperCase();
}
function iconWrap(svg) {
  return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
         'stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" ' +
         'aria-hidden="true">' + svg + '</svg>';
}
function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, c => ({
    '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
  }[c]));
}

// ============================================================
// Topbar injection (hamburger + avatar)
// ============================================================
function injectTopbar(identity) {
  const topbar = document.querySelector('.topbar');
  if (!topbar) return;

  const hasBack = topbar.querySelector('.back');
  if (!hasBack && !topbar.querySelector('.topbar__menu-btn')) {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'topbar__menu-btn';
    btn.setAttribute('aria-label', 'Open menu');
    btn.innerHTML = iconWrap('<line x1="3" y1="6" x2="21" y2="6"/><line x1="3" y1="12" x2="21" y2="12"/><line x1="3" y1="18" x2="21" y2="18"/>');
    btn.addEventListener('click', openDrawer);
    topbar.insertBefore(btn, topbar.firstChild);
  }

  let right = topbar.querySelector('.topbar__right');
  if (!right) {
    right = document.createElement('div');
    right.className = 'topbar__right';
    topbar.appendChild(right);
  }
  if (!right.querySelector('.topbar__avatar')) {
    const a = document.createElement('a');
    a.className = 'topbar__avatar';
    a.href = 'profile.html';
    a.setAttribute('aria-label', 'Your profile');
    const p = identity.profile;
    if (p?.avatar_url) {
      a.innerHTML = '<img src="' + esc(p.avatar_url) + '" alt="">';
    } else {
      a.textContent = initials(p?.full_name || p?.email || '?');
    }
    right.appendChild(a);
  }
}

// ============================================================
// Drawer
// ============================================================
let drawerOpen = false;

function primaryItem(it, here) {
  const active = it.files.includes(here);
  const cls = 'drawer__primary' + (active ? ' is-active' : '');
  return '<a class="' + cls + '" href="' + it.href + '">' +
    '<span class="drawer__primary-icon">' + iconWrap(it.svg) + '</span>' +
    '<span class="drawer__primary-label">' + esc(it.label) + '</span>' +
    '<span class="drawer__primary-badge" data-badge="' + it.tab + '"></span>' +
  '</a>';
}

function secondaryItem(href, label, svg) {
  return '<a class="drawer__item" href="' + href + '">' + iconWrap(svg) + '<span>' + esc(label) + '</span></a>';
}

function mountDrawer(identity) {
  if (document.getElementById('matric-drawer')) return;

  const p = identity.profile || {};
  const roles = identity.roles || [];
  const isAdmin = roles.includes('HOD') || roles.includes('UNIVERSITY_ADMIN');
  const here = currentFile();

  const instName = p.institutions?.name || '';
  const deptName = p.departments?.name || '';
  const scopeLine = [deptName, instName].filter(Boolean).join(' · ') || 'Matric member';
  const roleLabel = (p.role || 'member').replace(/-/g, ' ');
  const isVerified = p.role === 'student' || roles.includes('LECTURER') || roles.includes('HOD') || roles.includes('UNIVERSITY_ADMIN');

  const verifiedBadge = isVerified
    ? '<span class="drawer__verified">' +
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>' +
        'Verified' +
      '</span>'
    : '';

  const backdrop = document.createElement('div');
  backdrop.className = 'drawer-backdrop';
  backdrop.id = 'matric-drawer-backdrop';
  backdrop.addEventListener('click', closeDrawer);

  const drawer = document.createElement('aside');
  drawer.className = 'drawer';
  drawer.id = 'matric-drawer';
  drawer.setAttribute('aria-hidden', 'true');

  drawer.innerHTML = `
    <div class="drawer__head">
      <div class="drawer__avatar">
        ${p.avatar_url
          ? '<img src="' + esc(p.avatar_url) + '" alt="">'
          : initials(p.full_name || p.email || '?')}
      </div>
      <div class="drawer__identity">
        <div class="drawer__name">${esc(p.full_name || 'Welcome')}</div>
        <div class="drawer__meta">
          <span style="text-transform:capitalize;">${esc(roleLabel)}</span>
          ${verifiedBadge}
        </div>
      </div>
    </div>

    <nav class="drawer__body">

      <div class="drawer__primary-group">
        ${PRIMARY.map(it => primaryItem(it, here)).join('')}
      </div>

      <hr class="drawer__divider">

      <div class="drawer__section">
        <div class="drawer__label">Academic</div>
        ${secondaryItem('assignments.html', 'Assignments', '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/>')}
      </div>

      <div class="drawer__section">
        <div class="drawer__label">Me</div>
        ${secondaryItem('profile.html', 'Profile', '<path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>')}
        ${secondaryItem('settings.html', 'Settings', '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09a1.65 1.65 0 0 0-1.09-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>')}
      </div>

      ${isAdmin ? `
      <div class="drawer__section">
        <div class="drawer__label">Administration</div>
        ${secondaryItem('approvals.html', 'Approvals', '<polyline points="9 11 12 14 22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/>')}
      </div>` : ''}

      <hr class="drawer__divider">

      <div class="drawer__section">
        <button class="drawer__item drawer__item--danger" id="matric-drawer-signout" type="button">
          ${iconWrap('<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="M16 17l5-5-5-5"/><path d="M21 12H9"/>')}
          <span>Sign out</span>
        </button>
      </div>

    </nav>
  `;

  document.body.appendChild(backdrop);
  document.body.appendChild(drawer);

  drawer.querySelector('#matric-drawer-signout').addEventListener('click', async () => {
    await supabase.auth.signOut();
    location.replace('login.html');
  });
}

function openDrawer() {
  const drawer = document.getElementById('matric-drawer');
  const backdrop = document.getElementById('matric-drawer-backdrop');
  if (!drawer || !backdrop) return;
  drawer.setAttribute('data-open', '1');
  drawer.setAttribute('aria-hidden', 'false');
  backdrop.setAttribute('data-open', '1');
  document.body.setAttribute('data-drawer-open', '1');
  drawerOpen = true;
}

function closeDrawer() {
  const drawer = document.getElementById('matric-drawer');
  const backdrop = document.getElementById('matric-drawer-backdrop');
  if (!drawer || !backdrop) return;
  drawer.removeAttribute('data-open');
  drawer.setAttribute('aria-hidden', 'true');
  backdrop.removeAttribute('data-open');
  document.body.removeAttribute('data-drawer-open');
  drawerOpen = false;
}

document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && drawerOpen) closeDrawer();
});

// Swipe from left edge to open
let touchStartX = null;
document.addEventListener('touchstart', (e) => {
  if (e.touches.length === 1 && e.touches[0].clientX < 20) {
    touchStartX = e.touches[0].clientX;
  } else {
    touchStartX = null;
  }
}, { passive: true });
document.addEventListener('touchmove', (e) => {
  if (touchStartX === null || drawerOpen) return;
  const dx = e.touches[0].clientX - touchStartX;
  if (dx > 60) { openDrawer(); touchStartX = null; }
}, { passive: true });
document.addEventListener('touchend', () => { touchStartX = null; }, { passive: true });

// ============================================================
// Drawer badges (unread counts shown next to primary items)
// ============================================================
function setBadge(tab, count) {
  const el = document.querySelector('.drawer__primary-badge[data-badge="' + tab + '"]');
  if (!el) return;
  if (count > 0) {
    el.textContent = count > 99 ? '99+' : String(count);
    el.setAttribute('data-show', '1');
  } else {
    el.removeAttribute('data-show');
  }
}

function tabForNotification(n) {
  const link = (n.link || '').toLowerCase();
  if (link.includes('dm.html') || link.includes('messages')) return 'connect';
  if (link.includes('announcement')) return 'notices';
  if (link.includes('material')) return 'library';
  if (link.includes('group') || link.includes('communit')) return 'connect';
  switch (n.kind) {
    case 'announcement': return 'notices';
    case 'material':     return 'library';
    case 'group':        return 'connect';
    default:             return null;
  }
}

let _meId = null;
let _badgeChannel = null;

async function refreshBadges() {
  if (!_meId) return;

  let chatCount = 0;
  try {
    const { data: inbox } = await supabase.rpc('dm_inbox');
    chatCount = (inbox || []).reduce((s, t) => s + (t.unread || 0), 0);
  } catch (_) {}
  setBadge('connect', chatCount);

  const { data: notifs } = await supabase
    .from('notifications')
    .select('kind, link, read')
    .eq('user_id', _meId)
    .eq('read', false);

  const buckets = { notices: 0, library: 0 };
  (notifs || []).forEach(n => {
    const tab = tabForNotification(n);
    if (tab === 'notices') buckets.notices++;
    if (tab === 'library') buckets.library++;
  });

  setBadge('notices', buckets.notices);
  setBadge('library', buckets.library);
}

async function initBadges() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return;
  _meId = session.user.id;
  await refreshBadges();

  _badgeChannel = supabase
    .channel('drawer-badges:' + _meId)
    .on('postgres_changes',
        { event: '*', schema: 'public', table: 'notifications', filter: 'user_id=eq.' + _meId },
        () => refreshBadges())
    .on('postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'dm_messages', filter: 'recipient_id=eq.' + _meId },
        () => refreshBadges())
    .subscribe();

  window.addEventListener('matric:notifications-changed', () => refreshBadges());
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) refreshBadges();
  });
}

// ============================================================
// Boot
// ============================================================
async function boot() {
  if (document.body.getAttribute(CHROME_SKIP_ATTR) === '1') return;
  const identity = await getIdentity();
  injectTopbar(identity);
  mountDrawer(identity);
  initBadges().catch(() => {});
  document.body.classList.add('has-drawer-chrome');
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', boot);
} else {
  boot();
}
