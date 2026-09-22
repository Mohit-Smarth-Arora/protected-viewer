const sharp = require('sharp');

// Escapes text for safe embedding inside an SVG <text> node.
function escapeXml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

// Every watermark carries this ownership line beneath the per-view
// email+timestamp label, on every asset type, per-request.
const OWNERSHIP_LINE = 'Solely Owned by Mohit Smarth Arora';

// Builds a repeating diagonal tiled watermark SVG covering the whole image.
// Repeating (not a single corner mark) matters: a corner watermark is trivially
// cropped out; a full tile survives cropping to any sub-region.
//
// `label` may be a single string or an array of lines — each line renders
// as its own <tspan> stacked under the tile's rotation, so e.g. the viewer's
// email+timestamp and the ownership line both appear in every tile.
function buildWatermarkSvg(width, height, label) {
  const lines = Array.isArray(label) ? label : [label];
  const safeLines = lines.map(escapeXml);
  const tileW = 340;
  const tileH = 170;
  const lineHeightPx = 22;
  const cols = Math.ceil(width / tileW) + 2;
  const rows = Math.ceil(height / tileH) + 2;

  let texts = '';
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const x = c * tileW - tileW / 2;
      const y = r * tileH;
      const tspans = safeLines
        .map((line, i) => `<tspan x="${x}" dy="${i === 0 ? 0 : lineHeightPx}">${line}</tspan>`)
        .join('');
      texts += `<text x="${x}" y="${y}" transform="rotate(-30 ${x} ${y})">${tspans}</text>`;
    }
  }

  return `
    <svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">
      <style>
        text {
          font-family: 'DejaVu Sans', sans-serif;
          font-size: 20px;
          fill: rgba(255,255,255,0.35);
          stroke: rgba(0,0,0,0.25);
          stroke-width: 0.5px;
        }
      </style>
      ${texts}
    </svg>
  `;
}

// Renders `label` (e.g. "user@example.com • 2026-09-21T12:00:00Z") as a
// tiled watermark composited onto the source image, server-side, before any
// bytes leave the server. The ownership line is always appended as a second
// line in every tile. Returns a Buffer (PNG).
async function watermarkImage(sourcePath, label) {
  const image = sharp(sourcePath);
  const metadata = await image.metadata();
  const width = metadata.width || 1024;
  const height = metadata.height || 768;

  const svg = buildWatermarkSvg(width, height, [label, OWNERSHIP_LINE]);
  const svgBuffer = Buffer.from(svg);

  return image
    .composite([{ input: svgBuffer, top: 0, left: 0 }])
    .png()
    .toBuffer();
}

// Extracts just the <text>...</text> tile markup from buildWatermarkSvg's
// output, so the code-snippet renderer can composite the same tiling logic
// as a background layer beneath the code text, at a different opacity/size
// canvas than watermarkImage uses. Keeps tile geometry in one place
// (buildWatermarkSvg) rather than duplicating the tiling math here.
function buildWatermarkTiles(width, height, label) {
  const full = buildWatermarkSvg(width, height, label);
  const match = full.match(/<style>[^]*<\/style>\s*([^]*)<\/svg>/);
  return match ? match[1] : '';
}

// Renders a code snippet (plain text) as a watermarked image so raw text
// never reaches the client. Uses SVG text layout — monospace, one <tspan>
// per line — rasterized to PNG by sharp. The ownership line is always
// appended to the per-view label, same as watermarkImage.
async function watermarkCodeSnippet(code, label, opts = {}) {
  const lines = code.split('\n');
  const fontSize = opts.fontSize || 16;
  const lineHeight = fontSize * 1.5;
  const charWidth = fontSize * 0.6;
  const padding = 32;

  const longestLine = lines.reduce((max, l) => Math.max(max, l.length), 0);
  const width = Math.ceil(padding * 2 + longestLine * charWidth);
  const height = Math.ceil(padding * 2 + lines.length * lineHeight);

  const codeLines = lines
    .map((line, i) => {
      const y = padding + (i + 1) * lineHeight - lineHeight * 0.3;
      return `<text x="${padding}" y="${y}" class="code">${escapeXml(line)}</text>`;
    })
    .join('');

  const watermarkTiles = buildWatermarkTiles(width, height, [label, OWNERSHIP_LINE]);

  const svg = `
    <svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">
      <rect width="100%" height="100%" fill="#1e1e1e"/>
      <style>
        .code { font-family: 'DejaVu Sans Mono', monospace; font-size: ${fontSize}px; fill: #d4d4d4; }
        .wm text { font-family: 'DejaVu Sans', sans-serif; font-size: 20px; fill: rgba(255,255,255,0.12); stroke: none; }
      </style>
      <g class="wm">${watermarkTiles}</g>
      ${codeLines}
    </svg>
  `;

  return sharp(Buffer.from(svg)).png().toBuffer();
}

