// v2/js/bottom-nav.js — injects mobile bottom navigation.
// Opt out with <body data-no-nav="1">.

const ITEMS = [
  { href: 'dashboard.html',     label: 'Home',      files: ['dashboard.html'],
    svg: '<path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/>' },
  { href: 'messages.html',      label: 'Chat',      files: ['messages.html','dm.html'],
    svg: '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>' },
  { href: 'announcements.html', label: 'Notices',   files: ['announcements.html'],
    svg: '<path d="M3 11l18-8v18L3 13v-2z"/><path d="M11.6 16.8a3 3 0 1 1-5.8-1.6"/>' },
  { href: 'materials.html',     label: 'Materials', files: ['materials.html'],
    svg: '<path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/>' },
  { href: 'groups.html',        label: 'Groups',    files: ['groups.html','group-chat.html'],
    svg: '<path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>' },
  { href: 'profile.html',       label: 'Profile',   files: ['profile.html'],
    svg: '<path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>' },
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

function mount() {
  if (document.body.dataset.noNav === '1') return;
  if (document.querySelector('.bottom-nav')) return;

  const here = currentFile();

  const nav = document.createElement('nav');
  nav.className = 'bottom-nav';
  nav.setAttribute('aria-label', 'Primary navigation');

  nav.innerHTML = ITEMS.map(it => {
    const active = it.files.includes(here);
    const cls = 'bottom-nav__item' + (active ? ' is-active' : '');
    const current = active ? ' aria-current="page"' : '';
    return '<a class="' + cls + '" href="' + it.href + '"' + current + '>' +
             '<span class="bottom-nav__icon">' + iconWrap(it.svg) + '</span>' +
             '<span class="bottom-nav__label">' + it.label + '</span>' +
           '</a>';
  }).join('');

  document.body.appendChild(nav);
  document.body.classList.add('has-bottom-nav');
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', mount);
} else {
  mount();
}
