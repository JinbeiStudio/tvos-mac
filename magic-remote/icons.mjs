// Writes the TV app's icons from the Apple TV icon, cropped to its artwork so it fills the tile like the other apps.
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const require = createRequire(import.meta.url);
const sharp = require('sharp');
const [out] = process.argv.slice(2);
const big = join(mkdtempSync(join(tmpdir(), 'tvicon-')), 'icon.png');
execFileSync('sips', ['-s', 'format', 'png', '/System/Applications/TV.app/Contents/Resources/AppIcon.icns', '--out', big]);
// The rounded corners become the icon's own dark colour, so the tile is a full square.
const trimmed = await sharp(big).trim({ threshold: 10 }).toBuffer();
const { width, height } = await sharp(trimmed).metadata();
// Drops the icon's rim and rounded corners, leaving only its dark face.
const inset = Math.round(width * 0.12);
const art = await sharp(trimmed).extract({ left: inset, top: inset, width: width - 2 * inset, height: height - 2 * inset }).toBuffer();
// Webos icons are flat, so each row's offset from the face's gradient is removed: the background becomes one solid tone, the logo keeps its own colours.
const flat = await sharp(art).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
const target = 47;
// The logo touches the sides on some rows, so each row takes whichever side edge continues the rows above (the gradient moves slowly).
const W = flat.info.width;
let previous = [target, target, target];
for (let y = 0; y < flat.info.height; y++) {
  const sides = [3, W - 4].map((x) => [0, 1, 2].map((c) => flat.data[(y * W + x) * 4 + c]));
  const bg = sides.reduce((best, side) => (Math.abs(side[0] - previous[0]) < Math.abs(best[0] - previous[0]) ? side : best));
  previous = bg;
  const shift = [0, 1, 2].map((c) => target - bg[c]);
  for (let x = 0; x < W; x++)
    for (let c = 0; c < 3; c++) {
      const i = (y * W + x) * 4 + c;
      flat.data[i] = Math.min(255, Math.max(0, flat.data[i] + shift[c]));
    }
}
const solid = await sharp(flat.data, { raw: flat.info }).png().toBuffer();
// Padding by copying the edge keeps the face's own gradient to the corners, so no flat dark corners show.
const w = width - 2 * inset;
const pad = Math.round(w * 0.1);
const padded = await sharp(solid).extend({ top: pad, bottom: pad, left: pad, right: pad, extendWith: 'copy' }).toBuffer();
for (const [name, size] of [['icon.png', 80], ['largeIcon.png', 130], ['miniIcon.png', 60]])
  await sharp(padded).resize(size, size, { fit: 'cover' }).flatten({ background: '#1c1c1e' }).png().toFile(join(out, name));
