// Must be required before anything requires 'sharp' anywhere in the app,
// so sharp's bundled fontconfig picks up our custom config before its first
// SVG render. Fixes watermark text rendering as empty boxes on hosts with
// no system fonts (e.g. Railway's minimal container — see
// assets/fonts/LICENSE.txt and git history around 2026-09-21).
const fs = require('fs');
const path = require('path');
const os = require('os');

const fontsDir = path.join(__dirname, '..', '..', 'assets', 'fonts');
const templatePath = path.join(fontsDir, 'fonts.conf');

// fontconfig's <dir> needs an absolute, runtime-known path, so the checked
// -in template is resolved into a generated copy under the OS tmp dir at
// startup rather than hardcoding a path that would only be correct on one
// machine.
const resolvedConfPath = path.join(os.tmpdir(), 'protected-viewer-fonts.conf');
const template = fs.readFileSync(templatePath, 'utf8');
fs.writeFileSync(resolvedConfPath, template.replace('__FONTS_DIR__', fontsDir));

process.env.FONTCONFIG_FILE = resolvedConfPath;
