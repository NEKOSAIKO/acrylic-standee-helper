/* Acrylic stand geometry demo. Local, dependency-free raster-to-vector geometry.
 * All public output coordinates are millimetres, with y increasing downwards.
 * This is an image-resolution approximation, not a certified CAM kernel.
 */
(function (root) {
  'use strict';

  const finite = (value, fallback) => Number.isFinite(Number(value)) ? Number(value) : fallback;
  const clamp = (value, lo, hi) => Math.max(lo, Math.min(hi, value));
  const fmt = value => Number(value.toFixed(3));

  function boundsOfMask(mask, width, height) {
    let minX = width, minY = height, maxX = -1, maxY = -1;
    for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
      if (!mask[y * width + x]) continue;
      minX = Math.min(minX, x); maxX = Math.max(maxX, x);
      minY = Math.min(minY, y); maxY = Math.max(maxY, y);
    }
    return maxX < minX ? null : { minX, minY, maxX, maxY, width: maxX - minX + 1, height: maxY - minY + 1 };
  }

  function fromAlpha(width, height, alpha) {
    width = Math.floor(width); height = Math.floor(height);
    if (width < 1 || height < 1 || width * height > 16000000 || !alpha || alpha.length !== width * height) {
      throw new Error('透明度图像尺寸无效。');
    }
    const hasTransparency = alpha.some(value => value < 250);
    return { width, height, alpha: new Uint8Array(alpha), imageDataURL: null, originalWidth: width, originalHeight: height, transparent: hasTransparency, hasTransparency };
  }

  function fromImage(image, maxSide = 480) {
    if (typeof document === 'undefined') throw new Error('fromImage 需要浏览器画布。');
    const originalWidth = image.naturalWidth || image.width;
    const originalHeight = image.naturalHeight || image.height;
    if (!originalWidth || !originalHeight) throw new Error('请先载入一张带透明底的图片。');
    maxSide = clamp(Math.round(finite(maxSide, 480)), 64, 960);
    const ratio = Math.min(1, maxSide / Math.max(originalWidth, originalHeight));
    const canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(originalWidth * ratio));
    canvas.height = Math.max(1, Math.round(originalHeight * ratio));
    const context = canvas.getContext('2d', { willReadFrequently: true });
    context.drawImage(image, 0, 0, canvas.width, canvas.height);
    const rgba = context.getImageData(0, 0, canvas.width, canvas.height).data;
    const alpha = new Uint8Array(canvas.width * canvas.height);
    let transparentPixels = 0;
    for (let i = 0; i < alpha.length; i++) {
      alpha[i] = rgba[i * 4 + 3];
      if (alpha[i] < 250) transparentPixels++;
    }
    const bounds = boundsOfMask(alpha, canvas.width, canvas.height);
    if (!bounds) throw new Error('图片完全透明，没有可提取的轮廓。');
    const cropped = document.createElement('canvas');
    cropped.width = bounds.width; cropped.height = bounds.height;
    cropped.getContext('2d').drawImage(canvas, bounds.minX, bounds.minY, bounds.width, bounds.height, 0, 0, bounds.width, bounds.height);
    const croppedAlpha = new Uint8Array(bounds.width * bounds.height);
    for (let y = 0; y < bounds.height; y++) {
      croppedAlpha.set(alpha.subarray((y + bounds.minY) * canvas.width + bounds.minX, (y + bounds.minY) * canvas.width + bounds.maxX + 1), y * bounds.width);
    }
    return {
      width: bounds.width, height: bounds.height, alpha: croppedAlpha,
      imageCanvas: cropped, imageDataURL: cropped.toDataURL('image/png'),
      originalWidth, originalHeight, transparent: transparentPixels > 0, hasTransparency: transparentPixels > 0,
      sourcePixelScale: 1 / ratio
    };
  }

  // Border flood fill: only enclosed background is filled; open notches remain open.
  function fillHoles(mask, width, height) {
    const output = new Uint8Array(mask), outside = new Uint8Array(mask.length);
    const queue = new Int32Array(mask.length);
    let head = 0, tail = 0;
    function add(i) { if (!mask[i] && !outside[i]) { outside[i] = 1; queue[tail++] = i; } }
    for (let x = 0; x < width; x++) { add(x); add((height - 1) * width + x); }
    for (let y = 1; y < height - 1; y++) { add(y * width); add(y * width + width - 1); }
    while (head < tail) {
      const i = queue[head++], x = i % width;
      if (x) add(i - 1); if (x < width - 1) add(i + 1);
      if (i >= width) add(i - width); if (i < mask.length - width) add(i + width);
    }
    for (let i = 0; i < output.length; i++) if (!outside[i]) output[i] = 1;
    return output;
  }

  function componentInfo(mask, width, height) {
    const seen = new Uint8Array(mask.length), queue = new Int32Array(mask.length), areas = [];
    for (let seed = 0; seed < mask.length; seed++) {
      if (!mask[seed] || seen[seed]) continue;
      let head = 0, tail = 0; queue[tail++] = seed; seen[seed] = 1;
      while (head < tail) {
        const i = queue[head++], x = i % width, y = Math.floor(i / width);
        for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
          if ((!dx && !dy) || x + dx < 0 || x + dx >= width || y + dy < 0 || y + dy >= height) continue;
          const j = i + dy * width + dx;
          if (mask[j] && !seen[j]) { seen[j] = 1; queue[tail++] = j; }
        }
      }
      areas.push(tail);
    }
    areas.sort((a, b) => b - a);
    return { count: areas.length, areas };
  }

  // Felzenszwalb/Huttenlocher separable exact squared Euclidean distance transform.
  function distanceSquared(mask, width, height, target) {
    const size = Math.max(width, height), f = new Float64Array(size), d = new Float64Array(size);
    const v = new Int32Array(size), z = new Float64Array(size + 1);
    const temp = new Float32Array(mask.length), output = new Float32Array(mask.length);
    const far = 1e10;
    function transform(n) {
      let k = 0; v[0] = 0; z[0] = -Infinity; z[1] = Infinity;
      for (let q = 1; q < n; q++) {
        let s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * (q - v[k]));
        while (s <= z[k]) {
          k--;
          s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * (q - v[k]));
        }
        k++; v[k] = q; z[k] = s; z[k + 1] = Infinity;
      }
      k = 0;
      for (let q = 0; q < n; q++) { while (z[k + 1] < q) k++; d[q] = (q - v[k]) * (q - v[k]) + f[v[k]]; }
    }
    for (let x = 0; x < width; x++) {
      for (let y = 0; y < height; y++) f[y] = !!mask[y * width + x] === !!target ? 0 : far;
      transform(height);
      for (let y = 0; y < height; y++) temp[y * width + x] = d[y];
    }
    for (let y = 0; y < height; y++) {
      const row = y * width;
      for (let x = 0; x < width; x++) f[x] = temp[row + x];
      transform(width);
      for (let x = 0; x < width; x++) output[row + x] = d[x];
    }
    return output;
  }

  function signedField(mask, width, height) {
    const toInside = distanceSquared(mask, width, height, true);
    const toOutside = distanceSquared(mask, width, height, false);
    for (let i = 0; i < mask.length; i++) toInside[i] = mask[i] ? Math.sqrt(toOutside[i]) - 0.5 : 0.5 - Math.sqrt(toInside[i]);
    return toInside;
  }

  function closeMask(mask, width, height, radius) {
    if (radius < 0.7) return mask;
    const toInside = distanceSquared(mask, width, height, true), expanded = new Uint8Array(mask.length), limit = radius * radius;
    for (let i = 0; i < mask.length; i++) expanded[i] = toInside[i] <= limit ? 1 : 0;
    const toOutside = distanceSquared(expanded, width, height, false);
    for (let i = 0; i < mask.length; i++) expanded[i] = mask[i] || toOutside[i] > limit ? 1 : 0;
    return expanded;
  }

  function fillFieldHoles(field, width, height) {
    const mask = new Uint8Array(field.length);
    for (let i = 0; i < field.length; i++) mask[i] = field[i] >= 0 ? 1 : 0;
    const solid = fillHoles(mask, width, height);
    for (let i = 0; i < field.length; i++) if (solid[i] && !mask[i]) field[i] = 0.5;
  }

  function contours(field, width, height) {
    const nodes = new Map(), horizontalCount = (width - 1) * height;
    function connect(idA, pointA, idB, pointB) {
      let a = nodes.get(idA), b = nodes.get(idB);
      if (!a) { a = { point: pointA, neighbors: [] }; nodes.set(idA, a); }
      if (!b) { b = { point: pointB, neighbors: [] }; nodes.set(idB, b); }
      a.neighbors.push(idB); b.neighbors.push(idA);
    }
    const basic = { 1: [3, 0], 2: [0, 1], 3: [3, 1], 4: [1, 2], 6: [0, 2], 7: [3, 2], 8: [2, 3], 9: [0, 2], 11: [1, 2], 12: [1, 3], 13: [0, 1], 14: [3, 0] };
    for (let y = 0; y < height - 1; y++) for (let x = 0; x < width - 1; x++) {
      if(x===0 && y%32===0)cancelled();
      const i = y * width + x;
      const values = [field[i], field[i + 1], field[i + width + 1], field[i + width]];
      const code = (values[0] >= 0 ? 1 : 0) | (values[1] >= 0 ? 2 : 0) | (values[2] >= 0 ? 4 : 0) | (values[3] >= 0 ? 8 : 0);
      if (!code || code === 15) continue;
      let edges = basic[code];
      if (code === 5) edges = values[0] + values[1] + values[2] + values[3] > 0 ? [3, 2, 0, 1] : [3, 0, 1, 2];
      if (code === 10) edges = values[0] + values[1] + values[2] + values[3] > 0 ? [0, 3, 1, 2] : [0, 1, 2, 3];
      function edge(e) {
        const a = e, b = (e + 1) % 4;
        const t = values[a] / (values[a] - values[b]);
        if (e === 0) return [y * (width - 1) + x, [x + t, y]];
        if (e === 1) return [horizontalCount + y * width + x + 1, [x + 1, y + t]];
        if (e === 2) return [(y + 1) * (width - 1) + x, [x + 1 - t, y + 1]];
        return [horizontalCount + y * width + x, [x, y + 1 - t]];
      }
      for (let e = 0; e < edges.length; e += 2) { const a = edge(edges[e]), b = edge(edges[e + 1]); connect(a[0], a[1], b[0], b[1]); }
    }
    const visited = new Set(), loops = [];
    for (const [seed] of nodes) {
      if (visited.has(seed)) continue;
      const loop = []; let current = seed, previous = -1, closed = false;
      for (let guard = 0; guard <= nodes.size; guard++) {
        if (current === seed && loop.length) { closed = true; break; }
        if (visited.has(current)) break;
        const node = nodes.get(current); if (!node) break;
        loop.push(node.point); visited.add(current);
        const next = node.neighbors.find(n => n !== previous);
        if (next === undefined) break;
        previous = current; current = next;
      }
      if (closed && loop.length >= 3) loops.push(loop);
    }
    return loops;
  }

  function loopBounds(loops) {
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const loop of loops) for (const [x, y] of loop) {
      minX = Math.min(minX, x); minY = Math.min(minY, y); maxX = Math.max(maxX, x); maxY = Math.max(maxY, y);
    }
    return { minX, minY, maxX, maxY, width: maxX - minX, height: maxY - minY };
  }

  function simplifyOpen(points, tolerance) {
    if (points.length <= 2) return points;
    const keep = new Uint8Array(points.length); keep[0] = keep[points.length - 1] = 1;
    const stack = [[0, points.length - 1]], limit = tolerance * tolerance;
    while (stack.length) {
      const [start, end] = stack.pop(), a = points[start], b = points[end];
      const dx = b[0] - a[0], dy = b[1] - a[1], lengthSquared = dx * dx + dy * dy;
      let maxDistance = limit, found = -1;
      for (let i = start + 1; i < end; i++) {
        const p = points[i], t = lengthSquared ? clamp(((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / lengthSquared, 0, 1) : 0;
        const ex = p[0] - a[0] - dx * t, ey = p[1] - a[1] - dy * t, distance = ex * ex + ey * ey;
        if (distance > maxDistance) { maxDistance = distance; found = i; }
      }
      if (found >= 0) { keep[found] = 1; stack.push([start, found], [found, end]); }
    }
    return points.filter((_, i) => keep[i]);
  }

  function simplifyLoop(points, tolerance) {
    const extremes = [0, 0, 0, 0];
    points.forEach((p, i) => {
      if (p[0] < points[extremes[0]][0]) extremes[0] = i;
      if (p[0] > points[extremes[1]][0]) extremes[1] = i;
      if (p[1] < points[extremes[2]][1]) extremes[2] = i;
      if (p[1] > points[extremes[3]][1]) extremes[3] = i;
    });
    const cuts = [...new Set(extremes)].sort((a, b) => a - b), output = [];
    if (cuts.length < 2) return points;
    for (let i = 0; i < cuts.length; i++) {
      const start = cuts[i], end = cuts[(i + 1) % cuts.length];
      const segment = end > start ? points.slice(start, end + 1) : points.slice(start).concat(points.slice(0, end + 1));
      output.push(...simplifyOpen(segment, tolerance).slice(0, -1));
    }
    return output;
  }

  function pathsFromLoops(loops, pixelMm, originX, originY, rounding) {
    const position = point => `${fmt((point[0] - originX) * pixelMm)} ${fmt((point[1] - originY) * pixelMm)}`;
    return loops.map(loop => {
      const points = simplifyLoop(loop, 0.17), bounds = loopBounds([points]), count = points.length;
      const corners = points.map((p, i) => {
        const before = points[(i + count - 1) % count], after = points[(i + 1) % count];
        const left = Math.hypot(before[0] - p[0], before[1] - p[1]), right = Math.hypot(after[0] - p[0], after[1] - p[1]);
        const extreme = Math.abs(p[0] - bounds.minX) < 1e-5 || Math.abs(p[0] - bounds.maxX) < 1e-5 || Math.abs(p[1] - bounds.minY) < 1e-5 || Math.abs(p[1] - bounds.maxY) < 1e-5;
        const distance = extreme ? 0 : Math.min(rounding, left * 0.34, right * 0.34);
        return {
          point: p,
          entry: left ? [p[0] + (before[0] - p[0]) * distance / left, p[1] + (before[1] - p[1]) * distance / left] : p,
          exit: right ? [p[0] + (after[0] - p[0]) * distance / right, p[1] + (after[1] - p[1]) * distance / right] : p,
          distance
        };
      });
      let path = `M ${position(corners[0].exit)}`;
      for (let i = 1; i <= count; i++) {
        const corner = corners[i % count];
        path += ` L ${position(corner.entry)}`;
        if (corner.distance) path += ` Q ${position(corner.point)} ${position(corner.exit)}`;
      }
      return path + ' Z';
    }).join(' ');
  }

  function roundedRectField(x, y, rect) {
    const radius = rect.radius, halfW = rect.width / 2, halfH = rect.height / 2;
    const qx = Math.abs(x - rect.x - halfW) - halfW + radius;
    const qy = Math.abs(y - rect.y - halfH) - halfH + radius;
    return radius - Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) - Math.min(Math.max(qx, qy), 0);
  }

  function rectanglePath(rect) {
    const { x, y, width: w, height: h, radius: r } = rect, n = fmt;
    return `M ${n(x + r)} ${n(y)} H ${n(x + w - r)} Q ${n(x + w)} ${n(y)} ${n(x + w)} ${n(y + r)} V ${n(y + h - r)} Q ${n(x + w)} ${n(y + h)} ${n(x + w - r)} ${n(y + h)} H ${n(x + r)} Q ${n(x)} ${n(y + h)} ${n(x)} ${n(y + h - r)} V ${n(y + r)} Q ${n(x)} ${n(y)} ${n(x + r)} ${n(y)} Z`;
  }

  function resampleLoop(loop, step) {
    const output = [];
    let carried = 0;
    for (let i = 0; i < loop.length; i++) {
      const a = loop[i], b = loop[(i + 1) % loop.length], length = Math.hypot(b[0] - a[0], b[1] - a[1]);
      if (!length) continue;
      let distance = carried;
      while (distance < length) {
        output.push([a[0] + (b[0] - a[0]) * distance / length, a[1] + (b[1] - a[1]) * distance / length]);
        distance += step;
      }
      carried = distance - length;
    }
    return output;
  }

  function detectNotchesAtScale(loops, pixelMm, bridgeWidth, maxNotchDepth, toolDiameter, look) {
    const found = []; found.rejected = [];
    const sampleMm = 0.5;
    for (const loop of loops) {
      const points = resampleLoop(loop, sampleMm / pixelMm), n = points.length;
      if (n < 16) continue;
      let area = 0;
      for (let i = 0; i < n; i++) { const a = points[i], b = points[(i + 1) % n]; area += a[0] * b[1] - b[0] * a[1]; }
      const orientation = area >= 0 ? 1 : -1, curvature = new Float32Array(n);
      const at = i => points[(i % n + n) % n];
      for (let i = 0; i < n; i++) {
        const a = at(i - look), b = at(i), c = at(i + look);
        const ax = b[0] - a[0], ay = b[1] - a[1], bx = c[0] - b[0], by = c[1] - b[1];
        curvature[i] = Math.atan2(ax * by - ay * bx, ax * bx + ay * by) * orientation;
      }
      const used = new Uint8Array(n);
      const bottoms = [];
      for (let i = 0; i < n; i++) {
        if (curvature[i] > -0.2) continue;
        let lowest = true;
        for (let d = -5; d <= 5; d++) if (curvature[(i + d + n) % n] < curvature[i]) lowest = false;
        if (lowest) bottoms.push(i);
      }
      bottoms.sort((a, b) => curvature[a] - curvature[b]);
      for (const bottom of bottoms) {
        cancelled();
        if (used[bottom]) continue;
        const maxTravel = Math.min(Math.floor(n / 3), Math.ceil(bridgeWidth * 2.2 / sampleMm));
        let left = 0, right = 0;
        for (let d = look; d <= maxTravel; d++) if (curvature[(bottom - d + n) % n] > 0.22) { left = d; break; }
        for (let d = look; d <= maxTravel; d++) if (curvature[(bottom + d) % n] > 0.22) { right = d; break; }
        if (!left || !right) continue;
        // Use the convex shoulder apex, not the first rising curvature sample.
        function shoulder(distance, direction) {
          let best = distance;
          for (let d = distance; d <= Math.min(distance + 8, maxTravel); d++) {
            if (curvature[(bottom + direction * d + n) % n] > curvature[(bottom + direction * best + n) % n]) best = d;
          }
          return best;
        }
        left = shoulder(left, -1); right = shoulder(right, 1);
        let start = bottom - left, end = bottom + right, a = at(start), b = at(end);
        let chord = Math.hypot(b[0] - a[0], b[1] - a[1]), mouth = chord * pixelMm;
        const arc = (left + right) * sampleMm;
        if (mouth > bridgeWidth || mouth < Math.max(0.4, pixelMm * 2) || arc > bridgeWidth * 3.2) continue;
        let nx = -(b[1] - a[1]) / chord * orientation, ny = (b[0] - a[0]) / chord * orientation;
        let depth = 0, opposite = 0;
        let oldArc = [];
        for (let j = start; j <= end; j++) {
          const p = at(j), distance = ((p[0] - a[0]) * nx + (p[1] - a[1]) * ny) * pixelMm;
          depth = Math.max(depth, distance); opposite = Math.max(opposite, -distance); oldArc.push(p);
        }
        if (depth <= maxNotchDepth + 0.7 || depth > bridgeWidth * 1.25 || opposite > 0.8) continue;
        const originalDepthMm = depth;
        // Search nearby convex shoulders for a shallow, tangent-continuous arc.
        // This changes a narrow deep V into a broad transition rather than just rounding its tip.
        let tangentControl = null, selectedRadiusMm = 0;
        const maxExtend = Math.ceil(Math.min(18, bridgeWidth) / sampleMm);
        outer: for (let total = 0; total <= maxExtend * 2; total++) {
          for (let dl = Math.max(0, total - maxExtend); dl <= Math.min(total, maxExtend); dl++) {
            const dr = total - dl, s = start - dl, e = end + dr, p = at(s), q = at(e);
            const length = Math.hypot(q[0] - p[0], q[1] - p[1]);
            if (length * pixelMm > bridgeWidth) continue;
            const u = [at(s + 2)[0] - at(s - 2)[0], at(s + 2)[1] - at(s - 2)[1]];
            const v = [at(e + 2)[0] - at(e - 2)[0], at(e + 2)[1] - at(e - 2)[1]];
            const cross = u[0] * v[1] - u[1] * v[0];
            if (Math.abs(cross) < 1e-6) continue;
            const dx = q[0] - p[0], dy = q[1] - p[1];
            // A cutter bridge must progress from one shoulder to the other.
            // Opposing tangents made the old candidate fold back into a tiny beak.
            if (u[0] * dx + u[1] * dy <= 0 || v[0] * dx + v[1] * dy <= 0) continue;
            const tu = (dx * v[1] - dy * v[0]) / cross, tv = (dx * u[1] - dy * u[0]) / cross;
            if (tu <= 0 || tv >= 0) continue;
            const control = [p[0] + u[0] * tu, p[1] + u[1] * tu];
            // Also forbid a return along either screen axis. A positive chord
            // projection alone still allowed a small leftward hook under headphones.
            if (control[0] < Math.min(p[0], q[0]) - 0.05 || control[0] > Math.max(p[0], q[0]) + 0.05 || control[1] < Math.min(p[1], q[1]) - 0.05 || control[1] > Math.max(p[1], q[1]) + 0.05) continue;
            const projection = ((control[0] - p[0]) * dx + (control[1] - p[1]) * dy) / (length * length);
            if (projection <= 0.025 || projection >= 0.975) continue;
            const sag = ((control[0] - p[0]) * (-dy / length * orientation) + (control[1] - p[1]) * (dx / length * orientation)) * pixelMm / 2;
            // maxNotchDepth triggers repair of a deep recess; it is not a cap on
            // the sag of a broad smooth transition between relocated shoulders.
            if (sag < 0 || sag > Math.max(maxNotchDepth, toolDiameter * 1.5) || Math.hypot(control[0] - p[0], control[1] - p[1]) > length * 2 || Math.hypot(control[0] - q[0], control[1] - q[1]) > length * 2) continue;
            let minimumRadiusMm = Infinity;
            const ddx = 2 * (q[0] - 2 * control[0] + p[0]), ddy = 2 * (q[1] - 2 * control[1] + p[1]);
            for (let sample = 0; sample <= 40; sample++) {
              const t = sample / 40;
              const vx = 2 * ((1 - t) * (control[0] - p[0]) + t * (q[0] - control[0]));
              const vy = 2 * ((1 - t) * (control[1] - p[1]) + t * (q[1] - control[1]));
              const crossDerivative = Math.abs(vx * ddy - vy * ddx);
              if (crossDerivative > 1e-9) minimumRadiusMm = Math.min(minimumRadiusMm, Math.pow(vx * vx + vy * vy, 1.5) / crossDerivative * pixelMm);
            }
            if (minimumRadiusMm < toolDiameter / 2) continue;
            tangentControl = control; selectedRadiusMm = minimumRadiusMm; start = s; end = e; a = p; b = q; chord = length; mouth = length * pixelMm;
            nx = -dy / length * orientation; ny = dx / length * orientation;
            oldArc = []; depth = 0;
            for (let j = start; j <= end; j++) { const point = at(j); oldArc.push(point); depth = Math.max(depth, ((point[0] - a[0]) * nx + (point[1] - a[1]) * ny) * pixelMm); }
            break outer;
          }
        }
        if (!tangentControl) {
          // Cubic fallback: independent shoulder tangents can bridge recesses
          // whose tangents do not meet at a suitable quadratic control point.
          let best=null;
          searchCubic: for(let total=0;total<=maxExtend*2;total++)for(let dl=Math.max(0,total-maxExtend);dl<=Math.min(total,maxExtend);dl++){
            const dr=total-dl,s=start-dl,e=end+dr,p=at(s),q=at(e),dx=q[0]-p[0],dy=q[1]-p[1],length=Math.hypot(dx,dy);
            if(length*pixelMm>bridgeWidth||length<0.1)continue;
            let u=[at(s+2)[0]-at(s-2)[0],at(s+2)[1]-at(s-2)[1]],v=[at(e+2)[0]-at(e-2)[0],at(e+2)[1]-at(e-2)[1]];
            const lu=Math.hypot(...u),lv=Math.hypot(...v);if(!lu||!lv)continue;u=u.map(x=>x/lu);v=v.map(x=>x/lv);
            if(u[0]*dx+u[1]*dy<0||v[0]*dx+v[1]*dy<0)continue;
            for(const factor of [0.25,0.35,0.45,0.55]){
              const c1=[p[0]+u[0]*length*factor,p[1]+u[1]*length*factor],c2=[q[0]-v[0]*length*factor,q[1]-v[1]*length*factor],replacement=[];let radius=Infinity,sag=0,valid=true;
              for(let k=0;k<=60;k++){const t=k/60,a=1-t,x=a*a*a*p[0]+3*a*a*t*c1[0]+3*a*t*t*c2[0]+t*t*t*q[0],y=a*a*a*p[1]+3*a*a*t*c1[1]+3*a*t*t*c2[1]+t*t*t*q[1];
                const vx=3*a*a*(c1[0]-p[0])+6*a*t*(c2[0]-c1[0])+3*t*t*(q[0]-c2[0]),vy=3*a*a*(c1[1]-p[1])+6*a*t*(c2[1]-c1[1])+3*t*t*(q[1]-c2[1]);
                const ax=6*a*(c2[0]-2*c1[0]+p[0])+6*t*(q[0]-2*c2[0]+c1[0]),ay=6*a*(c2[1]-2*c1[1]+p[1])+6*t*(q[1]-2*c2[1]+c1[1]);
                if(vx*dx+vy*dy<-1e-8){valid=false;break;}const cross=Math.abs(vx*ay-vy*ax);if(cross>1e-9)radius=Math.min(radius,Math.pow(vx*vx+vy*vy,1.5)/cross*pixelMm);
                sag=Math.max(sag,((x-p[0])*(-dy/length*orientation)+(y-p[1])*(dx/length*orientation))*pixelMm);replacement.push([x,y]);
              }
              if(!valid||radius<toolDiameter/2||sag>Math.max(maxNotchDepth,toolDiameter))continue;
              const old=[];for(let j=s;j<=e;j++)old.push(at(j));best={span:{loopIndex:loops.indexOf(loop),start:s,end:e,n},polygon:old.concat(replacement.slice().reverse()),replacement,mouthWidthMm:length*pixelMm,previousDepthMm:originalDepthMm,retainedDepthMm:sag,tangentContinuous:true,minimumBridgeRadiusMm:radius,noBacktracking:true};break searchCubic;
            }
          }
          if(best){found.push(best);for(let j=best.span.start;j<=best.span.end;j++)used[(j+n)%n]=1;continue;}
        }
        if (!tangentControl) {
          found.rejected.push({ reason: 'no-smooth-bridge', mouthWidthMm: mouth, depthMm: depth, polygon: oldArc.slice(), span: { loopIndex: loops.indexOf(loop), start, end, n } });
          continue;
        }
        const sag = Math.min(maxNotchDepth, mouth * 0.075) / pixelMm;
        let control = tangentControl || [(a[0] + b[0]) / 2 + nx * sag * 2, (a[1] + b[1]) / 2 + ny * sag * 2];
        const tangentA = [at(start + 2)[0] - at(start - 2)[0], at(start + 2)[1] - at(start - 2)[1]];
        const tangentB = [at(end + 2)[0] - at(end - 2)[0], at(end + 2)[1] - at(end - 2)[1]];
        const determinant = tangentA[0] * tangentB[1] - tangentA[1] * tangentB[0];
        if (Math.abs(determinant) > 1e-6) {
          const dx = b[0] - a[0], dy = b[1] - a[1];
          const ta = (dx * tangentB[1] - dy * tangentB[0]) / determinant;
          const tb = (dx * tangentA[1] - dy * tangentA[0]) / determinant;
          const intersection = [a[0] + tangentA[0] * ta, a[1] + tangentA[1] * ta];
          const perpendicular = ((intersection[0] - a[0]) * nx + (intersection[1] - a[1]) * ny) * pixelMm / 2;
          if (ta > 0 && tb < 0 && Math.hypot(intersection[0] - a[0], intersection[1] - a[1]) < chord * 3 && Math.hypot(intersection[0] - b[0], intersection[1] - b[1]) < chord * 3 && perpendicular >= 0 && perpendicular <= maxNotchDepth) control = intersection;
        }
        const replacement = [];
        for (let j = 0; j <= Math.max(16, Math.ceil(mouth / 0.35)); j++) {
          const steps = Math.max(16, Math.ceil(mouth / 0.35)), t = j / steps, u = 1 - t;
          replacement.push([u * u * a[0] + 2 * u * t * control[0] + t * t * b[0], u * u * a[1] + 2 * u * t * control[1] + t * t * b[1]]);
        }
        // Unioning this patch means the new cutter boundary can only add material.
        const retainedDepthMm = Math.max(0, ...replacement.map(p => ((p[0] - a[0]) * nx + (p[1] - a[1]) * ny) * pixelMm));
        found.push({ span: { loopIndex: loops.indexOf(loop), start, end, n }, polygon: oldArc.concat(replacement.slice().reverse()), replacement, mouthWidthMm: mouth, previousDepthMm: originalDepthMm, retainedDepthMm, tangentContinuous: !!tangentControl, minimumBridgeRadiusMm: selectedRadiusMm, noBacktracking: true });
        for (let j = start; j <= end; j++) used[(j + n) % n] = 1;
      }
    }
    return found;
  }

  // Detect at several physical scales so rasterization noise cannot turn a
  // single deep recess into an unrelated pair of tiny shoulders. Fine-scale
  // results keep priority; coarser passes only add disjoint recesses.
  function detectNotches(loops, pixelMm, bridgeWidth, maxNotchDepth, toolDiameter) {
    const result = [], rejected = [];
    function overlaps(a, b) {
      if (a.loopIndex !== b.loopIndex) return false;
      for (let shift = -1; shift <= 1; shift++) {
        const start = b.start + shift * b.n, end = b.end + shift * b.n;
        if (Math.min(a.end, end) - Math.max(a.start, start) > 1) return true;
      }
      return false;
    }
    for (const look of [4, 6, 8]) {
      const candidates = detectNotchesAtScale(loops, pixelMm, bridgeWidth, maxNotchDepth, toolDiameter, look);
      for (const candidate of candidates) {
        if (!result.some(region => overlaps(region.span, candidate.span))) result.push(candidate);
      }
      rejected.push(...candidates.rejected);
    }
    result.rejected = [];
    for (const candidate of rejected) {
      if (!result.some(region => overlaps(region.span, candidate.span)) &&
          !result.rejected.some(region => overlaps(region.span, candidate.span))) result.rejected.push(candidate);
    }
    return result;
  }

  function addPolygonToField(field, width, height, polygon) {
    const bounds = loopBounds([polygon]);
    const x0 = Math.max(0, Math.floor(bounds.minX)), x1 = Math.min(width - 1, Math.ceil(bounds.maxX));
    const y0 = Math.max(0, Math.floor(bounds.minY)), y1 = Math.min(height - 1, Math.ceil(bounds.maxY));
    for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
      let inside = false, minDistanceSquared = Infinity;
      for (let i = 0; i < polygon.length; i++) {
        const a = polygon[i], b = polygon[(i + 1) % polygon.length];
        if ((a[1] > y) !== (b[1] > y) && x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]) inside = !inside;
        const dx = b[0] - a[0], dy = b[1] - a[1], lengthSquared = dx * dx + dy * dy;
        const t = lengthSquared ? clamp(((x - a[0]) * dx + (y - a[1]) * dy) / lengthSquared, 0, 1) : 0;
        const ex = x - a[0] - t * dx, ey = y - a[1] - t * dy;
        minDistanceSquared = Math.min(minDistanceSquared, ex * ex + ey * ey);
      }
      const signed = Math.sqrt(minDistanceSquared) * (inside ? 1 : -1), i = y * width + x;
      field[i] = Math.max(field[i], signed);
    }
  }

  function cancelled(){if(typeof NativeCancelled==='function'&&NativeCancelled())throw new Error('CANCELLED');}
  const poly=(loops,op=0,delta=0)=>JSON.parse(NativePolygon(JSON.stringify(loops),op,delta));
  let traceKey='',traceCache=null;
  function trace(source,threshold){
    if(traceKey===String(threshold)&&traceCache)return traceCache;
    const w=source.width+2,h=source.height+2,mask=new Uint8Array(w*h);
    for(let y=0;y<source.height;y++){if(!(y%32))cancelled();for(let x=0;x<source.width;x++)mask[(y+1)*w+x+1]=source.alpha[y*source.width+x]>=threshold?1:0;}
    const b=boundsOfMask(mask,w,h);if(!b)throw new Error('当前阈值下没有图案，请降低透明度阈值。');
    const solid=fillHoles(mask,w,h),field=new Float32Array(w*h);for(let i=0;i<field.length;i++)field[i]=solid[i]?0.5:-0.5;
    cancelled();const loops=contours(field,w,h).map(p=>simplifyLoop(p,0.25));
    traceKey=String(threshold);traceCache={loops,b};return traceCache;
  }
  function build(source,options={}){
    const start=Date.now(),threshold=clamp(Math.round(finite(options.threshold,26)),1,254),tr=trace(source,threshold);
    const requestedHeight=finite(options.height,150),offset=finite(options.offset,3),curve=finite(options.curveSmooth,60),tol=0.012+curve/100*0.148;
    const sy=(requestedHeight-2*(offset+tol))/tr.b.height,sx=sy*source.height/source.width*(source.originalWidth/source.originalHeight);
    const raw=tr.loops.map(p=>p.map(([x,y])=>[(x-0.5)*sx,(y-0.5)*sy]));
    let silhouette=poly(raw),baseline=poly(silhouette,1,offset+tol);
    const radius=finite(options.cornerRadius,1);
    if(radius>0.01)baseline=poly(baseline,3,radius);
    cancelled();
    let candidates=options.cncBridge===false?[]:detectNotches(baseline,1,finite(options.bridgeWidth,16),finite(options.maxNotchDepth,1),finite(options.toolDiameter,3));
    const rejected=candidates.rejected||[];candidates.sort((a,b)=>loopBounds([a.polygon]).minY-loopBounds([b.polygon]).minY);
    const disabled=new Set(options.disabledBridges||[]),active=candidates.filter((_,i)=>!disabled.has(i));
    const body=poly(poly(baseline.concat(active.map(r=>r.polygon))),3,Math.max(.8,radius)),bb=loopBounds(body),originX=bb.minX,originY=bb.minY;
    const local=loops=>loops.map(p=>p.map(([x,y])=>[x-originX,y-originY]));
    let fitFallbacks=0;const fitted=loops=>{const f=CurveFit.path(local(loops),tol);fitFallbacks+=f.fallbacks;return f.path;};
    const tabWidth=finite(options.tabWidth,18),tabDepth=finite(options.tabDepth,3),tabCount=options.tabCount===2?2:1,tabs=[];
    const spacing=tabCount===2?Math.max(tabWidth+2,bb.width*.42):0,free=Math.max(0,(bb.width-tabWidth-spacing)/2-.5),shift=finite(options.tabPosition,0)/100*free;
    let warnings=[];
    for(let i=0;i<tabCount;i++){
      const cx=bb.width/2+shift+(tabCount===2?(i?1:-1)*spacing/2:0),left=cx-tabWidth/2,depths=[];
      const xs=Array.from({length:25},(_,j)=>originX+left+tabWidth*j/24);
      // Include vertices: uniform samples alone can miss a high point in the
      // bottom edge, leaving the top of the reference rectangle below it.
      for(const loop of body)for(const p of loop)if(p[0]>originX+left&&p[0]<originX+left+tabWidth)xs.push(p[0]);
      for(const x of xs){let ys=[];for(const loop of body)for(let k=0;k<loop.length;k++){let a=loop[k],b=loop[(k+1)%loop.length];if((a[0]<=x&&b[0]>x)||(b[0]<=x&&a[0]>x))ys.push(a[1]+(x-a[0])/(b[0]-a[0])*(b[1]-a[1])-originY);}if(ys.length)depths.push(Math.max(...ys));}
      depths.sort((a,b)=>a-b);if(!depths.length)throw new Error('插脚没有接触主体，请调整位置或宽度。');
      // Keep the existing position and attachment area as a factory reference.
      // Rectangles are never merged into the body cutline.
      const attach=depths[0],overlap=Math.max(0,finite(options.tabOverlap,3)),y=Math.max(0,attach-overlap),rect={x:left,y,width:tabWidth,height:bb.height+tabDepth-y,radius:0,centerX:cx,depth:tabDepth,bridgeHeight:bb.height-attach,overlap};tabs.push(rect);
      if(rect.bridgeHeight>Math.max(2,tabDepth))warnings.push(`插脚 ${i+1} 参考框向上延伸 ${fmt(rect.bridgeHeight)} mm，请由工厂调整。`);
    }
    cancelled();
    const bodyOnlyPath=fitted(body),path=bodyOnlyPath,baselinePath=fitted(baseline);
    const minX=Math.min(0,...tabs.map(t=>t.x)),maxX=Math.max(bb.width,...tabs.map(t=>t.x+t.width)),totalHeight=Math.max(bb.height,...tabs.map(t=>t.y+t.height));
    if(fitFallbacks)warnings.push('局部曲线拟合已回退为原轮廓以避免自交，请放大检查后调整平滑度。');
    if(body.length>1)warnings.push(`存在 ${body.length} 个独立刀线，请检查是否需要连接。`);
    const region=r=>{let b=loopBounds([r.polygon]);return {bounds:{x:b.minX-originX,y:b.minY-originY,width:b.width,height:b.height},mouthWidthMm:r.mouthWidthMm,previousDepthMm:r.previousDepthMm,retainedDepthMm:r.retainedDepthMm,minimumBridgeRadiusMm:r.minimumBridgeRadiusMm,tangentContinuous:true,noBacktracking:true,curveSamples:r.replacement.map(([x,y])=>[x-originX,y-originY])};};
    const imageBox={x:-originX,y:-originY,width:source.width*sx,height:source.height*sy};
    return {bodyPath:path,bodyOnlyPath,baselinePath,bridgePath:active.length?pathsFromLoops(local(active.map(r=>r.polygon)),1,0,0,.01):'',whitePath:'',silhouettePath:fitted(silhouette),imageBox,bounds:{x:minX,y:0,width:maxX-minX,height:totalHeight},tabs,tabReferenceOnly:true,widthMm:bb.width,heightMm:bb.height,totalHeightMm:totalHeight,totalWidthMm:maxX-minX,bridgeRegions:candidates.map((r,i)=>({...region(r),enabled:!disabled.has(i),index:i})),bridgeDiagnostics:{detected:candidates.length+rejected.length,bridged:active.length,unhandled:rejected.map(r=>({reason:r.reason,bounds:(()=>{let b=loopBounds([r.polygon]);return {x:b.minX-originX,y:b.minY-originY,width:b.width,height:b.height}})()}))},warnings,geometryResolutionMm:sy,cutComponents:body.length,whiteContours:0,fitToleranceMm:tol,offsetMm:offset,engineMs:Date.now()-start,curveNodes:(path.match(/C /g)||[]).length,options};
  }

  const API = { fromImage, fromAlpha, build, version: '0.3.0', testUtils: { fillHoles, boundsOfMask, componentInfo, distanceSquared, signedField, contours, loopBounds, detectNotches } };
  root.AcrylicGeometry = API;
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
})(typeof window !== 'undefined' ? window : globalThis);
