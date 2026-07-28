class_name PlaythroughAnimationHtmlRenderer
extends RefCounted

static func build_html(playtest_report: Dictionary) -> String:
	var animation: Dictionary = playtest_report.get("animation", {})
	var title := str(animation.get("title", playtest_report.get("spec_id", "Playthrough Animation")))
	var payload := {
		"contract_id": "playthrough_animation_html_payload_v1",
		"animation": animation,
		"success": bool(playtest_report.get("success", false)),
		"errors": playtest_report.get("errors", []),
	}
	var payload_json := JSON.stringify(payload, "\t").replace("</", "<\\/")
	var html := """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>__TITLE__</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #0d1012;
      --panel: #15191d;
      --panel-2: #101316;
      --line: #303840;
      --text: #e9edf0;
      --muted: #98a2aa;
      --safe: #6fc48a;
      --risk: #dd7a5d;
      --shortcut: #7eb9e9;
      --gold: #e5bc62;
      --aster: #549cff;
      --peris: #ffb159;
      --endo: #72c48e;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: Inter, Segoe UI, Arial, sans-serif;
      background: var(--bg);
      color: var(--text);
    }
    header {
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
      gap: 16px;
      padding: 20px 24px 12px;
      border-bottom: 1px solid var(--line);
      background: #101417;
    }
    h1 { margin: 0 0 6px; font-size: 22px; letter-spacing: 0; }
    .subtitle { color: var(--muted); font-size: 13px; line-height: 1.45; }
    .tags { display: flex; flex-wrap: wrap; gap: 8px; justify-content: flex-end; }
    .tag {
      border: 1px solid #38414a;
      background: #1b2127;
      border-radius: 4px;
      padding: 5px 8px;
      color: #cbd3d8;
      font-size: 12px;
      white-space: nowrap;
    }
    main {
      display: grid;
      grid-template-columns: minmax(680px, 1fr) 360px;
      gap: 16px;
      padding: 16px 24px 24px;
    }
    .stage-card, .side-card {
      min-width: 0;
      border: 1px solid var(--line);
      background: var(--panel);
      border-radius: 6px;
      overflow: hidden;
    }
    .toolbar {
      display: flex;
      align-items: center;
      gap: 10px;
      padding: 12px;
      border-bottom: 1px solid var(--line);
      background: var(--panel-2);
    }
    button {
      border: 1px solid #3b4650;
      background: #20272e;
      color: var(--text);
      border-radius: 4px;
      padding: 7px 10px;
      font: inherit;
      cursor: pointer;
    }
    button:hover { background: #28313a; }
    input[type="range"] { flex: 1; min-width: 160px; }
    .readout {
      min-width: 116px;
      color: var(--muted);
      font-size: 12px;
      text-align: right;
    }
    .stage-wrap {
      position: relative;
      background: #0c0f11;
      min-height: 620px;
    }
    .pressure-flash {
      position: absolute;
      inset: 18px;
      display: grid;
      place-items: center;
      border: 4px solid #ff6b4b;
      background: rgba(120, 18, 8, 0.42);
      color: #fff3eb;
      font-size: 30px;
      font-weight: 850;
      letter-spacing: 0.04em;
      text-shadow: 0 2px 12px #000;
      pointer-events: none;
      opacity: 0;
      transition: opacity 100ms linear;
    }
    .pressure-flash.visible { opacity: 1; }
    svg { display: block; width: 100%; height: 620px; }
    .foundation { fill: #0f1417; stroke: #263039; stroke-width: 1; }
    .route { fill: none; stroke-width: 8; stroke-linecap: round; opacity: 0.72; }
    .route.safe { stroke: var(--safe); }
    .route.risky { stroke: var(--risk); stroke-dasharray: 12 8; }
    .route.shortcut { stroke: var(--shortcut); stroke-dasharray: 4 7; }
    .route.active { stroke-width: 12; opacity: 1; filter: drop-shadow(0 0 5px currentColor); }
    .node-pad { stroke: #44505a; stroke-width: 1.5; opacity: 0.86; }
    .node.boundary { fill: #263632; }
    .node.foraging, .node.resource { fill: #24472d; }
    .node.guidance { fill: #23384b; }
    .node.route_pressure, .node.pressure, .node.danger { fill: #4c2822; }
    .node.shortcut { fill: #26404f; }
    .node.shelter { fill: #4a3d22; }
    .node.active .node-pad { stroke: var(--gold); stroke-width: 3; opacity: 1; }
    .node-label { fill: #ecf2f5; font-size: 11px; text-anchor: middle; pointer-events: none; }
    .node-role { fill: #a9b3ba; font-size: 9px; text-anchor: middle; pointer-events: none; }
    .content.flora { fill: #4fb46c; stroke: #b5e4bf; }
    .content.enemies { fill: #c95f53; stroke: #f2b4a7; }
    .content.structures { fill: #8f9ba5; stroke: #d0d7dc; }
    .content.unsupported { fill: #626a70; stroke: #a4abb0; }
    .content-label { fill: #d5dcdf; font-size: 8px; text-anchor: middle; pointer-events: none; }
    .path-line { fill: none; stroke-width: 2; stroke-dasharray: 4 5; opacity: 0.75; }
    .path-line.aster { stroke: var(--aster); }
    .path-line.peris { stroke: var(--peris); }
    .path-line.endo { stroke: var(--endo); }
    .token circle.core { stroke: #edf4f7; stroke-width: 2; }
    .token.aster circle.core { fill: var(--aster); }
    .token.peris circle.core { fill: var(--peris); }
    .token.endo circle.core { fill: var(--endo); }
    .token text { fill: #081014; font-weight: 800; font-size: 10px; text-anchor: middle; dominant-baseline: central; }
    .token.walk circle.core { transform-origin: center; animation: walkbob 0.46s infinite alternate ease-in-out; }
    .token.run circle.core { transform-origin: center; animation: runpulse 0.26s infinite alternate ease-in-out; }
    .token.consume circle.core { animation: consume 0.7s infinite alternate ease-in-out; stroke: #f4d36a; }
    .token.excluded { opacity: 0.12; filter: grayscale(1); }
    .aura { fill: none; stroke: #f4d36a; stroke-width: 3; opacity: 0; }
    .token.consume .aura { opacity: 0.9; animation: aura 0.9s infinite ease-out; }
    @keyframes walkbob { from { transform: translateY(0); } to { transform: translateY(-2px); } }
    @keyframes runpulse { from { transform: scale(1); } to { transform: scale(1.18); } }
    @keyframes consume { from { filter: brightness(1); } to { filter: brightness(1.45); } }
    @keyframes aura { from { r: 13; opacity: 0.85; } to { r: 24; opacity: 0.08; } }
    .side-card { max-height: calc(100vh - 120px); display: flex; flex-direction: column; }
    .side-section { padding: 12px; border-bottom: 1px solid var(--line); }
    .side-title { margin: 0 0 8px; font-size: 13px; color: #dbe4e8; }
    .snapshot-title { font-size: 16px; font-weight: 760; margin-bottom: 4px; }
    .snapshot-meta { color: var(--muted); font-size: 12px; line-height: 1.45; }
    .party { display: grid; gap: 8px; }
    .member {
      border: 1px solid #313b44;
      background: #11161a;
      border-radius: 5px;
      padding: 8px;
    }
    .member.excluded { opacity: 0.28; border-style: dashed; filter: grayscale(0.9); }
    .member.excluded .locomotion { color: #9ba4aa; }
    .member-head { display: flex; justify-content: space-between; gap: 8px; font-size: 12px; margin-bottom: 6px; }
    .locomotion { color: var(--muted); text-transform: uppercase; font-size: 10px; letter-spacing: 0.04em; }
    .bars { display: grid; gap: 4px; }
    .bar { height: 6px; background: #242c33; border-radius: 2px; overflow: hidden; }
    .bar span { display: block; height: 100%; background: #7ccf91; }
    .bar.sta span { background: #e2b95f; }
    .bar.atp span { background: #75afe5; }
    .hands { color: #c9d1d6; font-size: 11px; margin-top: 7px; display: grid; grid-template-columns: 1fr 1fr; gap: 5px; }
    .hand {
      border: 1px solid #36414a;
      background: #20262c;
      border-radius: 3px;
      padding: 4px 5px;
      min-width: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .timeline { overflow: auto; padding: 10px 12px; display: grid; gap: 6px; }
    .tick {
      border: 1px solid #2c353d;
      background: #101418;
      border-radius: 4px;
      padding: 7px 8px;
      color: #cbd4d9;
      font-size: 11px;
      cursor: pointer;
    }
    .tick.active { border-color: var(--gold); background: #211f18; color: #f4e2ad; }
    @media (max-width: 980px) {
      main { grid-template-columns: 1fr; padding: 12px; }
      header { flex-direction: column; }
      .tags { justify-content: flex-start; }
      .stage-wrap, svg { min-height: 520px; height: 520px; }
      .side-card { max-height: none; }
    }
  </style>
</head>
<body>
  <header>
    <div>
      <h1>__TITLE__</h1>
      <div class="subtitle">Captured from the reusable headless playtest contract. Tokens, routes, elevations, content markers, hands, abilities, and endocytosis state come from preview snapshots.</div>
    </div>
    <div class="tags" id="tags"></div>
  </header>
  <main>
    <section class="stage-card">
      <div class="toolbar">
        <button id="play">Pause</button>
        <button id="restart">Restart</button>
        <input id="scrub" type="range" min="0" value="0" step="1">
        <button id="slower">-</button>
        <button id="faster">+</button>
        <div class="readout" id="readout">snapshot 0 / 0</div>
      </div>
      <div class="stage-wrap">
        <svg id="stage" viewBox="0 0 1000 620" role="img" aria-label="playthrough animation">
          <rect class="foundation" x="18" y="18" width="964" height="584" rx="4"></rect>
          <g id="routes"></g>
          <g id="nodes"></g>
          <g id="content"></g>
          <g id="paths"></g>
          <g id="tokens"></g>
        </svg>
        <div class="pressure-flash" id="pressure-flash">NEAR MISS</div>
      </div>
    </section>
    <aside class="side-card">
      <section class="side-section">
        <h2 class="side-title">Current Beat</h2>
        <div class="snapshot-title" id="snapshot-title">No snapshots</div>
        <div class="snapshot-meta" id="snapshot-meta"></div>
      </section>
      <section class="side-section">
        <h2 class="side-title">Party State</h2>
        <div class="party" id="party"></div>
      </section>
      <section class="side-section">
        <h2 class="side-title">Chunk State</h2>
        <div class="snapshot-meta" id="chunk-state"></div>
      </section>
      <div class="timeline" id="timeline"></div>
    </aside>
  </main>
  <script id="report-data" type="application/json">__DATA__</script>
  <script>
    const payload = JSON.parse(document.getElementById("report-data").textContent);
    const animation = payload.animation || {};
    const layout = animation.layout || {};
    const snapshots = animation.snapshots || [];
    const nodes = layout.nodes || [];
    const routes = layout.routes || [];
    const nodeById = new Map(nodes.map((node) => [node.id, node]));
    const partyIds = animation.party || ["aster", "peris", "endo"];
    const colors = { aster: "#549cff", peris: "#ffb159", endo: "#72c48e" };
    const initials = { aster: "A", peris: "P", endo: "E" };
    const stage = document.getElementById("stage");
    const routesLayer = document.getElementById("routes");
    const nodesLayer = document.getElementById("nodes");
    const contentLayer = document.getElementById("content");
    const pathsLayer = document.getElementById("paths");
    const tokensLayer = document.getElementById("tokens");
    const playButton = document.getElementById("play");
    const restartButton = document.getElementById("restart");
    const scrub = document.getElementById("scrub");
    const readout = document.getElementById("readout");
    const slower = document.getElementById("slower");
    const faster = document.getElementById("faster");
    const partyPanel = document.getElementById("party");
    const timeline = document.getElementById("timeline");
    const titleEl = document.getElementById("snapshot-title");
    const metaEl = document.getElementById("snapshot-meta");
    const chunkEl = document.getElementById("chunk-state");
    const tagsEl = document.getElementById("tags");
    const pressureFlash = document.getElementById("pressure-flash");
    let index = 0;
    let progress = 0;
    let playing = snapshots.length > 1;
    let lastFrame = performance.now();
    let playbackRate = 1;

    // Scheduler time resets between golden, risky, and shadow runs. Convert those
    // segments into one monotonic reel while preserving real in-game duration;
    // duplicate event snapshots advance nearly instantly instead of adding pauses.
    const playTimes = [];
    let segmentOffset = 0;
    let previousRawTime = snapshots.length ? Number(snapshots[0].time || 0) : 0;
    let previousPlayTime = previousRawTime;
    for (let i = 0; i < snapshots.length; i += 1) {
      const rawTime = Number(snapshots[i].time || 0);
      if (i > 0 && rawTime + 0.001 < previousRawTime) {
        segmentOffset = previousPlayTime + 0.8 - rawTime;
      }
      const candidate = rawTime + segmentOffset;
      const playTime = i === 0 ? candidate : Math.max(previousPlayTime + 0.001, candidate);
      playTimes.push(playTime);
      previousRawTime = rawTime;
      previousPlayTime = playTime;
    }
    let playheadTime = playTimes[0] || 0;

    scrub.max = Math.max(0, snapshots.length - 1);

    function vec3(value, fallback = [0, 0, 0]) {
      return Array.isArray(value) && value.length >= 3 ? value : fallback;
    }

    function escapeText(value) {
      return String(value ?? "").replace(/[&<>"']/g, (char) => ({
        "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
      }[char]));
    }

    function bounds() {
      let pointCount = 0;
      let minX = Infinity;
      let maxX = -Infinity;
      let minY = Infinity;
      let maxY = -Infinity;
      let minZ = Infinity;
      let maxZ = -Infinity;
      function includePoint(value) {
        const point = vec3(value);
        minX = Math.min(minX, point[0]);
        maxX = Math.max(maxX, point[0]);
        minY = Math.min(minY, point[1]);
        maxY = Math.max(maxY, point[1]);
        minZ = Math.min(minZ, point[2]);
        maxZ = Math.max(maxZ, point[2]);
        pointCount += 1;
      }
      for (const node of nodes) includePoint(node.position);
      for (const snapshot of snapshots) {
        for (const charId of partyIds) {
          const char = snapshot.characters?.[charId];
          if (char) includePoint(char.position);
          const path = char?.movement?.path || [];
          for (const p of path) includePoint(p);
        }
      }
      if (!pointCount) {
        includePoint([0, 0, 0]);
        includePoint([24, 0, 12]);
      }
      return {
        minX: minX - 4,
        maxX: maxX + 4,
        minY: minY,
        maxY: maxY,
        minZ: minZ - 4,
        maxZ: maxZ + 4
      };
    }

    const b = bounds();
    const scale = Math.min(900 / Math.max(1, b.maxX - b.minX), 500 / Math.max(1, b.maxZ - b.minZ));
    function project(pos) {
      const p = vec3(pos);
      return {
        x: 50 + (p[0] - b.minX) * scale,
        y: 560 - (p[2] - b.minZ) * scale - (p[1] - b.minY) * 34,
        elevation: p[1]
      };
    }

    function svgEl(name, attrs = {}) {
      const el = document.createElementNS("http://www.w3.org/2000/svg", name);
      for (const [key, value] of Object.entries(attrs)) el.setAttribute(key, value);
      return el;
    }

    function routeKind(route) {
      return route.kind || route.risk || "safe";
    }

    function drawRoutes() {
      for (const route of routes) {
        const from = nodeById.get(route.from);
        const to = nodeById.get(route.to);
        if (!from || !to) continue;
        const a = project(from.position);
        const z = project(to.position);
        const path = svgEl("path", {
          id: `route-${route.id}`,
          class: `route ${routeKind(route)}`,
          d: `M ${a.x.toFixed(2)} ${a.y.toFixed(2)} L ${z.x.toFixed(2)} ${z.y.toFixed(2)}`
        });
        routesLayer.appendChild(path);
      }
    }

    function drawNodes() {
      for (const node of nodes) {
        const p = project(node.position);
        const size = vec3(node.footprint || node.floor_size, [3.2, 0.2, 2.4]);
        const w = Math.max(34, size[0] * scale);
        const h = Math.max(24, size[2] * scale);
        const g = svgEl("g", { id: `node-${node.id}`, class: `node ${node.role || "route"}` });
        g.appendChild(svgEl("rect", {
          class: "node-pad",
          x: (p.x - w / 2).toFixed(2),
          y: (p.y - h / 2).toFixed(2),
          width: w.toFixed(2),
          height: h.toFixed(2),
          rx: 4
        }));
        g.appendChild(svgEl("circle", { cx: p.x, cy: p.y, r: 6, fill: "#f1f5f8" }));
        const label = svgEl("text", { class: "node-label", x: p.x, y: p.y - h / 2 - 11 });
        label.textContent = node.id === "exit_shelter" ? "exit shelter" : (node.title || node.id);
        g.appendChild(label);
        const role = svgEl("text", { class: "node-role", x: p.x, y: p.y + h / 2 + 13 });
        role.textContent = `${node.action_verb || node.role || "route"}  ·  ${node.role || "route"}`;
        g.appendChild(role);
        nodesLayer.appendChild(g);
        drawContent(node, p);
      }
    }

    function drawContent(node, nodePoint) {
      const placements = node.content_placements || [];
      for (const placement of placements) {
        const pos = placement.position || [
          vec3(node.position)[0] + vec3(placement.local_offset)[0],
          vec3(node.position)[1] + vec3(placement.local_offset)[1],
          vec3(node.position)[2] + vec3(placement.local_offset)[2]
        ];
        const p = project(pos);
        const size = vec3(placement.size, [0.8, 0.8, 0.8]);
        const category = placement.category || "structures";
        const unsupported = placement.support && placement.support !== "implemented" ? " unsupported" : "";
        let marker;
        if (category === "flora") {
          marker = svgEl("circle", { class: `content flora${unsupported}`, cx: p.x, cy: p.y, r: Math.max(4, size[0] * scale * 0.18) });
        } else if (category === "enemies") {
          marker = svgEl("rect", {
            class: `content enemies${unsupported}`,
            x: p.x - 6, y: p.y - 6, width: 12, height: 12,
            transform: `rotate(45 ${p.x} ${p.y})`
          });
        } else {
          marker = svgEl("rect", { class: `content structures${unsupported}`, x: p.x - 7, y: p.y - 5, width: 14, height: 10, rx: 2 });
        }
        contentLayer.appendChild(marker);
        const label = svgEl("text", { class: "content-label", x: p.x, y: p.y - 9 });
        label.textContent = placement.id || category;
        contentLayer.appendChild(label);
      }
    }

    function buildTokens() {
      for (const charId of partyIds) {
        const g = svgEl("g", { id: `token-${charId}`, class: `token ${charId}` });
        g.appendChild(svgEl("circle", { class: "aura", cx: 0, cy: 0, r: 18 }));
        g.appendChild(svgEl("circle", { class: "core", cx: 0, cy: 0, r: 12 }));
        const label = svgEl("text", { x: 0, y: 1 });
        label.textContent = initials[charId] || charId.slice(0, 1).toUpperCase();
        g.appendChild(label);
        tokensLayer.appendChild(g);
      }
    }

    function lerp(a, b, t) { return a + (b - a) * t; }
    function characterPoint(snapshot, nextSnapshot, charId) {
      const a = vec3(snapshot?.characters?.[charId]?.position);
      const bpos = vec3(nextSnapshot?.characters?.[charId]?.position, a);
      return project([lerp(a[0], bpos[0], progress), lerp(a[1], bpos[1], progress), lerp(a[2], bpos[2], progress)]);
    }

    function drawPaths(snapshot) {
      pathsLayer.replaceChildren();
      const activeParty = new Set(snapshot.chunk?.active_party || partyIds);
      for (const charId of partyIds) {
        if (!activeParty.has(charId)) continue;
        const path = snapshot.characters?.[charId]?.movement?.path || [];
        if (path.length < 2) continue;
        const d = path.map((p, i) => {
          const point = project(p);
          return `${i === 0 ? "M" : "L"} ${point.x.toFixed(2)} ${point.y.toFixed(2)}`;
        }).join(" ");
        pathsLayer.appendChild(svgEl("path", { class: `path-line ${charId}`, d }));
      }
    }

    function statWidth(value, max) {
      const v = Number(value ?? 0);
      return `${Math.max(0, Math.min(100, (v / max) * 100)).toFixed(0)}%`;
    }

    function renderParty(snapshot) {
      partyPanel.innerHTML = "";
      const activeParty = new Set(snapshot.chunk?.active_party || partyIds);
      for (const charId of partyIds) {
        const char = snapshot.characters?.[charId] || {};
        const stats = char.stats || {};
        const slots = char.hand_labels || char.hand_slots || [];
        const member = document.createElement("div");
        const isActive = activeParty.has(charId);
        member.className = `member${isActive ? "" : " excluded"}`;
        member.innerHTML = `
          <div class="member-head"><strong>${escapeText(charId.toUpperCase())}</strong><span class="locomotion">${escapeText(isActive ? (char.locomotion || "idle") : "not in shadow party")}</span></div>
          <div class="bars">
            <div class="bar hp"><span style="width:${statWidth(stats.hp, 100)}"></span></div>
            <div class="bar sta"><span style="width:${statWidth(stats.sta, 100)}"></span></div>
            <div class="bar atp"><span style="width:${statWidth(stats.atp, 8)}"></span></div>
          </div>
          <div class="hands">
            <div class="hand">L ${escapeText(slots[0] || "-")}</div>
            <div class="hand">R ${escapeText(slots[1] || "-")}</div>
          </div>
        `;
        partyPanel.appendChild(member);
      }
    }

    function activeRouteId(snapshot) {
      const data = snapshot.data || {};
      if (data.route_id) return data.route_id;
      if (data.route?.id) return data.route.id;
      const chunkRoute = snapshot.chunk?.route_choice;
      return chunkRoute || "";
    }

    function activeNodeId(snapshot) {
      const data = snapshot.data || {};
      if (data.node_id) return data.node_id;
      if (data.node?.node_id) return data.node.node_id;
      return "";
    }

    function render(snapshot, nextSnapshot = snapshot) {
      if (!snapshot) return;
      for (const el of document.querySelectorAll(".active")) el.classList.remove("active");
      const routeId = activeRouteId(snapshot);
      const nodeId = activeNodeId(snapshot);
      if (routeId) document.getElementById(`route-${routeId}`)?.classList.add("active");
      if (nodeId) document.getElementById(`node-${nodeId}`)?.classList.add("active");
      document.getElementById(`tick-${snapshot.index}`)?.classList.add("active");

      for (const charId of partyIds) {
        const token = document.getElementById(`token-${charId}`);
        const char = snapshot.characters?.[charId] || {};
        const activeParty = new Set(snapshot.chunk?.active_party || partyIds);
        const isActive = activeParty.has(charId);
        const p = characterPoint(snapshot, nextSnapshot, charId);
        token.setAttribute("transform", `translate(${p.x.toFixed(2)} ${p.y.toFixed(2)})`);
        token.setAttribute("class", `token ${charId} ${isActive ? (char.locomotion || "idle") : "excluded"}`);
      }
      drawPaths(snapshot);
      renderParty(snapshot);
      titleEl.textContent = snapshot.label || "Snapshot";
      metaEl.textContent = `${snapshot.phase || "phase"} / t=${Number(snapshot.time || 0).toFixed(2)} / ${snapshot.data?.event_type || "state"}`;
      const eventType = snapshot.data?.event_type || "";
      const pressureVisible = eventType === "route_pressure_impact" || eventType === "route_pressure_recovery";
      pressureFlash.classList.toggle("visible", pressureVisible);
      pressureFlash.textContent = pressureVisible
        ? `NEAR MISS // -${Number(snapshot.data?.damage || 0).toFixed(0)} HP EACH`
        : "NEAR MISS";
      const chunk = snapshot.chunk || {};
      const chainStates = Object.keys(chunk.produced_chain_states || {}).length;
      const delivered = (chunk.delivered_resource_nodes || []).length;
      chunkEl.textContent = `phase=${chunk.route_phase || "-"}  party=${(chunk.active_party || partyIds).join("+")}  resources=${chunk.resources_collected ?? 0}  chain_states=${chainStates}  delivered=${delivered}  shelter=${chunk.shelter_rested ? "rested" : "not yet"}  damage=${Number(chunk.risky_damage_total || 0).toFixed(1)}`;
      scrub.value = String(index);
      readout.textContent = `t ${Number(snapshot.time || 0).toFixed(1)}s · ${playbackRate.toFixed(2)}x`;
    }

    function buildTimeline() {
      timeline.replaceChildren();
      for (const snapshot of snapshots) {
        const item = document.createElement("button");
        item.className = "tick";
        item.id = `tick-${snapshot.index}`;
        item.textContent = `${snapshot.index}. ${snapshot.phase} - ${snapshot.label}`;
        item.addEventListener("click", () => {
          index = snapshot.index - 1;
          playheadTime = playTimes[index] || 0;
          progress = 0;
          playing = false;
          playButton.textContent = "Play";
          render(snapshots[index], snapshots[index + 1] || snapshots[index]);
        });
        timeline.appendChild(item);
      }
    }

    function buildTags() {
      const summary = animation.summary || {};
      const world = animation.world_slot || {};
      const tags = [
        animation.spec_id || "generated stretch",
        animation.preview_party_preset || "preview",
        `${snapshots.length} snapshots`,
        summary.has_run_state ? "run captured" : "walk only",
        summary.has_endocytosis ? "endocytosis captured" : "no endocytosis",
        world.entry_shelter_id && world.exit_shelter_id ? `${world.entry_shelter_id} to ${world.exit_shelter_id}` : ""
      ].filter(Boolean);
      tagsEl.innerHTML = tags.map((tag) => `<span class="tag">${escapeText(tag)}</span>`).join("");
    }

    function tick(now) {
      const delta = now - lastFrame;
      lastFrame = now;
      if (playing && snapshots.length > 1) {
        playheadTime += (delta / 1000) * playbackRate;
        while (index < snapshots.length - 1 && (playTimes[index + 1] || 0) <= playheadTime) {
          index += 1;
        }
        if (index >= snapshots.length - 1) {
          index = snapshots.length - 1;
          progress = 0;
          playing = false;
          playButton.textContent = "Play";
        } else {
          const start = playTimes[index] || 0;
          const finish = playTimes[index + 1] || start;
          progress = Math.max(0, Math.min(1, (playheadTime - start) / Math.max(0.001, finish - start)));
        }
      }
      render(snapshots[index], snapshots[index + 1] || snapshots[index]);
      requestAnimationFrame(tick);
    }

    playButton.addEventListener("click", () => {
      playing = !playing;
      playButton.textContent = playing ? "Pause" : "Play";
    });
    restartButton.addEventListener("click", () => {
      index = 0;
      progress = 0;
      playheadTime = playTimes[0] || 0;
      playing = snapshots.length > 1;
      playButton.textContent = playing ? "Pause" : "Play";
    });
    scrub.addEventListener("input", () => {
      index = Number(scrub.value);
      progress = 0;
      playheadTime = playTimes[index] || 0;
      playing = false;
      playButton.textContent = "Play";
      render(snapshots[index], snapshots[index + 1] || snapshots[index]);
    });
    slower.addEventListener("click", () => { playbackRate = Math.max(0.25, playbackRate / 1.25); });
    faster.addEventListener("click", () => { playbackRate = Math.min(4, playbackRate * 1.25); });

    buildTags();
    drawRoutes();
    drawNodes();
    buildTokens();
    buildTimeline();
    render(snapshots[0] || null, snapshots[1] || snapshots[0] || null);
    requestAnimationFrame(tick);
  </script>
</body>
</html>
"""
	return html.replace("__TITLE__", _html_escape(title)).replace("__DATA__", payload_json)

static func _html_escape(value: String) -> String:
	return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
