const express = require('express');
const { generateAnexa } = require('./lib/generate');

const app = express();
app.use(express.json({ limit: '5mb' }));

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
