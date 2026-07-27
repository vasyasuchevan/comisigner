// Fill definition for Anexa 5 (Act Adițional – drepturi bănești deplasare).
// Each rule finds a blank (a run of underscores) in the .docx and replaces it, keeping the
// surrounding text. String.prototype.replace with a non-global RegExp replaces only the first
// match — so each rule fires once, in order. Adding a new anexa = a new config like this one.

module.exports = {
  templateFile: 'anexa5.docx',

  // Values the office must supply (besides the auto/derived ones).
  requiredFields: ['reg_nr', 'act_nr', 'cim_nr', 'cim_data', 'nume', 'cnp', 'ci_serie', 'ci_nr'],

  rules: [
    // Header registration + act numbers (dates = data_azi)
    { re: /(Înregistrat sub nr\. )_+( din data de )_+/, build: (v, m) => m[1] + v.reg_nr + m[2] + v.data_azi },
    { re: /(>nr\. )_+( din data de )_+(<)/, build: (v, m) => m[1] + v.act_nr + m[2] + v.data_azi + m[3] },
    { re: /(la Contractul Individual de Muncă nr\. )_+( din data de )_+/, build: (v, m) => m[1] + v.cim_nr + m[2] + v.cim_data },
    // SALARIATUL clause — identity
    { re: /(Dl\.\/Dna\. )_+/, build: (v, m) => m[1] + v.nume },
    { re: /(CNP )_+/, build: (v, m) => m[1] + v.cnp },
    { re: /(C\.I\. seria )_+( nr\. )_+/, build: (v, m) => m[1] + v.ci_serie + m[2] + v.ci_nr },
    { re: /(în baza Contractului Individual de Muncă nr\. )_+( din data de )_+/, build: (v, m) => m[1] + v.cim_nr + m[2] + v.cim_data },
    { re: /(Celelalte clauze ale Contractului Individual de Muncă nr\. )_+( \/ )_+/, build: (v, m) => m[1] + v.cim_nr + m[2] + v.cim_data },
    { re: /(Încheiat astăzi, )_+/, build: (v, m) => m[1] + v.data_azi },
    // Bottom SALARIAT name (a run that is ONLY underscores)
    { re: /(<w:t[^>]*>)_{25,}(<\/w:t>)/, build: (v, m) => m[1] + v.nume + m[2] },
    // Bottom "Data: __   Semnătura salariat: __" — fill the date, leave signature blank for the image
    { re: /(Data: )_+(\s+Semnătura salariat: )_+/, build: (v, m) => m[1] + v.data_azi }
  ],

  // Where the worker's signature image is stamped (PDF points, origin bottom-left; page is
  // 0-indexed). Two salariat spots on page 4.
  signatureSpots: [
    { page: 3, x: 350, y: 500, w: 115, h: 30 }, // SALARIAT block "Semnătura ____"
    { page: 3, x: 245, y: 368, w: 110, h: 26 }  // bottom "Semnătura salariat: ____"
  ]
};
