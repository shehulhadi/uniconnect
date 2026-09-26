// v2/js/bottom-nav.js — Matric chrome.
//
// Two navigation layers:
//   1. Bottom nav — always visible, four primary destinations.
//   2. Left drawer — the same four primaries, PLUS a context section
//      that changes based on which page you're on, PLUS secondary
//      pages (Assignments, Profile, Settings, Approvals) and Sign out.
//
// Every page loads this file with:
//   <script type="module" src="../js/bottom-nav.js"></script>

import { supabase } from './supabase.js';

// ============================================================
// Primary destinations (bottom nav + top of drawer)
// ============================================================
const PRIMARY = [
  { tab: 'home',     href: 'dashboard.html',     label: 'Home',
    files: ['dashboard.html'],
    svg: '<path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/>' },
  { tab: 'connect',  href: 'messages.html',      label: 'Connect',
    files: ['messages.html','dm.html','groups.html','group-chat.html','connect.html','community.html'],
    svg: '<path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z"/>' },
  { tab: 'notices',  href: 'notices.html', label: 'Notices',
    files: ['announcements.html','notices.html'],
    svg: '<path d="M3 11l18-8v18L3 13v-2z"/><path d="M11.6 16.8a3 3 0 1 1-5.8-1.6"/>' },
  { tab: 'library',  href: 'materials.html',     label: 'Library',
    files: ['materials.html','library.html'],
    svg: '<path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z"/><path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z"/>' },
];

const CHROME_SKIP_ATTR = 'data-no-chrome';

// ============================================================
// Context sections — drawn inside the drawer, per-page
// ============================================================
const CONTEXTS = {
  // Connect section
  messages:  { label: 'In Connect', items: [
    { href: 'messages.html',              label: 'Messages',    icon: 'chat' },
    { href: 'groups.html',                label: 'Communities', icon: 'users' },
    { href: 'messages.html?tab=people',   label: 'People',      icon: 'searchUsers' },
  ]},
  dm:        { label: 'In Connect', items: [
    { href: 'messages.html',              label: 'Messages',    icon: 'chat' },
    { href: 'groups.html',                label: 'Communities', icon: 'users' },
    { href: 'messages.html?tab=people',   label: 'People',      icon: 'searchUsers' },
  ]},
  groups:    { label: 'In Connect', items: [
    { href: 'messages.html',              label: 'Messages',    icon: 'chat' },
    { href: 'groups.html',                label: 'Communities', icon: 'users' },
    { href: 'messages.html?tab=people',   label: 'People',      icon: 'searchUsers' },
  ]},
  community: { label: 'In Connect', items: [
    { href: 'messages.html',              label: 'Messages',    icon: 'chat' },
    { href: 'groups.html',                label: 'Communities', icon: 'users' },
    { href: 'messages.html?tab=people',   label: 'People',      icon: 'searchUsers' },
  ]},

  // Notices section
  announcements: { label: 'Notices', items: [
    { href: 'announcements.html?filter=all',        label: 'All',        icon: 'list' },
    { href: 'announcements.html?filter=university', label: 'University', icon: 'building' },
    { href: 'announcements.html?filter=faculty',    label: 'Faculty',    icon: 'layers' },
    { href: 'announcements.html?filter=department', label: 'Department', icon: 'building2' },
    { href: 'announcements.html?filter=course',     label: 'Course',     icon: 'book' },
  ]},
  notices: { label: 'Notices', items: [
    { href: 'notices.html?filter=all',        label: 'All',        icon: 'list' },
    { href: 'notices.html?filter=university', label: 'University', icon: 'building' },
    { href: 'notices.html?filter=faculty',    label: 'Faculty',    icon: 'layers' },
    { href: 'notices.html?filter=department', label: 'Department', icon: 'building2' },
    { href: 'notices.html?filter=course',     label: 'Course',     icon: 'book' },
  ]},

  // Library section
  materials: { label: 'Library', items: [
    { href: 'materials.html?section=courses',         label: 'My Courses',       icon: 'book' },
    { href: 'materials.html?section=materials',       label: 'Course Materials', icon: 'folder' },
    { href: 'materials.html?section=past_questions',  label: 'Past Questions',   icon: 'file' },
    { href: 'materials.html?section=ebooks',          label: 'E-books',          icon: 'bookOpen' },
    { href: 'materials.html?section=saved',           label: 'Saved',            icon: 'bookmark' },
  ]},
  library: { label: 'Library', items: [
    { href: 'library.html?section=courses',         label: 'My Courses',       icon: 'book' },
    { href: 'library.html?section=materials',       label: 'Course Materials', icon: 'folder' },
    { href: 'library.html?section=past_questions',  label: 'Past Questions',   icon: 'file' },
    { href: 'library.html?section=ebooks',          label: 'E-books',          icon: 'bookOpen' },
    { href: 'library.html?section=saved',           label: 'Saved',            icon: 'bookmark' },
  ]},
};

