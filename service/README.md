# Anexa generator service

Server-side generator for COMILGA's CIM anexe. It fills a `.docx` template with the driver's
data, renders it to PDF with **LibreOffice** (so the company layout stays pixel-perfect — the
browser can't do this for text inside justified paragraphs), and stamps the worker's signature.

This runs as a small standalone service because LibreOffice can't live in a Vercel serverless
function. Everything else in ComiSigner is unchanged; the office calls this over HTTP.

## Why a service (and not the browser)

- The anexe are legal documents with fields *inside* justified paragraphs. Only a real layout
  engine (LibreOffice) places those correctly after filling. In-browser overlay can't.
- The office already needs a server round-trip for the automatic numbering (Supabase), so a
  small generation service is not extra architecture — it's where the perfect fill belongs.

## Run locally

```bash
npm install
# point at your LibreOffice (Linux containers have `soffice` on PATH already)
SOFFICE_BIN="C:/Program Files/LibreOffice/program/soffice.exe" PORT=8080 npm start
```

## Run with Docker

```bash
docker build -t comisigner-anexa .
docker run -p 8080:8080 comisigner-anexa
```

## Deploy to production (Render — easiest, no local Docker needed)

The office runs on HTTPS, so the service must too. Render builds the Dockerfile straight from
GitHub and gives you an HTTPS URL. Steps (all in the browser):

1. Go to **render.com** → sign in with the GitHub account that has the repo.
2. **New +** → **Blueprint** → pick this repo → **Apply**. (Render reads `render.yaml` at the
   repo root and creates the service from `service/`.)
   - Prefer clicking through instead? **New +** → **Web Service** → the repo → set
     **Root Directory** = `service`, **Runtime** = Docker → Create.
3. In the service's **Environment**, set:
   - `ALLOW_ORIGIN` = the office origin, e.g. `https://comisigner.vercel.app`
   - `API_KEY` = a long random string (the Blueprint generates one automatically).
4. Wait for the first deploy (LibreOffice makes the image large — a few minutes). Open the
   service URL + `/health` — it should return `{"ok":true}`.
5. In the office (`/office/anexe.html` → **Configurare serviciu**) paste the service URL and the
   same `API_KEY`.

**Plan/memory:** LibreOffice needs ~512 MB+ RAM. Render's free plan can run out of memory and
also sleeps when idle (slow first request). Use at least the **Starter** plan for real use.

Any host that runs a Docker container with HTTPS works the same way (Railway, Fly.io, Google
Cloud Run, a VPS with `docker run` behind a TLS proxy) — just set the two env vars.

## Environment variables

| Var | Purpose |
|-----|---------|
| `PORT` | Listen port (default 8080; hosts usually set this for you). |
| `SOFFICE_BIN` | Path to LibreOffice (default `soffice` on PATH; the container has it). |
| `ALLOW_ORIGIN` | CORS origin allowed to call the service (default `*`; set to the office origin). |
| `API_KEY` | If set, requests must send the same value as `X-Api-Key` (`/health` stays open). |

## API

`POST /generate/:type` (e.g. `/generate/anexa5`) → `application/pdf`

```jsonc
{
  "fields": {
    "reg_nr": "128", "act_nr": "45",          // from Supabase next_anexa_number()
    "cim_nr": "482", "cim_data": "12.02.2024", // from the worker's record
    "nume": "SUCEVAN VASILE",                  // nume + prenume, from the ID reader
    "cnp": "5020114226940",
    "ci_serie": "SV", "ci_nr": "654321",
    "data_azi": "27.07.2026"                    // optional; defaults to today
  },
  "signaturePngBase64": "data:image/png;base64,..."  // the worker's signature (optional)
}
```

`GET /health` → `{ "ok": true }`

## Adding an anexa

Drop the `.docx` in `templates/` and add a `config/<name>.js` describing its fill rules and
signature spots (see `config/anexa5.js`). No other code changes.

## Notes / TODO for production

- **Signature source**: the office passes the worker's signature PNG. Wiring it to ComiSigner's
  stored signature (Supabase `signatures` bucket) is done on the office side.
- **CIM number**: currently supplied as an input. It should come from the worker's real contract
  record, not the auto-counter (an act adițional must reference the actual CIM) — pending.
- Put the service behind auth (only the office should call it) before exposing it publicly.
