// v2/js/supabase.js
// Single source of truth for the Supabase client.
// Every page that needs data imports `supabase` from here.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = 'https://lhhcmfvvcnvoemcwyxpe.supabase.co';
const SUPABASE_KEY = 'sb_publishable_Xz3xmKMZUXOhkd7KRJ5eXg_dN78ccOT';

export const supabase = createClient(SUPABASE_URL, SUPABASE_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
});
