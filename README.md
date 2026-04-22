# The Goblet of Fire

A Harry Potter-themed random picker for the HRS Keycard dogfooding tournament. Team members cast their name into the goblet; when the appointed hour arrives, the flames choose a champion.

Single-file HTML. No build step. No framework.

## Files

| File | What it is |
|---|---|
| `goblet.html` | The app. Self-contained. Works standalone. |
| `supabase-setup.sql` | Optional: SQL to turn on shared team storage via Supabase. |

## How to run it

### 1. Local / single-device mode (works today, no setup)

Open `goblet.html` directly in a browser, or serve it:

```bash
python3 -m http.server 4747
# then visit http://localhost:4747/goblet.html
```

Everything works — casting, countdown, draw, reveal — but state lives in **that browser only**. Good for a single admin running the picker on screen-share while the team calls out names.

### 2. Host on GitHub Pages

```bash
git init
git add goblet.html README.md supabase-setup.sql
git commit -m "Goblet of Fire"
git remote add origin https://github.com/<you>/goblet-of-fire.git
git push -u origin main
```

Then GitHub → Settings → Pages → deploy from `main` / root. Link will be `https://<you>.github.io/goblet-of-fire/goblet.html`.

Without shared storage this is still single-device — each visitor's browser has its own goblet. See step 3 for real team play.

### 3. Shared team storage (Supabase, ~5 minutes)

1. Go to https://supabase.com, create a free project.
2. SQL Editor → New Query → paste the contents of `supabase-setup.sql`.
3. Before running, replace `CHANGE-ME-TO-A-LONG-RANDOM-STRING` on the last line with your own long admin key.
4. Run the query.
5. Project Settings → API → copy the **Project URL** and **anon public key**.
6. In `goblet.html` find `const CONFIG = { ... }` near the top of the `<script type="module">` block and fill in both values.
7. Redeploy (commit + push to GitHub Pages).

Now everyone's casts go to the same goblet.

## How people use it

- **Public URL** (what you share with the team): `https://<you>.github.io/goblet-of-fire/goblet.html`
  - Sees: count of names, countdown, lore text. Can cast a name. Cannot see who else cast.
- **Admin URL** (only you): `https://<you>.github.io/goblet-of-fire/goblet.html?admin=1&key=YOUR_ADMIN_KEY`
  - Additional: the name list, set draw time, empty the goblet, trigger the draw.

In local mode, `key=` can be anything (it's only validated against Supabase). In Supabase mode, it must match the admin key you seeded in step 3.

## Canon notes

Names are never readable by non-admin visitors. In local mode this is enforced client-side (the list is never rendered for public viewers). In Supabase mode it's enforced server-side by Row Level Security + `security definer` RPCs — the browser literally cannot query the names table.

Casting a duplicate name silently succeeds without telling you whether the name was new, so public visitors can't enumerate who's in.
