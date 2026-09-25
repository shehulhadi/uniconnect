// v2/js/bottom-nav.js — injects bottom navigation with realtime unread badges.
// Opt out with <body data-no-nav="1">.

import { supabase } from './supabase.js';

const ITEMS = [
  { tab: 'home',      href: 'dashboard.html',     label: 'Home',      files: ['dashboard.html'],
    svg: '<path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/>' },
  { tab: 'chat',      href: 'messages.html',      label: 'Chat',      files: ['messages.html','dm.html'],
    svg: '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>' },
  { tab: 'notices',   href: 'announcements.html', label: 'Notices',   files: ['announcements.html'],
    svg: '<path d="M3 11l18-8v18L3 13v-2z"/><path d="M11.6 16.8a3 3 0 1 1-5.8-1.6"/>' },
  { tab: 'materials', href: 'materials.html',     label: 'Materials', files: ['materials.html'],
    svg: '<path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/>' },
  { tab: 'groups',    href: 'groups.html',        label: 'Groups',    files: ['groups.html','group-chat.html'],
    svg: '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>' },
  { tab: 'profile',   href: 'profile.html',       label: 'Profile',   files: ['profile.html'],
    svg: '<path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>' },
  { tab: 'approvals', href: 'approvals.html',     label: 'Approvals', files: ['approvals.html'],
    requireRole: ['HOD','UNIVERSITY_ADMIN'],
    svg: '<polyline points="9 11 12 14 22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/>' },
];

function currentFile() {
  const parts = location.pathname.split('/');
  return parts[parts.length - 1] || 'dashboard.html';
}

function iconWrap(svg) {
  return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
         'stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" ' +
         'aria-hidden="true">' + svg + '</svg>';
}

let myRoleNames = [];

async function fetchMyRoles() {
  try {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session) return [];
    const { data } = await supabase
      .from('user_role_assignments')
      .select('role_definitions(name)')
      .eq('user_id', session.user.id)
      .eq('status', 'active');
    return (data || []).map(r => r.role_definitions?.name).filter(Boolean);
  } catch (_) { return []; }
}

function mountNav() {
  if (document.body.dataset.noNav === '1') return null;
  if (document.querySelector('.bottom-nav')) return document.querySelector('.bottom-nav');

  const here = currentFile();
  const nav = document.createElement('nav');
  nav.className = 'bottom-nav';
  nav.setAttribute('aria-label', 'Primary navigation');

  const visible = ITEMS.filter(it => !it.requireRole || it.requireRole.some(r => myRoleNames.includes(r)));

  nav.innerHTML = visible.map(it => {
    const active = it.files.includes(here);
    const cls = 'bottom-nav__item' + (active ? ' is-active' : '');
    const current = active ? ' aria-current="page"' : '';
    return '<a class="' + cls + '" data-tab="' + it.tab + '" href="' + it.href + '"' + current + '>' +
             '<span class="bottom-nav__icon">' + iconWrap(it.svg) + '</span>' +
             '<span class="bottom-nav__label">' + it.label + '</span>' +
             '<span class="bottom-nav__badge" data-show=""></span>' +
           '</a>';
  }).join('');

  document.body.appendChild(nav);
  document.body.classList.add('has-bottom-nav');
  return nav;
}

// ---------------- Badge logic ----------------

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
  if (link.includes('dm.html') || link.includes('messages')) return 'chat';
  if (link.includes('announcement')) return 'notices';
  if (link.includes('material')) return 'materials';
  if (link.includes('group') || link.includes('communit')) return 'groups';
  // fall back by kind
  switch (n.kind) {
    case 'announcement': return 'notices';
    case 'material':     return 'materials';
    case 'group':        return 'groups';
    default:             return null;
  }
}

let meId = null;
let channel = null;

async function refreshBadges() {
  if (!meId) return;

  // Unread DMs — sum from dm_inbox()
  let chatCount = 0;
  try {
    const { data: inbox } = await supabase.rpc('dm_inbox');
    chatCount = (inbox || []).reduce((s, t) => s + (t.unread || 0), 0);
  } catch (_) {}
  setBadge('chat', chatCount);

  // Other tabs — unread notifications grouped by which tab they belong to
  const { data: notifs } = await supabase
    .from('notifications')
    .select('kind, link, read')
    .eq('user_id', meId)
    .eq('read', false);

  const buckets = { chat: 0, notices: 0, materials: 0, groups: 0 };
  (notifs || []).forEach(n => {
    const tab = tabForNotification(n);
    if (tab && tab !== 'chat') buckets[tab] = (buckets[tab] || 0) + 1;
  });

  setBadge('notices',   buckets.notices);
  setBadge('materials', buckets.materials);
  setBadge('groups',    buckets.groups);
}

async function initBadges() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return;
  meId = session.user.id;

  await refreshBadges();

  // Realtime: any change to my notifications re-computes badges
  channel = supabase
    .channel('nav-badges:' + meId)
    .on('postgres_changes',
        { event: '*', schema: 'public', table: 'notifications', filter: 'user_id=eq.' + meId },
        () => refreshBadges())
    .on('postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'dm_messages', filter: 'recipient_id=eq.' + meId },
        () => refreshBadges())
    .subscribe();

  // External code (notifications.js, page scripts) can force a refresh
  window.addEventListener('matric:notifications-changed', () => refreshBadges());

  // Refresh when tab becomes visible again
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) refreshBadges();
  });
}

// ---------------- Boot ----------------
async function boot() {
  myRoleNames = await fetchMyRoles();
  mountNav();
  initBadges().catch(() => {});
  window.addEventListener('beforeunload', () => {
    if (channel) supabase.removeChannel(channel);
  });
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', boot);
} else {
  boot();
}
