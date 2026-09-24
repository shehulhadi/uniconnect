import { supabase } from './supabase.js';

const $ = (id) => document.getElementById(id);

function fail(msg) {
  console.error('[onboarding]', msg);
  const l = $('state-loading');
  if (l) l.hidden = true;
  const e = $('state-error');
  if (e) { e.hidden = false; e.textContent = String(msg); }
}

const STEPS = [
  { key: 'account',     title: 'Your account',           sub: 'This is the account you signed up with.' },
  { key: 'institution', title: 'Your institution',       sub: 'Choose the university, polytechnic, or college you belong to.' },
  { key: 'academic',    title: 'Your academic details',  sub: 'Tell us where you study within your institution.' },
  { key: 'identity',    title: 'Your student identity',  sub: 'Provide the ID your institution recognises you by.' },
  { key: 'enrollment',  title: 'Setting up your campus', sub: 'We are connecting you to your courses and communities.' },
];

function stepIndex(regStep) {
  switch (regStep) {
    case 'account':      return 0;
    case 'institution':  return 1;
    case 'academic':     return 2;
    case 'verification': return 3;
    case 'enrollment':   return 4;
    default:             return 0;
  }
}

function renderStepper(current) {
  const el = $('onb-progress');
  if (!el) return;
  el.innerHTML = STEPS.map((_, i) => {
    let cls = 'onb-progress__seg';
    if (i < current)   cls += ' is-done';
    if (i === current) cls += ' is-current';
    return `<div class="${cls}"></div>`;
  }).join('');
}

function showPanel(idx) {
  const panels = ['account','institution','academic','identity','enrollment'];
  panels.forEach((key, i) => {
    const el = $(`panel-${key}`);
    if (el) el.hidden = i !== idx;
  });
}

