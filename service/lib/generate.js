const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFile } = require('child_process');
const { PDFDocument } = require('pdf-lib');
const { fillDocx } = require('./fillDocx');

// LibreOffice binary. On the container it's `soffice` on PATH; locally override via env,
// e.g. SOFFICE_BIN="C:/Program Files/LibreOffice/program/soffice.exe".
const SOFFICE = process.env.SOFFICE_BIN || 'soffice';

function convertToPdf(docxPath, outDir) {
  // Each conversion gets its own LibreOffice user profile — headless soffice is otherwise a
  // single instance and concurrent requests would clash. pathToFileURL keeps it cross-platform.
  const profileUrl = require('url').pathToFileURL(path.join(outDir, 'loprofile')).href;
  return new Promise((resolve, reject) => {
    execFile(SOFFICE, ['-env:UserInstallation=' + profileUrl, '--headless', '--convert-to', 'pdf', '--outdir', outDir, docxPath],
      { timeout: 60000 }, (err, stdout, stderr) => {
        if (err) return reject(new Error('LibreOffice convert failed: ' + (stderr || err.message)));
        const outPdf = path.join(outDir, path.basename(docxPath).replace(/\.docx$/i, '.pdf'));
        if (!fs.existsSync(outPdf)) return reject(new Error('LibreOffice produced no PDF'));
        resolve(outPdf);
      });
  });
}

async function stampSignature(pdfBuffer, signaturePng, spots) {
  if (!signaturePng || !spots || !spots.length) return pdfBuffer;
  const doc = await PDFDocument.load(pdfBuffer);
  const png = await doc.embedPng(signaturePng);
  const pages = doc.getPages();
  for (const s of spots) {
    const page = pages[s.page];
    if (!page) continue;
    const scale = Math.min(s.w / png.width, s.h / png.height);
    page.drawImage(png, { x: s.x, y: s.y, width: png.width * scale, height: png.height * scale });
  }
  return Buffer.from(await doc.save());
}

function todayRo() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return p(d.getDate()) + '.' + p(d.getMonth() + 1) + '.' + d.getFullYear();
}

// Generate one filled (and optionally signed) anexa PDF.
//   type            e.g. 'anexa5' (a file under config/)
//   fields          the values to fill; data_azi defaults to today
//   signaturePng    Buffer of the worker's signature PNG (optional)
async function generateAnexa(type, fields, signaturePng) {
  const cfg = require('../config/' + type);
  const values = Object.assign({ data_azi: todayRo() }, fields || {});

  const missingInput = (cfg.requiredFields || []).filter((f) => !values[f] && values[f] !== 0);
  if (missingInput.length) throw new Error('missing fields: ' + missingInput.join(', '));

  const tplPath = path.join(__dirname, '..', 'templates', cfg.templateFile);
  const { buffer: filledDocx, missing } = await fillDocx(fs.readFileSync(tplPath), values, cfg.rules);

  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'anexa-'));
  try {
    const docxPath = path.join(work, type + '.docx');
    fs.writeFileSync(docxPath, filledDocx);
    const pdfPath = await convertToPdf(docxPath, work);
    let pdf = fs.readFileSync(pdfPath);
    pdf = await stampSignature(pdf, signaturePng, cfg.signatureSpots);
    return { pdf, unfilled: missing };
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
}

module.exports = { generateAnexa, todayRo };