// Builds the watermark overlay as a standalone HTML fragment: a fixed,
// full-viewport, pointer-events:none layer with a repeating diagonal tiled
// background (same visual language as the image/snippet watermark — a tiled
// mark survives cropping/scrolling, a single corner mark doesn't) plus a
// small fixed banner pinned to the top so it's visible even if the page's
// own background hides the tile. This is NOT pixel-baked — it's real DOM/CSS
// sitting on top of the page, so it's exactly as removable as any other
// element via devtools. Accepted tradeoff for this asset type (see db.js
// assets.type comment) — it deters casual screenshot/redistribution and
// keeps every view attributable, it does not prevent extraction by someone
// willing to open devtools.
function buildHtmlWatermarkOverlay(label) {
  const lines = [label, OWNERSHIP_LINE];
  const safeLines = lines.map(escapeXml);
  const tileText = safeLines.join(String.fromCharCode(10));

  // Reuses the same tiled-SVG approach as the image watermark, but as a CSS
  // background-image data URI on a fixed overlay div instead of a sharp
  // composite — same tiling geometry, different delivery mechanism.
  const tileSvg = `<svg xmlns='http://www.w3.org/2000/svg' width='340' height='170'>
    <text x='0' y='60' transform='rotate(-30 0 60)' font-family='DejaVu Sans, sans-serif' font-size='16' fill='rgba(120,120,120,0.28)'>
      <tspan x='0' dy='0'>${safeLines[0]}</tspan>
      <tspan x='0' dy='18'>${safeLines[1]}</tspan>
    </text>
  </svg>`;
  const encodedTile = Buffer.from(tileSvg).toString('base64');

  return `
<div id="__pv_watermark_overlay" style="
  position:fixed; inset:0; z-index:2147483647; pointer-events:none;
  background-image:url('data:image/svg+xml;base64,${encodedTile}');
  background-repeat:repeat;
"></div>
<div id="__pv_watermark_banner" style="
  position:fixed; top:0; left:0; right:0; z-index:2147483647; pointer-events:none;
  background:rgba(20,20,20,0.72); color:#fff; font:12px 'DejaVu Sans', sans-serif;
  padding:4px 10px; text-align:center; white-space:pre-line;
">${tileText}</div>
`;
}

// Blocks zoom gestures *inside the embedded page's content* — trackpad/touch
// pinch-zoom and Ctrl+scroll-wheel zoom, both of which zoom the page's own
// layout and visibly break it inside the app's iframe. Deliberately does
// NOT touch the browser's own zoom (Ctrl +/-/0, the browser's pinch-zoom
// on its chrome, view menu) — that's outside this document entirely and
// was explicitly asked to keep working.
//   - touch-action: pan-x pan-y on html/body tells the browser this page
//     doesn't want pinch-zoom gestures, the standard way to opt out of it.
//   - the wheel listener only preventDefault()s when ctrlKey is set (how
//     browsers signal "this scroll should zoom"), so normal scrolling is
//     completely unaffected.
const ZOOM_LOCK_SNIPPET = `
<style>html, body { touch-action: pan-x pan-y; }</style>
<script>
(function () {
  document.addEventListener('wheel', function (e) {
    if (e.ctrlKey) e.preventDefault();
  }, { passive: false });
})();
</script>
`;

// Inserts one or more HTML fragments right before </body> (so they render
// after — and, for the watermark, visually on top of — the page's own
// content), or appended at the end if the document has no </body> tag at
// all (e.g. a bare HTML fragment rather than a full document).
function injectBeforeBodyEnd(html, fragments) {
  const combined = fragments.join('\n');
  if (/<\/body>/i.test(html)) {
    return html.replace(/<\/body>/i, `${combined}</body>`);
  }
  return `${html}\n${combined}`;
}

// Prepares a served html asset: the zoom lock always applies (it's UX
// consistency, not part of the deterrence mechanism — see
// ZOOM_LOCK_SNIPPET comment), the watermark overlay only when
// [watermarked] is true (the per-viewer opt-out — see
// lib/folders.js shouldWatermarkHtmlFor).
function prepareHtmlAsset(html, label, watermarked) {
  const fragments = [ZOOM_LOCK_SNIPPET];
  if (watermarked) fragments.push(buildHtmlWatermarkOverlay(label));
  return injectBeforeBodyEnd(html, fragments);
}

module.exports = {
  watermarkImage,
  watermarkCodeSnippet,
  prepareHtmlAsset,
  OWNERSHIP_LINE,
};