export async function run() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) { location.replace('login.html'); return; }
  const meId = session.user.id;

  const { data: profile, error } = await supabase
    .from('profiles')
    .select('id, email, full_name, registration_step, verification_status, institution_id, faculty_id, department_id, programme_id, level_id, session_id, matric_no')
    .eq('id', meId)
    .single();

  if (error) { fail('Could not load your account: ' + error.message); return; }

  if (profile.registration_step === 'complete') {
    location.replace('dashboard.html');
    return;
  }

  const current = stepIndex(profile.registration_step);

  $('state-loading').hidden = true;
  $('wizard').hidden = false;

  renderStepper(current);
  showPanel(current);
  $('step-label').textContent = `Step ${current + 1} of ${STEPS.length}`;
  $('step-title').textContent = STEPS[current].title;
  $('step-sub').textContent   = STEPS[current].sub;

  // ---------- Panel 1: Account ----------
  if (current === 0) {
    $('p-email').textContent = profile.email;
    $('p-account-hint').textContent = 'Your account is active. You can continue to the next step.';
    $('btn-account-continue').addEventListener('click', async () => {
      const btn = $('btn-account-continue');
      btn.disabled = true; btn.textContent = 'Saving…';
      const { error: upErr } = await supabase
        .from('profiles')
        .update({ registration_step: 'institution' })
        .eq('id', meId);
      if (upErr) {
        btn.disabled = false; btn.textContent = 'Continue';
        $('alert').textContent = upErr.message;
        $('alert').setAttribute('data-show', '1');
        return;
      }
      location.reload();
    });
  }

  // ---------- Panel 2: Institution ----------
  if (current === 1) {
    let institutions = [];
    let selectedId = profile.institution_id || null;

    function renderInstitutions(filter) {
      const q = (filter || '').trim().toLowerCase();
      const filtered = !q ? institutions : institutions.filter(i =>
        (i.name || '').toLowerCase().includes(q) || (i.domain || '').toLowerCase().includes(q)
      );
      const el = $('inst-list');
      if (!el) return;
      if (filtered.length === 0) {
        el.innerHTML = '<div class="inst-loading">No institutions match that search.</div>';
        return;
      }
      el.innerHTML = filtered.map(i => {
        const initials = (i.name || '?').split(/[\s,]+/).filter(Boolean).slice(0, 2).map(s => s[0]).join('').toUpperCase();
        const meta = i.domain || i.slug || '';
        const sel = i.id === selectedId ? ' data-selected="1"' : '';
        return `<button class="inst-card" data-id="${i.id}"${sel} type="button">
          <div class="inst-card__icon">${initials}</div>
          <div class="inst-card__body">
            <div class="inst-card__name">${i.name}</div>
            ${meta ? `<div class="inst-card__meta">${meta}</div>` : ''}
          </div>
        </button>`;
      }).join('');
    }

    const { data: list, error: listErr } = await supabase
      .from('institutions')
      .select('id, name, slug, domain')
      .order('name');

    if (listErr) {
      $('inst-list').innerHTML = `<div class="inst-loading" style="color:var(--danger);">${listErr.message}</div>`;
    } else {
      institutions = list || [];
      renderInstitutions('');
    }

    if (selectedId) $('btn-inst-continue').disabled = false;

    $('inst-search').addEventListener('input', (e) => renderInstitutions(e.target.value));

    $('inst-list').addEventListener('click', (e) => {
      const card = e.target.closest('.inst-card');
      if (!card) return;
      selectedId = card.dataset.id;
      document.querySelectorAll('.inst-card').forEach(el => el.removeAttribute('data-selected'));
      card.setAttribute('data-selected', '1');
      $('btn-inst-continue').disabled = false;
    });

    $('btn-inst-back').addEventListener('click', async () => {
      await supabase.from('profiles').update({ registration_step: 'account' }).eq('id', meId);
      location.reload();
    });

    $('btn-inst-continue').addEventListener('click', async () => {
      if (!selectedId) return;
      const btn = $('btn-inst-continue');
      btn.disabled = true; btn.textContent = 'Saving…';
      const { error: upErr } = await supabase
        .from('profiles')
        .update({ institution_id: selectedId, registration_step: 'academic' })
        .eq('id', meId);
      if (upErr) {
        btn.disabled = false; btn.textContent = 'Continue';
        $('alert').textContent = upErr.message;
        $('alert').setAttribute('data-show', '1');
        return;
      }
      location.reload();
    });
  }

  // ---------- Panel 3: Academic ----------
  if (current === 2) {
    const selFaculty = $('sel-faculty');
    const selDept    = $('sel-department');
    const selProg    = $('sel-programme');
    const selLevel   = $('sel-level');
    const selSession = $('sel-session');
    const btnCont    = $('btn-acad-continue');

    const instId = profile.institution_id;
    if (!instId) { fail('Institution is not set. Please go back to step 2.'); return; }

    function fillSelect(select, items, vKey, lKey, placeholder, selected) {
      select.innerHTML = ['<option value="">' + placeholder + '</option>']
        .concat(items.map(i => {
          const sel = (selected && selected === i[vKey]) ? ' selected' : '';
          return `<option value="${i[vKey]}"${sel}>${i[lKey]}</option>`;
        })).join('');
    }

    function refreshContinue() {
      const ok = selFaculty.value && selDept.value && selProg.value && selLevel.value && selSession.value;
      btnCont.disabled = !ok;
    }

    const { data: fac, error: facErr } = await supabase
      .from('faculties').select('id, name').eq('institution_id', instId).order('name');
    if (facErr) { fail('Could not load faculties: ' + facErr.message); return; }
    fillSelect(selFaculty, fac || [], 'id', 'name', 'Select a faculty', profile.faculty_id);

    async function loadDepartments(facultyId, preselect) {
      selDept.disabled = true;
      selDept.innerHTML = '<option value="">Loading…</option>';
      selProg.disabled = true;
      selProg.innerHTML = '<option value="">Select a department first</option>';
      if (!facultyId) {
        selDept.innerHTML = '<option value="">Select a faculty first</option>';
        refreshContinue(); return;
      }
      const { data, error } = await supabase
        .from('departments').select('id, name').eq('faculty_id', facultyId).order('name');
      if (error) { selDept.innerHTML = '<option value="">Could not load departments</option>'; refreshContinue(); return; }
      fillSelect(selDept, data || [], 'id', 'name', 'Select a department', preselect);
      selDept.disabled = false;
      refreshContinue();
    }

    async function loadProgrammes(deptId, preselect) {
      selProg.disabled = true;
      selProg.innerHTML = '<option value="">Loading…</option>';
      if (!deptId) {
        selProg.innerHTML = '<option value="">Select a department first</option>';
        refreshContinue(); return;
      }
      const { data, error } = await supabase
        .from('programmes').select('id, name, code').eq('department_id', deptId).order('name');
      if (error) { selProg.innerHTML = '<option value="">Could not load programmes</option>'; refreshContinue(); return; }
      fillSelect(selProg, data || [], 'id', 'name', 'Select a programme', preselect);
      selProg.disabled = false;
      refreshContinue();
    }

    const { data: lv } = await supabase
      .from('levels').select('id, ordinal, display_name').eq('institution_id', instId).order('ordinal');
    if (lv && lv.length) {
      fillSelect(selLevel, lv, 'id', 'display_name', 'Select a level', profile.level_id);
      selLevel.disabled = false;
    } else {
      selLevel.innerHTML = '<option value="">No levels configured</option>';
    }

    const { data: ss } = await supabase
      .from('academic_sessions').select('id, name, is_current').eq('institution_id', instId).order('start_date', { ascending: false });
    if (ss && ss.length) {
      fillSelect(selSession, ss, 'id', 'name', 'Select a session', profile.session_id);
      selSession.disabled = false;
      if (ss.length === 1) selSession.value = ss[0].id;
      else if (!profile.session_id) {
        const cur = ss.find(s => s.is_current);
        if (cur) selSession.value = cur.id;
      }
    } else {
      selSession.innerHTML = '<option value="">No sessions configured</option>';
    }

    selFaculty.addEventListener('change', async () => {
      await loadDepartments(selFaculty.value, null);
      selProg.value = '';
      refreshContinue();
    });
    selDept.addEventListener('change', async () => {
      await loadProgrammes(selDept.value, null);
      refreshContinue();
    });
    [selProg, selLevel, selSession].forEach(el => el.addEventListener('change', refreshContinue));

    if (profile.faculty_id) {
      await loadDepartments(profile.faculty_id, profile.department_id);
      if (profile.department_id) await loadProgrammes(profile.department_id, profile.programme_id);
    }
    refreshContinue();

    $('btn-acad-back').addEventListener('click', async () => {
      await supabase.from('profiles').update({ registration_step: 'institution' }).eq('id', meId);
      location.reload();
    });

    btnCont.addEventListener('click', async () => {
      if (btnCont.disabled) return;
      btnCont.disabled = true; btnCont.textContent = 'Saving…';
      const { error: upErr } = await supabase
        .from('profiles')
        .update({
          faculty_id: selFaculty.value,
          department_id: selDept.value,
          programme_id: selProg.value,
          level_id: selLevel.value,
          session_id: selSession.value,
          registration_step: 'verification'
        })
        .eq('id', meId);
      if (upErr) {
        btnCont.disabled = false; btnCont.textContent = 'Continue';
        $('alert').textContent = upErr.message;
        $('alert').setAttribute('data-show', '1');
        return;
      }
      location.reload();
    });
  }

  // ---------- Sign out ----------
  $('btn-signout').addEventListener('click', async () => {
    await supabase.auth.signOut();
    location.replace('login.html');
  });
}
