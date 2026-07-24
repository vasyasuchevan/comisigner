// ComiSigner — /api/staff
//
// The ONE place in this project that knows the Supabase service_role key.
// Everything else is a static page talking to Supabase through the public
// (anon/publishable) key, protected by RLS. Managing office accounts —
// creating a login, changing a role, deactivating someone — needs Supabase's
// Admin API, which requires service_role and can never run in the browser.
// This function holds that key (as a Vercel environment variable, never in
// the repo) and re-checks on every single request that the caller is an
// authenticated Admin before doing anything privileged. No npm dependencies —
// plain fetch() calls to Supabase's REST endpoints, matching this project's
// "no build step" convention.

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://nyuuhxbyvqntcygbwzcp.supabase.co';

function adminHeaders(serviceRoleKey, extra) {
  return Object.assign(
    { Authorization: 'Bearer ' + serviceRoleKey, apikey: serviceRoleKey },
    extra || {}
  );
}

module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!serviceRoleKey) {
    res.status(500).json({ error: 'SUPABASE_SERVICE_ROLE_KEY nu este configurat pe server (Vercel → Project Settings → Environment Variables).' });
    return;
  }

  const authHeader = req.headers['authorization'] || '';
  const accessToken = authHeader.replace(/^Bearer\s+/i, '');
  if (!accessToken) {
    res.status(401).json({ error: 'Lipsește token-ul de autentificare.' });
    return;
  }

  // Who is calling? Validate their session token against Supabase Auth.
  let callingUser;
  try {
    const userResp = await fetch(SUPABASE_URL + '/auth/v1/user', {
      headers: adminHeaders(serviceRoleKey, { Authorization: 'Bearer ' + accessToken })
    });
    if (!userResp.ok) throw new Error('invalid token');
    callingUser = await userResp.json();
  } catch (err) {
    res.status(401).json({ error: 'Token invalid sau expirat.' });
    return;
  }

  // Are they an Admin? This check — not the hidden button in the UI — is the
  // real security boundary for everything below.
  let callerRole = null;
  try {
    const profileResp = await fetch(
      SUPABASE_URL + '/rest/v1/profiles?id=eq.' + encodeURIComponent(callingUser.id) + '&select=role',
      { headers: adminHeaders(serviceRoleKey) }
    );
    const rows = await profileResp.json();
    callerRole = Array.isArray(rows) && rows[0] ? rows[0].role : null;
  } catch (err) {
    res.status(500).json({ error: 'Nu s-a putut verifica rolul apelantului.' });
    return;
  }
  if (callerRole !== 'admin') {
    res.status(403).json({ error: 'Doar Admin poate gestiona echipa.' });
    return;
  }

  let body = req.body || {};
  if (typeof body === 'string') {
    try { body = JSON.parse(body); } catch (e) { body = {}; }
  }
  const action = body.action;

  try {
    if (action === 'list') {
      const usersResp = await fetch(SUPABASE_URL + '/auth/v1/admin/users?per_page=200', {
        headers: adminHeaders(serviceRoleKey)
      });
      const usersJson = await usersResp.json();
      if (!usersResp.ok) throw new Error(usersJson.msg || usersJson.error_description || 'Nu s-a putut încărca lista de utilizatori.');
      const allUsers = usersJson.users || [];

      const profilesResp = await fetch(SUPABASE_URL + '/rest/v1/profiles?select=id,role,full_name', {
        headers: adminHeaders(serviceRoleKey)
      });
      const profiles = await profilesResp.json();
      const profileById = {};
      (profiles || []).forEach(function (p) { profileById[p.id] = p; });

      const staff = allUsers
        .filter(function (u) { return profileById[u.id]; })
        .map(function (u) {
          const p = profileById[u.id];
          return {
            id: u.id,
            email: u.email,
            full_name: p.full_name,
            role: p.role,
            deactivated: !!(u.banned_until && new Date(u.banned_until) > new Date())
          };
        });

      res.status(200).json({ staff: staff });
      return;
    }

    if (action === 'invite') {
      const email = body.email;
      const role = body.role === 'admin' ? 'admin' : 'hr';
      if (!email) { res.status(400).json({ error: 'Lipsește adresa de e-mail.' }); return; }

      const inviteResp = await fetch(SUPABASE_URL + '/auth/v1/invite', {
        method: 'POST',
        headers: adminHeaders(serviceRoleKey, { 'Content-Type': 'application/json' }),
        body: JSON.stringify({ email: email })
      });
      const inviteJson = await inviteResp.json();
      if (!inviteResp.ok) throw new Error(inviteJson.msg || inviteJson.error_description || 'Nu s-a putut trimite invitația.');

      const newUserId = inviteJson.id;
      const profileInsertResp = await fetch(SUPABASE_URL + '/rest/v1/profiles', {
        method: 'POST',
        headers: adminHeaders(serviceRoleKey, { 'Content-Type': 'application/json', Prefer: 'return=minimal' }),
        body: JSON.stringify({ id: newUserId, role: role, full_name: body.full_name || null })
      });
      if (!profileInsertResp.ok) {
        throw new Error('Contul a fost creat și invitat, dar nu s-a putut atribui rolul — verificați manual în Supabase Dashboard → Table Editor → profiles.');
      }

      res.status(200).json({ ok: true });
      return;
    }

    if (action === 'updateRole') {
      const id = body.id;
      const newRole = body.role === 'admin' ? 'admin' : 'hr';
      if (!id) { res.status(400).json({ error: 'Lipsește id-ul.' }); return; }

      const updateResp = await fetch(SUPABASE_URL + '/rest/v1/profiles?id=eq.' + encodeURIComponent(id), {
        method: 'PATCH',
        headers: adminHeaders(serviceRoleKey, { 'Content-Type': 'application/json', Prefer: 'return=minimal' }),
        body: JSON.stringify({ role: newRole })
      });
      if (!updateResp.ok) throw new Error('Nu s-a putut actualiza rolul.');

      res.status(200).json({ ok: true });
      return;
    }

    if (action === 'deactivate') {
      const deactivateId = body.id;
      if (!deactivateId) { res.status(400).json({ error: 'Lipsește id-ul.' }); return; }
      if (deactivateId === callingUser.id) {
        res.status(400).json({ error: 'Nu îți poți dezactiva propriul cont.' });
        return;
      }

      // ban_duration is a duration string, not a date — this bans for ~100 years,
      // effectively permanent but reversible (re-invite/PATCH ban_duration:'none' later).
      const banResp = await fetch(SUPABASE_URL + '/auth/v1/admin/users/' + encodeURIComponent(deactivateId), {
        method: 'PUT',
        headers: adminHeaders(serviceRoleKey, { 'Content-Type': 'application/json' }),
        body: JSON.stringify({ ban_duration: '876000h' })
      });
      if (!banResp.ok) throw new Error('Nu s-a putut dezactiva contul.');

      res.status(200).json({ ok: true });
      return;
    }

    res.status(400).json({ error: 'Acțiune necunoscută.' });
  } catch (err) {
    res.status(500).json({ error: err.message || 'Eroare necunoscută.' });
  }
};
