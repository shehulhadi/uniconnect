-- ============================================================
-- Migration 0009a — Rename seeded institution ABU → MAU
-- Everything references institution_id, so this is a single update.
-- ============================================================

update public.institutions
set name   = 'Modibbo Adama University, Yola',
    slug   = 'mau',
    domain = 'mau.edu.ng'
where slug = 'abu';