// ============================================================
// Icons
// ============================================================
const ICONS = {
  chat:        '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>',
  users:       '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
  searchUsers: '<circle cx="11" cy="11" r="8"/><path d="M21 21l-4.35-4.35"/>',
  user:        '<path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>',
  list:        '<line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/>',
  building:    '<path d="M3 21h18M5 21V7l7-4 7 4v14M9 9h.01M9 13h.01M9 17h.01M15 9h.01M15 13h.01M15 17h.01"/>',
  building2:   '<rect x="4" y="2" width="16" height="20" rx="2"/><path d="M9 22v-4h6v4M8 6h.01M12 6h.01M16 6h.01M8 10h.01M12 10h.01M16 10h.01M8 14h.01M12 14h.01M16 14h.01"/>',
  layers:      '<path d="M12 2L2 7l10 5 10-5z"/><path d="M2 17l10 5 10-5M2 12l10 5 10-5"/>',
  book:        '<path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z"/><path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z"/>',
  bookOpen:    '<path d="M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z"/><path d="M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z"/>',
  folder:      '<path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/>',
  file:        '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/>',
  bookmark:    '<path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"/>',
  assignment:  '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/><polyline points="9 15 11 17 15 13"/>',
  settings:    '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09a1.65 1.65 0 0 0-1.09-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>',
  shieldCheck: '<polyline points="9 11 12 14 22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/>',
  signout:     '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="M16 17l5-5-5-5"/><path d="M21 12H9"/>',
  menu:        '<line x1="3" y1="6" x2="21" y2="6"/><line x1="3" y1="12" x2="21" y2="12"/><line x1="3" y1="18" x2="21" y2="18"/>',
};

// ============================================================
// Utils
// ============================================================
function currentFile() {
  const parts = location.pathname.split('/');
  return parts[parts.length - 1] || 'dashboard.html';
}
function fileKey() {
  const f = currentFile();
  return f.replace(/\.html$/, '');
}
function initials(name) {
  return (name || '?').split(' ').map(s => s[0]).filter(Boolean).slice(0, 2).join('').toUpperCase();
}
function svgWrap(path, size) {
  const s = size || 20;
  return '<svg viewBox="0 0 24 24" width="' + s + '" height="' + s + '" fill="none" ' +
         'stroke="currentColor" stroke-width="1.75" stroke-linecap="round" ' +
         'stroke-linejoin="round" aria-hidden="true">' + path + '</svg>';
}
function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, c => ({
    '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
  }[c]));
}

// ============================================================
// Identity (cached per page load)
// ============================================================
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

// ============================================================
// Bottom navigation
// ============================================================
function mountNav() {
  if (document.body.dataset.noNav === '1') return null;
  if (document.querySelector('.bottom-nav')) return document.querySelector('.bottom-nav');

  const here = currentFile();
  const nav = document.createElement('nav');
  nav.className = 'bottom-nav';
  nav.setAttribute('aria-label', 'Primary navigation');

  nav.innerHTML = PRIMARY.map(it => {
    const active = it.files.includes(here);
    const cls = 'bottom-nav__item' + (active ? ' is-active' : '');
    const current = active ? ' aria-current="page"' : '';
    return '<a class="' + cls + '" data-tab="' + it.tab + '" href="' + it.href + '"' + current + '>' +
             '<span class="bottom-nav__icon">' + svgWrap(it.svg) + '</span>' +
             '<span class="bottom-nav__label">' + esc(it.label) + '</span>' +
             '<span class="bottom-nav__badge" data-show=""></span>' +
           '</a>';
  }).join('');

  document.body.appendChild(nav);
  document.body.classList.add('has-bottom-nav');
  return nav;
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
    btn.innerHTML = svgWrap(ICONS.menu, 22);
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
    if (p?.avatar_url) a.innerHTML = '<img src="' + esc(p.avatar_url) + '" alt="">';
    else a.textContent = initials(p?.full_name || p?.email || '?');
    right.appendChild(a);
  }
}

