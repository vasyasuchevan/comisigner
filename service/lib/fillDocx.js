const JSZip = require('jszip');

// Apply the template's replacement rules to word/document.xml and return a new .docx buffer.
// Returns { buffer, missing } — `missing` lists rules that matched nothing, so the caller can
// tell the office a field slot wasn't found (template drift) instead of silently shipping a gap.
async function fillDocx(docxBuffer, values, rules) {
  const zip = await JSZip.loadAsync(docxBuffer);
  const docXmlFile = zip.file('word/document.xml');
  if (!docXmlFile) throw new Error('invalid .docx: word/document.xml missing');

  let xml = await docXmlFile.async('string');
  const missing = [];

  for (const rule of rules) {
    let hit = false;
    xml = xml.replace(rule.re, function () {
      hit = true;
      // replace() callback args: (match, p1, p2, ..., offset, string). Drop the trailing two
      // so `m` is [match, p1, p2, ...] — same shape the build() functions expect.
      const m = Array.prototype.slice.call(arguments, 0, -2);
      return rule.build(values, m);
    });
    if (!hit) missing.push(rule.re.toString());
  }

  zip.file('word/document.xml', xml);
  const buffer = await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' });
  return { buffer, missing };
}

module.exports = { fillDocx };
