/**
 * ThumbHash 算法实现
 *
 * 移植自 Happy 项目 (MIT License)
 * 将 RGBA 像素数据编码为 ~28 字节的紧凑模糊图哈希。
 * 客户端可用此哈希即时渲染模糊占位图，无需任何 HTTP 请求。
 */

/**
 * @param w - 图片宽度 (≤100)
 * @param h - 图片高度 (≤100)
 * @param rgba - RGBA 像素数据
 * @returns ThumbHash 二进制 (~28 字节)
 */
export function thumbhash(w: number, h: number, rgba: Buffer): Uint8Array {
  if (w > 100 || h > 100) throw new Error(`${w}x${h} doesn't fit in 100x100`);
  const { PI, round, max, cos, abs } = Math;

  let avg_r = 0, avg_g = 0, avg_b = 0, avg_a = 0;
  for (let i = 0, j = 0; i < w * h; i++, j += 4) {
    const alpha = rgba[j + 3] / 255;
    avg_r += alpha / 255 * rgba[j];
    avg_g += alpha / 255 * rgba[j + 1];
    avg_b += alpha / 255 * rgba[j + 2];
    avg_a += alpha;
  }
  if (avg_a) {
    avg_r /= avg_a;
    avg_g /= avg_a;
    avg_b /= avg_a;
  }

  const hasAlpha = avg_a < w * h;
  const l_limit = hasAlpha ? 5 : 7;
  const lx = max(1, round(l_limit * w / max(w, h)));
  const ly = max(1, round(l_limit * h / max(w, h)));
  const l: number[] = [];
  const p: number[] = [];
  const q: number[] = [];
  const a: number[] = [];

  for (let i = 0, j = 0; i < w * h; i++, j += 4) {
    const alpha = rgba[j + 3] / 255;
    const r = avg_r * (1 - alpha) + alpha / 255 * rgba[j];
    const g = avg_g * (1 - alpha) + alpha / 255 * rgba[j + 1];
    const b = avg_b * (1 - alpha) + alpha / 255 * rgba[j + 2];
    l[i] = (r + g + b) / 3;
    p[i] = (r + g) / 2 - b;
    q[i] = r - g;
    a[i] = alpha;
  }

  const encodeChannel = (channel: number[], nx: number, ny: number): [number, number[], number] => {
    let dc = 0;
    const ac: number[] = [];
    let scale = 0;
    const fx: number[] = [];
    for (let cy = 0; cy < ny; cy++) {
      for (let cx = 0; cx * ny < nx * (ny - cy); cx++) {
        let f = 0;
        for (let x = 0; x < w; x++)
          fx[x] = cos(PI / w * cx * (x + 0.5));
        for (let y = 0; y < h; y++)
          for (let x = 0, fy = cos(PI / h * cy * (y + 0.5)); x < w; x++)
            f += channel[x + y * w] * fx[x] * fy;
        f /= w * h;
        if (cx || cy) {
          ac.push(f);
          scale = max(scale, abs(f));
        } else {
          dc = f;
        }
      }
    }
    if (scale)
      for (let i = 0; i < ac.length; i++)
        ac[i] = 0.5 + 0.5 / scale * ac[i];
    return [dc, ac, scale];
  };

  const [l_dc, l_ac, l_scale] = encodeChannel(l, max(3, lx), max(3, ly));
  const [p_dc, p_ac, p_scale] = encodeChannel(p, 3, 3);
  const [q_dc, q_ac, q_scale] = encodeChannel(q, 3, 3);
  const [a_dc, a_ac, a_scale] = hasAlpha ? encodeChannel(a, 5, 5) : [0, [0], 0];

  const isLandscape = w > h;
  const header24 = round(63 * l_dc) | (round(31.5 + 31.5 * p_dc) << 6) | (round(31.5 + 31.5 * q_dc) << 12) | (round(31 * l_scale) << 18) | ((hasAlpha ? 1 : 0) << 23);
  const header16 = (isLandscape ? ly : lx) | (round(63 * p_scale) << 3) | (round(63 * q_scale) << 9) | ((isLandscape ? 1 : 0) << 15);
  const hash: number[] = [header24 & 255, (header24 >> 8) & 255, header24 >> 16, header16 & 255, header16 >> 8];
  const ac_start = hasAlpha ? 6 : 5;
  let ac_index = 0;
  if (hasAlpha) {
    hash.push(round(15 * a_dc) | (round(15 * a_scale) << 4));
  }

  for (const ac of hasAlpha ? [l_ac, p_ac, q_ac, a_ac] : [l_ac, p_ac, q_ac]) {
    for (const f of ac) {
      hash[ac_start + (ac_index >> 1)] |= round(15 * f) << ((ac_index++ & 1) << 2);
    }
  }
  return new Uint8Array(hash);
}
