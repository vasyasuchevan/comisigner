---
name: supabase-migration
description: Write and hand off a Supabase SQL migration for the ComiSigner project. Use whenever a schema change, new table, new RLS policy, new trigger, or new RPC function is needed — especially for the roles/admin platform, trip/folder batch signing, and any other schema growth on this project.
---

# ComiSigner Supabase migrations

This project's Supabase database is only reachable from application code through the anon (publishable) key — there is no service_role key available, and that's a deliberate boundary, never ask the user for it. Any schema change — new table, column, RLS policy, trigger, or RPC function — has to be written as plain SQL and handed to the user to run themselves in the Supabase SQL Editor (which runs as the postgres role and bypasses RLS).

## What to always do

- Write the full migration as one or more copy-pasteable SQL blocks, not a diff or a description of what to do. The user pastes this straight into the SQL Editor.
- Explain in plain language what each block does and why, right above it — the user isn't a programmer.
- Think through RLS explicitly for anything new: which role (anon / authenticated / a new role like hr or admin) can insert/select/update/delete, and confirm that matches the intended access model before handing it over. This project's whole security pitch rests on RLS being scoped correctly — get it right in the SQL text itself, don't leave it as a TODO.
- If a trigger needs to read/write a table the calling role doesn't have direct rights to (like the existing `compute_chain_hash` trigger), mark it `security definer` and say so explicitly — this project has hit exactly that bug before (anon INSERT failing because a trigger's internal SELECT had no grant).
- Watch for RLS + `.select()` after an anonymous INSERT — requesting the row back requires SELECT rights the anon role deliberately doesn't have. Generate IDs client-side with `crypto.randomUUID()` before inserting instead of asking the DB to return them.
- Ask the user to confirm they've run it and report back before assuming the schema is live — there's no way to verify from the app side without the user's confirmation.

## Now that roles are being added (admin / HR / driver)

Design RLS per-role from the start rather than retrofitting: decide exactly what HR can and can't touch versus admin before writing the policy, not after. The interesting bugs in a role-based system are usually permission leaks (a narrower role can do something it shouldn't), not permission blocks — so when reviewing a new policy, actively try to think of what the *weakest* role could get away with.
