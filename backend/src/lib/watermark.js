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

// Builds a repeating diagonal tiled watermark SVG covering the whole image.
// Repeating (not a single corner mark) matters: a corner watermark is trivially
// cropped out; a full tile survives cropping to any sub-region.
function buildWatermarkSvg(width, height, label) {
  const safeLabel = escapeXml(label);
  const tileW = 320;
  const tileH = 160;
  const cols = Math.ceil(width / tileW) + 2;
  const rows = Math.ceil(height / tileH) + 2;

  let texts = '';
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const x = c * tileW - tileW / 2;
      const y = r * tileH;
      texts += `<text x="${x}" y="${y}" transform="rotate(-30 ${x} ${y})">${safeLabel}</text>`;
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

// Renders `label` (e.g. "user@example.com • 2026-09-21T12:00:00Z • view#abc123")
// as a tiled watermark composited onto the source image, server-side, before
// any bytes leave the server. Returns a Buffer (PNG).
async function watermarkImage(sourcePath, label) {
  const image = sharp(sourcePath);
  const metadata = await image.metadata();
  const width = metadata.width || 1024;
  const height = metadata.height || 768;

  const svg = buildWatermarkSvg(width, height, label);
  const svgBuffer = Buffer.from(svg);

  return image
    .composite([{ input: svgBuffer, top: 0, left: 0 }])
    .png()
    .toBuffer();
}

// Renders a code snippet (plain text) as a watermarked image so raw text
// never reaches the client. Uses SVG text layout — monospace, one <tspan>
// per line — rasterized to PNG by sharp.
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

  const watermarkOverlay = buildWatermarkSvg(width, height, label)
    .replace('<svg', '<svg') // reuse tiles, composited as a second layer below
    .match(/<text[^]*?<\/text>/g) || [];

  const svg = `
    <svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">
      <rect width="100%" height="100%" fill="#1e1e1e"/>
      <style>
        .code { font-family: 'DejaVu Sans Mono', monospace; font-size: ${fontSize}px; fill: #d4d4d4; }
        .wm { font-family: 'DejaVu Sans', sans-serif; font-size: 20px; fill: rgba(255,255,255,0.12); }
      </style>
      <g class="wm">${watermarkOverlay.join('')}</g>
      ${codeLines}
    </svg>
  `;

  return sharp(Buffer.from(svg)).png().toBuffer();
}

module.exports = { watermarkImage, watermarkCodeSnippet };
