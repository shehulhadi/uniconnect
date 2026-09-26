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
let chosenCourseIds = new Set();

function setRole(role) {
  chosenRole = role;
  document.querySelectorAll('#role-choice button').forEach(b => {
    const on = b.dataset.role === role;
    b.style.background = on ? 'var(--bg-elevated)' : 'transparent';
    b.style.color = on ? 'var(--text)' : 'var(--text-muted)';
    b.style.boxShadow = on ? '0 1px 2px rgba(0,0,0,0.04)' : 'none';
    b.setAttribute('aria-pressed', String(on));
  });
  const progField  = $('sel-programme')?.closest('.field');
  const levelField = $('sel-level')?.closest('.field');
  const courseField = $('course-picker-field');
  if (progField)   progField.hidden   = (role === 'lecturer');
  if (levelField)  levelField.hidden  = (role === 'lecturer');
  if (courseField) courseField.hidden = (role !== 'lecturer');
  if (role !== 'lecturer') chosenCourseIds.clear();
  refreshCoursePicker();
}

// =====================================================================

// ---------------- Course picker ----------------
let allCourses = [];
let allCoursesLoaded = false;

async function loadAllCourses() {
  if (allCoursesLoaded) return;
  try {
    const { data, error } = await supabase
      .from('courses')
      .select('id, code, title, department_id')
      .order('code');
    if (error) {
      console.error('[picker] could not load courses:', error.message);
    } else {
      allCourses = data || [];
      console.log('[picker] loaded', allCourses.length, 'courses total');
    }
  } catch (err) {
    console.error('[picker] exception loading courses:', err);
  }
  allCoursesLoaded = true;
  refreshCoursePicker();
}

function refreshCoursePicker() {
  const wrap = document.getElementById('course-picker');
  if (!wrap) {
    console.log('[picker] no #course-picker in DOM');
    return;
  }

  if (chosenRole !== 'lecturer') {
    wrap.innerHTML = '<div class="course-picker__empty">Select a department first</div>';
    return;
  }

  const deptSelect = document.getElementById('sel-department');
  const deptId = deptSelect ? deptSelect.value : '';
  console.log('[picker] role=lecturer, deptId=', deptId, 'total courses=', allCourses.length);

  if (!deptId) {
    wrap.innerHTML = '<div class="course-picker__empty">Select a department first</div>';
    return;
  }

  const filtered = allCourses.filter(c => c.department_id === deptId);
  console.log('[picker] matched', filtered.length, 'courses in dept', deptId);

  if (!filtered.length) {
    if (!allCoursesLoaded) {
      wrap.innerHTML = '<div class="course-picker__empty">Loading courses…</div>';
    } else {
      wrap.innerHTML = '<div class="course-picker__empty">No courses in this department yet</div>';
    }
    return;
  }

  wrap.innerHTML = filtered.map(c => {
    const checked = chosenCourseIds.has(c.id);
    return `
      <button class="course-picker__item" data-course-id="${c.id}" ${checked ? 'data-checked' : ''} type="button">
        <span class="course-picker__check">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
        </span>
        <span class="course-picker__body">
          <span class="course-picker__code">${c.code}</span>
          <span class="course-picker__title">${c.title}</span>
        </span>
      </button>`;
  }).join('');

  wrap.querySelectorAll('.course-picker__item').forEach(el => {
    el.addEventListener('click', () => {
      const id = el.dataset.courseId;
      if (chosenCourseIds.has(id)) {
        chosenCourseIds.delete(id);
        el.removeAttribute('data-checked');
      } else {
        chosenCourseIds.add(id);
        el.setAttribute('data-checked', '');
      }
      document.dispatchEvent(new CustomEvent('course-selection-changed'));
    });
  });
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

    await loadAllCourses();

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
      const courseIds = chosenRole === 'lecturer' ? Array.from(chosenCourseIds) : null;
      const { error: upErr } = await supabase.rpc('onboarding_set_academic', {
        p_role:          chosenRole,
        p_faculty_id:    selFaculty.value,
        p_department_id: selDept.value,
        p_programme_id:  chosenRole === 'student' ? selProg.value : null,
        p_level_id:      chosenRole === 'student' ? selLevel.value : null,
        p_session_id:    selSession.value,
        p_course_ids:    courseIds,
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
