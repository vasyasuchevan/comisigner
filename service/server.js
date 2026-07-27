const express = require('express');
const { generateAnexa } = require('./lib/generate');

const app = express();
app.use(express.json({ limit: '5mb' }));

// CORS — the office (a browser app on a different origin) calls this service directly.
// Set ALLOW_ORIGIN to the office origin in production; defaults to * for local/dev.
const ALLOW_ORIGIN = process.env.ALLOW_ORIGIN || '*';
app.use((req, res, next) => {
  res.set('Access-Control-Allow-Origin', ALLOW_ORIGIN);
  res.set('Access-Control-Allow-Headers', 'Content-Type');
  res.set('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

app.get('/health', (req, res) => res.json({ ok: true }));

// POST /generate/anexa5
// body: { fields: { reg_nr, act_nr, cim_nr, cim_data, nume, cnp, ci_serie, ci_nr, data_azi? },
//         signaturePngBase64?: "data:image/png;base64,..." | "<base64>" }
// -> application/pdf
app.post('/generate/:type', async (req, res) => {
  try {
    const type = String(req.params.type).replace(/[^a-z0-9]/gi, ''); // guard require() path
    const body = req.body || {};
    const sig = body.signaturePngBase64
      ? Buffer.from(String(body.signaturePngBase64).replace(/^data:image\/\w+;base64,/, ''), 'base64')
      : null;

    const { pdf, unfilled } = await generateAnexa(type, body.fields || {}, sig);
    if (unfilled && unfilled.length) res.set('X-Unfilled-Slots', String(unfilled.length));
    res.set('Content-Type', 'application/pdf');
    res.set('Content-Disposition', 'inline; filename="' + type + '.pdf"');
    res.send(pdf);
  } catch (e) {
    res.status(400).json({ error: String((e && e.message) || e) });
  }
});

const port = process.env.PORT || 8080;
app.listen(port, () => console.log('anexa generator service listening on :' + port));
