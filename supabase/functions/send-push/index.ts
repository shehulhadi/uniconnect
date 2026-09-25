// ============================================================
// Matric — send-push Edge Function
//
// Called by a Supabase Database Webhook on every INSERT into
// `public.notifications`. Looks up every push subscription for
// the target user and posts to each endpoint via Web Push.
//
// Environment (set in Supabase Dashboard → Project Settings → Edge Functions → Secrets):
//   VAPID_PUBLIC_KEY    — from ~/.matric-vapid.txt
//   VAPID_PRIVATE_KEY   — from ~/.matric-vapid.txt (SECRET)
//   VAPID_SUBJECT       — mailto: or https:// URL
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY — provided by Supabase automatically
// ============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';

const VAPID_PUBLIC  = Deno.env.get('VAPID_PUBLIC_KEY');
const VAPID_PRIVATE = Deno.env.get('VAPID_PRIVATE_KEY');
const VAPID_SUBJECT = Deno.env.get('VAPID_SUBJECT') || 'mailto:admin@example.com';
const SUPABASE_URL  = Deno.env.get('SUPABASE_URL');
const SERVICE_KEY   = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

if (!VAPID_PUBLIC || !VAPID_PRIVATE) {
  console.error('Missing VAPID keys');
}
if (VAPID_PUBLIC && VAPID_PRIVATE) {
  webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC, VAPID_PRIVATE);
}

Deno.serve(async (req) => {
  try {
    // Webhook payload is either { type, table, record, old_record } or the record directly
    const body = await req.json();
    const record = body.record || body;

    if (!record || !record.user_id) {
      return new Response('Missing user_id', { status: 400 });
    }

    // Only push for new rows
    if (body.type && body.type !== 'INSERT') {
      return new Response('Ignored event type: ' + body.type, { status: 200 });
    }

    // Build a deep link path (relative to the app root)
    let urlPath = './v2/pages/dashboard.html';
    const link = (record.link || '').toLowerCase();
    if (link.startsWith('dm.html'))                urlPath = './v2/pages/dm.html' + (record.link.split('?')[1] ? '?' + record.link.split('?')[1] : '');
    else if (link.startsWith('announcements'))     urlPath = './v2/pages/announcements.html';
    else if (link.startsWith('materials'))         urlPath = './v2/pages/materials.html';
    else if (link.startsWith('group-chat'))        urlPath = './v2/pages/group-chat.html' + (record.link.split('?')[1] ? '?' + record.link.split('?')[1] : '');
    else if (link.startsWith('messages'))          urlPath = './v2/pages/messages.html';

    const payload = JSON.stringify({
      title: record.title || 'Matric',
      body:  record.body  || '',
      url:   urlPath,
      tag:   record.kind  || 'notification',
      id:    record.id,
      icon:  './icons/icon-192.png',
      badge: './icons/icon-192.png',
    });

    const supabase = createClient(SUPABASE_URL, SERVICE_KEY);

    const { data: subs, error } = await supabase
      .from('push_subscriptions')
      .select('endpoint, p256dh, auth')
      .eq('user_id', record.user_id);

    if (error) throw error;

    if (!subs || subs.length === 0) {
      return new Response(JSON.stringify({ sent: 0, reason: 'no-subscriptions' }), {
        status: 200, headers: { 'content-type': 'application/json' },
      });
    }

    const results = await Promise.allSettled(
      subs.map(s => webpush.sendNotification(
        { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
        payload,
      ))
    );

    // Clean up dead subscriptions
    const dead = [];
    results.forEach((r, i) => {
      if (r.status === 'rejected') {
        const code = r.reason?.statusCode;
        if (code === 404 || code === 410) dead.push(subs[i].endpoint);
        else console.warn('push failed', code, r.reason?.message || r.reason);
      }
    });
    if (dead.length) {
      await supabase.from('push_subscriptions').delete().in('endpoint', dead);
    }

    const sent = results.filter(r => r.status === 'fulfilled').length;

    return new Response(JSON.stringify({ sent, dead: dead.length, total: subs.length }), {
      status: 200, headers: { 'content-type': 'application/json' },
    });
  } catch (err) {
    console.error('send-push error', err);
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500, headers: { 'content-type': 'application/json' },
    });
  }
});