// ============================================================
// Drawer
// ============================================================
let drawerOpen = false;

function primaryRow(it, here) {
  const active = it.files.includes(here);
  const cls = 'drawer__primary' + (active ? ' is-active' : '');
  return '<a class="' + cls + '" href="' + it.href + '">' +
    '<span class="drawer__primary-icon">' + svgWrap(it.svg, 22) + '</span>' +
    '<span class="drawer__primary-label">' + esc(it.label) + '</span>' +
    '<span class="drawer__primary-badge" data-badge="' + it.tab + '"></span>' +
  '</a>';
}

function secondaryRow(href, label, iconKey, opts) {
  const danger = opts && opts.danger ? ' drawer__item--danger' : '';
  return '<a class="drawer__item' + danger + '" href="' + href + '">' +
    svgWrap(ICONS[iconKey], 18) + '<span>' + esc(label) + '</span>' +
  '</a>';
}

function mountDrawer(identity) {
  if (document.getElementById('matric-drawer')) return;

  const p = identity.profile || {};
  const roles = identity.roles || [];
  const isAdmin = roles.includes('HOD') || roles.includes('UNIVERSITY_ADMIN');
  const here = currentFile();
  const key = fileKey();

  const roleLabel = (p.role || 'member').replace(/-/g, ' ');
  const isVerified = ['student','lecturer','hod','staff','faculty_admin','university_admin'].includes(p.role)
                     || roles.length > 0;

  const verifiedBadge = isVerified
    ? '<span class="drawer__verified">' +
        '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>' +
        'Verified' +
      '</span>'
    : '';

  // Context section — depends on which section we're on
  const context = CONTEXTS[key] || null;

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
        ${PRIMARY.map(it => primaryRow(it, here)).join('')}
      </div>

      ${context ? `
      <div class="drawer__section">
        <div class="drawer__label">${esc(context.label)}</div>
        ${context.items.map(it =>
          secondaryRow(it.href, it.label, it.icon)
        ).join('')}
      </div>` : ''}

      <hr class="drawer__divider">

      <div class="drawer__section">
        <div class="drawer__label">Academic</div>
        ${secondaryRow('assignments.html', 'Assignments', 'assignment')}
        ${(roles.includes('LECTURER') || roles.includes('HOD') || roles.includes('FACULTY_ADMIN')) ? secondaryRow('teaching.html', 'My Teaching', 'book') : ''}
      </div>

      <div class="drawer__section">
        <div class="drawer__label">Me</div>
        ${secondaryRow('profile.html', 'Profile', 'user')}
        ${secondaryRow('settings.html', 'Settings', 'settings')}
      </div>

      ${isAdmin ? `
      <div class="drawer__section">
        <div class="drawer__label">Administration</div>
        ${secondaryRow('approvals.html', 'Approvals', 'shieldCheck')}
      </div>` : ''}

      <hr class="drawer__divider">

      <div class="drawer__section">
        <button class="drawer__item drawer__item--danger" id="matric-drawer-signout" type="button">
          ${svgWrap(ICONS.signout, 18)}
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

// Swipe from left edge
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
// Unread badges (bottom nav)
// ============================================================
function setBadge(tab, count) {
  const el = document.querySelector('.bottom-nav__item[data-tab="' + tab + '"] .bottom-nav__badge');
  if (!el) return;
  const currently = el.hasAttribute('data-show');
  if (count > 0) {
    const text = count > 99 ? '99+' : String(count);
    if (el.textContent !== text) el.textContent = text;
    if (!currently) {
      el.setAttribute('data-show', '1');
      el.setAttribute('data-pulse', '1');
      setTimeout(() => el.removeAttribute('data-pulse'), 600);
    }
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
    .channel('nav-badges:' + _meId)
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
  mountNav();
  injectTopbar(identity);
  mountDrawer(identity);
  initBadges().catch(() => {});
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', boot);
} else {
  boot();
}
