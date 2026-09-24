import { supabase } from './supabase.js';

const $ = (id) => document.getElementById(id);

function fail(msg) {
  console.error('[onboarding]', msg);
  const l = $('state-loading'); if (l) l.hidden = true;
  const e = $('state-error');
  if (e) { e.hidden = false; e.textContent = String(msg); }
}

const STEPS = [
  { key: 'account',     title: 'Your account',           sub: 'This is the account you signed up with.' },
  { key: 'institution', title: 'Your institution',       sub: 'Choose the university, polytechnic, or college you belong to.' },
  { key: 'academic',    title: 'Your academic details',  sub: 'Tell us where you belong within your institution.' },
  { key: 'identity',    title: 'Your identity',          sub: 'Provide the identifier your institution recognises you by.' },
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
  const el = $('onb-progress'); if (!el) return;
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

// ---------------- Role picker (injected into panel-academic) ----------------
function ensureRolePicker(selected) {
  const panel = $('panel-academic');
  if (!panel) return null;
  let wrap = document.getElementById('role-choice');
  if (!wrap) {
    wrap = document.createElement('div');
    wrap.id = 'role-choice';
    wrap.style.cssText = `
      display: grid; grid-template-columns: 1fr 1fr; gap: 8px;
      background: var(--bg-sunken); border: 1px solid var(--border);
      border-radius: var(--radius-md); padding: 3px;
      margin-bottom: var(--space-4);
    `;
    wrap.innerHTML = `
      <button type="button" data-role="student" style="appearance:none;border:none;background:transparent;padding:0.55rem;border-radius:calc(var(--radius-md) - 3px);font-size:var(--text-sm);font-weight:500;color:var(--text-muted);cursor:pointer;min-height:40px;font-family:inherit;">Student</button>
      <button type="button" data-role="lecturer" style="appearance:none;border:none;background:transparent;padding:0.55rem;border-radius:calc(var(--radius-md) - 3px);font-size:var(--text-sm);font-weight:500;color:var(--text-muted);cursor:pointer;min-height:40px;font-family:inherit;">Lecturer</button>
    `;
    panel.insertBefore(wrap, panel.firstChild);
  }
  setRole(selected);
  return wrap;
}

let chosenRole = 'student';

function setRole(role) {
  chosenRole = role;
  document.querySelectorAll('#role-choice button').forEach(b => {
    const on = b.dataset.role === role;
    b.style.background = on ? 'var(--bg-elevated)' : 'transparent';
    b.style.color = on ? 'var(--text)' : 'var(--text-muted)';
    b.style.boxShadow = on ? '0 1px 2px rgba(0,0,0,0.04)' : 'none';
    b.setAttribute('aria-pressed', String(on));
  });
  // Hide programme and level for lecturers
  const progField = $('sel-programme')?.closest('.field');
  const levelField = $('sel-level')?.closest('.field');
  if (progField)  progField.hidden  = (role === 'lecturer');
  if (levelField) levelField.hidden = (role === 'lecturer');
}

// =====================================================================
export async function run() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) { location.replace('login.html'); return; }
  const meId = session.user.id;

  const { data: profile, error } = await supabase
    .from('profiles')
    .select('id, email, full_name, role, registration_step, verification_status, institution_id, faculty_id, department_id, programme_id, level_id, session_id, matric_no, staff_no')
    .eq('id', meId)
    .single();

  if (error) { fail('Could not load your account: ' + error.message); return; }
  if (profile.registration_step === 'complete') { location.replace('dashboard.html'); return; }

  const current = stepIndex(profile.registration_step);

  $('state-loading').hidden = true;
  $('wizard').hidden = false;
  renderStepper(current);
  showPanel(current);
  $('step-label').textContent = `Step ${current + 1} of ${STEPS.length}`;
  $('step-title').textContent = STEPS[current].title;
  $('step-sub').textContent   = STEPS[current].sub;

  // ---------------- Panel 1: Account ----------------
  if (current === 0) {
    $('p-email').textContent = profile.email;
    $('p-account-hint').textContent = 'Your account is active. You can continue to the next step.';
    $('btn-account-continue').addEventListener('click', async () => {
      const btn = $('btn-account-continue');
      btn.disabled = true; btn.textContent = 'Saving…';
      const { error: upErr } = await supabase
        .from('profiles').update({ registration_step: 'institution' }).eq('id', meId);
      if (upErr) {
        btn.disabled = false; btn.textContent = 'Continue';
        $('alert').textContent = upErr.message; $('alert').setAttribute('data-show', '1'); return;
      }
      location.reload();
    });
  }

  // ---------------- Panel 2: Institution ----------------
  if (current === 1) {
    let institutions = [];
    let selectedId = profile.institution_id || null;

    function renderInstitutions(filter) {
      const q = (filter || '').trim().toLowerCase();
      const filtered = !q ? institutions : institutions.filter(i =>
        (i.name || '').toLowerCase().includes(q) || (i.domain || '').toLowerCase().includes(q));
      const el = $('inst-list'); if (!el) return;
      if (filtered.length === 0) {
        el.innerHTML = '<div class="inst-loading">No institutions match that search.</div>'; return;
      }
      el.innerHTML = filtered.map(i => {
        const initials = (i.name || '?').split(/[\s,]+/).filter(Boolean).slice(0,2).map(s => s[0]).join('').toUpperCase();
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
      .from('institutions').select('id, name, slug, domain').order('name');
    if (listErr) {
      $('inst-list').innerHTML = `<div class="inst-loading" style="color:var(--danger);">${listErr.message}</div>`;
    } else {
      institutions = list || []; renderInstitutions('');
    }
    if (selectedId) $('btn-inst-continue').disabled = false;
    $('inst-search').addEventListener('input', (e) => renderInstitutions(e.target.value));
    $('inst-list').addEventListener('click', (e) => {
      const card = e.target.closest('.inst-card'); if (!card) return;
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
      const { error: upErr } = await supabase.rpc('onboarding_set_institution', { p_institution_id: selectedId });
      if (upErr) {
        btn.disabled = false; btn.textContent = 'Continue';
        $('alert').textContent = upErr.message; $('alert').setAttribute('data-show', '1'); return;
      }
      location.reload();
    });
  }

  // ---------------- Panel 3: Academic (with role picker) ----------------
  if (current === 2) {
    const selFaculty = $('sel-faculty');
    const selDept    = $('sel-department');
    const selProg    = $('sel-programme');
    const selLevel   = $('sel-level');
    const selSession = $('sel-session');
    const btnCont    = $('btn-acad-continue');

    const instId = profile.institution_id;
    if (!instId) { fail('Institution is not set.'); return; }

    // Role picker at top
    const startRole = (profile.role === 'lecturer') ? 'lecturer' : 'student';
    ensureRolePicker(startRole);
    document.querySelectorAll('#role-choice button').forEach(b => {
      b.addEventListener('click', () => { setRole(b.dataset.role); refreshContinue(); });
    });

    function fillSelect(select, items, vKey, lKey, placeholder, selected) {
      select.innerHTML = ['<option value="">' + placeholder + '</option>']
        .concat(items.map(i => {
          const sel = (selected && selected === i[vKey]) ? ' selected' : '';
          return `<option value="${i[vKey]}"${sel}>${i[lKey]}</option>`;
        })).join('');
    }
    function refreshContinue() {
      const base = selFaculty.value && selDept.value && selSession.value;
      const needsProgLvl = (chosenRole === 'student');
      const extra = needsProgLvl ? (selProg.value && selLevel.value) : true;
      btnCont.disabled = !(base && extra);
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
      if (error) { selDept.innerHTML = '<option value="">Could not load</option>'; refreshContinue(); return; }
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
      if (error) { selProg.innerHTML = '<option value="">Could not load</option>'; refreshContinue(); return; }
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
      .from('academic_sessions').select('id, name, is_current')
      .eq('institution_id', instId).order('start_date', { ascending: false });
    if (ss && ss.length) {
      fillSelect(selSession, ss, 'id', 'name', 'Select a session', profile.session_id);
      selSession.disabled = false;
      if (ss.length === 1) selSession.value = ss[0].id;
      else if (!profile.session_id) {
        const cur = ss.find(s => s.is_current); if (cur) selSession.value = cur.id;
      }
    } else {
      selSession.innerHTML = '<option value="">No sessions configured</option>';
    }

    selFaculty.addEventListener('change', async () => {
      await loadDepartments(selFaculty.value, null);
      selProg.value = ''; refreshContinue();
    });
    selDept.addEventListener('change', async () => {
      await loadProgrammes(selDept.value, null); refreshContinue();
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
      const { error: upErr } = await supabase.rpc('onboarding_set_academic', {
        p_role:          chosenRole,
        p_faculty_id:    selFaculty.value,
        p_department_id: selDept.value,
        p_programme_id:  chosenRole === 'student' ? selProg.value : null,
        p_level_id:      chosenRole === 'student' ? selLevel.value : null,
        p_session_id:    selSession.value,
      });
      if (upErr) {
        btnCont.disabled = false; btnCont.textContent = 'Continue';
        $('alert').textContent = upErr.message; $('alert').setAttribute('data-show', '1'); return;
      }
      location.reload();
    });
  }

  // ---------------- Panel 4: Identity ----------------
  if (current === 3) {
    const isLecturer = profile.role === 'lecturer';
    const inputEl = $('id-matric');
    const labelEl = inputEl?.previousElementSibling;

    if (labelEl) labelEl.textContent = isLecturer ? 'Staff / Employee number' : 'Matric / Student number';
    if (inputEl) inputEl.placeholder = isLecturer ? 'e.g. MAU/STAFF/042' : 'e.g. CSC/21/0042';

    const btnContinue = $('btn-id-continue');

    const { data: summary } = await supabase
      .from('profiles')
      .select(`
        institutions ( name ), faculties ( name ), departments ( name ),
        programmes ( name ), levels ( display_name ), academic_sessions ( name )
      `)
      .eq('id', meId)
      .single();

    if (summary) {
      $('id-institution').textContent = summary.institutions?.name || '—';
      $('id-faculty').textContent     = summary.faculties?.name || '—';
      $('id-department').textContent  = summary.departments?.name || '—';
      $('id-programme').textContent   = summary.programmes?.name || '—';
      $('id-level').textContent       = summary.levels?.display_name || '—';
      $('id-session').textContent     = summary.academic_sessions?.name || '—';

      // Hide programme and level rows for lecturers
      if (isLecturer) {
        const rp = $('id-programme')?.closest('.id-summary__row');
        const rl = $('id-level')?.closest('.id-summary__row');
        if (rp) rp.hidden = true;
        if (rl) rl.hidden = true;
      }
    }

    const prefill = isLecturer ? profile.staff_no : profile.matric_no;
    if (prefill) { inputEl.value = prefill; btnContinue.disabled = false; }

    inputEl.addEventListener('input', () => {
      btnContinue.disabled = !inputEl.value.trim();
    });

    $('btn-id-back').addEventListener('click', async () => {
      await supabase.from('profiles').update({ registration_step: 'academic' }).eq('id', meId);
      location.reload();
    });

    btnContinue.addEventListener('click', async () => {
      const ident = inputEl.value.trim();
      if (!ident) return;
      btnContinue.disabled = true; btnContinue.textContent = 'Submitting…';
      const { data, error } = await supabase.rpc('onboarding_submit_identity', { p_identifier: ident });
      if (error) {
        btnContinue.disabled = false; btnContinue.textContent = 'Submit for verification';
        $('alert').textContent = error.message; $('alert').setAttribute('data-show', '1'); return;
      }
      const status = data?.status;
      if (status === 'verified') { location.reload(); }
      else {
        $('id-form-block').hidden = true;
        $('id-pending-block').hidden = false;
      }
    });

    $('btn-id-refresh')?.addEventListener('click', () => location.reload());
    $('btn-id-verified-continue')?.addEventListener('click', async () => {
      await supabase.from('profiles').update({ registration_step: 'enrollment' }).eq('id', meId);
      location.reload();
    });

    if (profile.verification_status === 'verified') {
      $('id-form-block').hidden = true;
      $('id-verified-block').hidden = false;
    } else if (profile.verification_status === 'pending') {
      $('id-form-block').hidden = true;
      $('id-pending-block').hidden = false;
    }
  }

  // ---------------- Panel 5: Enrollment ----------------
  if (current === 4) {
    const order = ['institution','faculty','department','programme','level','courses','communities'];
    const isLecturer = profile.role === 'lecturer';

    // For lecturers, drop the programme / level / courses steps
    const steps = isLecturer
      ? ['institution','faculty','department','communities']
      : order;

    // Hide the divs for steps we're skipping
    if (isLecturer) {
      ['programme','level','courses'].forEach(k => { const el = $('enr-' + k); if (el) el.hidden = true; });
    }

    function setState(key, state) {
      const el = $('enr-' + key);
      if (el) el.setAttribute('data-state', state);
    }

    const { data: result, error } = await supabase.rpc('run_enrollment');
    if (error) { fail('Enrollment failed: ' + error.message); return; }

    for (const key of steps) {
      setState(key, 'active');
      await new Promise(r => setTimeout(r, 220));
      setState(key, 'done');
    }

    const parts = [];
    if (result.faculty)    parts.push(result.faculty);
    if (result.department) parts.push(result.department);
    if (result.programme)  parts.push(result.programme);
    if (result.level)      parts.push(result.level);

    $('enr-inst-name').textContent = result.institution || 'Your institution';
    $('enr-detail').textContent =
      parts.join(' · ') +
      (result.new_courses ? `  ·  ${result.new_courses} course${result.new_courses === 1 ? '' : 's'} connected` : '') +
      (result.new_communities ? `  ·  ${result.new_communities} communit${result.new_communities === 1 ? 'y' : 'ies'} connected` : '');

    $('enr-progress').hidden = true;
    $('enr-summary').hidden = false;

    $('btn-enr-enter').addEventListener('click', () => location.replace('dashboard.html'));
  }

  // ---------------- Sign out ----------------
  $('btn-signout').addEventListener('click', async () => {
    await supabase.auth.signOut();
    location.replace('login.html');
  });
}
