// Cursor Dream Skin injector — 僅對 Cursor Agents 視窗注入皮膚。
// 用法：
//   injector.mjs --once   --port N --theme-dir DIR [--timeout-ms T]
//   injector.mjs --verify --port N --theme-dir DIR [--timeout-ms T]
//   injector.mjs --watch  --port N --theme-dir DIR
// exit 0 = 成功/驗證通過；非 0 = 失敗（fail-closed）。
import fs from "node:fs";
import path from "node:path";

const MARKER_ID = "cursor-dream-skin-style";
const WALLPAPER_ID = "cursor-dream-skin-wallpaper";
const STATE_KEY = "__CURSOR_DREAM_SKIN_STATE__";

function arg(name, fallback = undefined) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}
const MODE = process.argv.includes("--verify")
  ? "verify"
  : process.argv.includes("--watch")
    ? "watch"
    : "once";
const PORT = Number(arg("port", "9341"));
const THEME_DIR = path.resolve(arg("theme-dir") || process.exit(2));
const TIMEOUT_MS = Number(arg("timeout-ms", "10000"));

function readTheme() {
  const theme = JSON.parse(fs.readFileSync(path.join(THEME_DIR, "theme.json"), "utf8"));
  const css = fs.readFileSync(path.join(THEME_DIR, "dream-skin.css"), "utf8");
  const artPath = path.join(THEME_DIR, theme.background || "background.png");
  const ext = path.extname(artPath).toLowerCase();
  const mime = ext === ".webp" ? "image/webp" : ext === ".jpg" || ext === ".jpeg" ? "image/jpeg" : "image/png";
  const b64 = fs.readFileSync(artPath).toString("base64");
  return { theme, css, artDataUrl: `data:${mime};base64,${b64}` };
}

async function listPageTargets() {
  const res = await fetch(`http://127.0.0.1:${PORT}/json/list`, { signal: AbortSignal.timeout(2000) });
  const list = await res.json();
  return list.filter((t) => t.type === "page" && /workbench\.html/.test(t.url) && t.webSocketDebuggerUrl);
}

function isAgentsTarget(t) {
  return /^Cursor Agents$/i.test(t.title || "");
}

async function findAgentsTargets() {
  return (await listPageTargets()).filter(isAgentsTarget);
}

async function waitForAgentsTargets(deadlineMs) {
  const deadline = Date.now() + deadlineMs;
  while (Date.now() < deadline) {
    const targets = await findAgentsTargets();
    if (targets.length) return targets;
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error("找不到 Cursor Agents 視窗（請先打開 Agents 視窗後重試）");
}

async function findTarget() {
  const targets = await findAgentsTargets();
  return targets[0] || null;
}

async function withAgentsTargets(fn) {
  const targets = await waitForAgentsTargets(Math.max(TIMEOUT_MS, 60000));
  const results = [];
  for (const target of targets) {
    const ws = await connect(target.webSocketDebuggerUrl);
    try {
      const rpc = makeRpc(ws);
      await rpc("Runtime.enable");
      results.push({ target, result: await fn(rpc, target) });
    } finally {
      try { ws.close(); } catch {}
    }
  }
  return results;
}

function connect(url) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    ws.onopen = () => resolve(ws);
    ws.onerror = (e) => reject(new Error(`websocket error: ${e.message || "unknown"}`));
    setTimeout(() => { try { ws.close(); } catch {} reject(new Error("websocket open timeout")); }, 5000);
  });
}

function makeRpc(ws) {
  let id = 0;
  const pending = new Map();
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    const p = pending.get(msg.id);
    if (p) { pending.delete(msg.id); p(msg); }
  };
  return async (method, params = {}) => {
    const mid = ++id;
    const msg = await new Promise((res) => { pending.set(mid, res); ws.send(JSON.stringify({ id: mid, method, params })); });
    if (msg.error) throw new Error(`${method}: ${msg.error.message}`);
    return msg.result;
  };
}

function buildPayload({ theme, css, artDataUrl }) {
  const vars = [
    `--ds-workbench-opacity:${theme.opacity?.workbench ?? 0.58}`,
    `--ds-sidebar-opacity:${theme.opacity?.sidebar ?? 0.72}`,
    `--ds-panel-opacity:${theme.opacity?.panel ?? 0.7}`,
    `--ds-editor-opacity:${theme.opacity?.editor ?? 0.62}`,
    `--ds-art-position:${theme.safeArea?.position ?? "center"}`,
    `--ds-task-raise:${theme.taskMode?.raiseOpacity ?? 0.12}`,
  ].join(";");
  const themeConfig = JSON.stringify({
    id: theme.id || "custom",
    appearance: theme.appearance || "auto",
    opacity: theme.opacity || {},
    tint: theme.tint || {},
  });
  return { css, vars, themeConfig, artDataUrl };
}

// 在 renderer 內建立/替換皮膚。
function injectExpression({ css, vars, themeConfig, artDataUrl }, expectedRevision) {
  const parts = [
    "(() => {",
    `const cfg = ${themeConfig};`,
    `const cssText = ${JSON.stringify(css)};`,
    `const rootStyle = ${JSON.stringify(vars)};`,
    `const artUrl = ${JSON.stringify(artDataUrl)};`,
    `const revision = ${JSON.stringify(String(expectedRevision))};`,
    `const old = window[${JSON.stringify(STATE_KEY)}];`,
    `const existingStyle = document.getElementById(${JSON.stringify(MARKER_ID)});`,
    `const existingWallpaper = document.getElementById(${JSON.stringify(WALLPAPER_ID)});`,
    "if (old && old.revision === revision && existingStyle && existingStyle.isConnected && existingWallpaper && existingWallpaper.isConnected) {",
    "return JSON.stringify({ ok: true, alreadyApplied: true, revision }); }",
    "if (old && typeof old.cleanup === 'function') old.cleanup();",
    "try { existingStyle?.remove(); } catch (e) {}",
    "try { existingWallpaper?.remove(); } catch (e) {}",
    "const html = document.documentElement;",
    "const body = document.body;",
    `let wallpaper = document.getElementById(${JSON.stringify(WALLPAPER_ID)});`,
    "if (!wallpaper) {",
    `wallpaper = document.createElement('div'); wallpaper.id = ${JSON.stringify(WALLPAPER_ID)};`,
    "body.insertBefore(wallpaper, body.firstChild); }",
    "wallpaper.style.backgroundImage = 'url(\"' + artUrl + '\")';",
    `const styleEl = document.createElement('style'); styleEl.id = ${JSON.stringify(MARKER_ID)};`,
    "styleEl.textContent = cssText;",
    "document.head.appendChild(styleEl);",
    "html.setAttribute('data-dream-skin', 'active');",
    "html.setAttribute('data-dream-art-ready', 'pending');",
    "html.style.cssText += ';' + rootStyle;",
    "html.style.setProperty('--ds-editor-opacity-base', String((cfg.opacity || {}).editor ?? 0.62));",
    "html.style.setProperty('--ds-sidebar-opacity-base', String((cfg.opacity || {}).sidebar ?? 0.72));",
    "const img = new Image();",
    "img.onload = () => html.setAttribute('data-dream-art-ready', 'true');",
    "img.onerror = () => html.setAttribute('data-dream-art-ready', 'error');",
    "img.src = artUrl;",
    "function applyAppearance() {",
    "if (cfg.appearance !== 'auto') { html.setAttribute('data-dream-appearance', cfg.appearance); return; }",
    "let light = false;",
    "try {",
    "const raw = getComputedStyle(html).getPropertyValue('--vscode-editor-background').trim();",
    "let r = 0, g = 0, b = 0;",
    "const hex = raw.match(/^#([0-9a-f]{6})$/i);",
    "const rgb = raw.match(/rgba?\\(([0-9]+)[,\\s]+([0-9]+)[,\\s]+([0-9]+)/i);",
    "if (hex) { const n = parseInt(hex[1], 16); r = (n >> 16) & 255; g = (n >> 8) & 255; b = n & 255; }",
    "else if (rgb) { r = +rgb[1]; g = +rgb[2]; b = +rgb[3]; }",
    "else { throw new Error('unparsed ' + raw); }",
    "light = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 > 0.5;",
    "} catch (e) { light = matchMedia('(prefers-color-scheme: light)').matches; }",
    "html.setAttribute('data-dream-appearance', light ? 'light' : 'dark');",
    "const tint = cfg.tint && cfg.tint[light ? 'light' : 'dark'];",
    "if (tint) html.style.setProperty('--ds-tint', tint); }",
    "applyAppearance();",
    "const mo = new MutationObserver(() => applyAppearance());",
    "mo.observe(html, { attributes: true, attributeFilter: ['class'] });",
    "setTimeout(applyAppearance, 800);",
    "function taskMode() {",
    "const aux = document.querySelector('.part.auxiliarybar');",
    "const on = !!(aux && aux.querySelector('[class*=\"assistant\"], [class*=\"message\"], [class*=\"chat\"]'));",
    "html.setAttribute('data-dream-task-mode', on ? 'on' : 'off'); }",
    "const to = setInterval(taskMode, 4000);",
    `window[${JSON.stringify(STATE_KEY)}] = {`,
    "revision, styleEl,",
    "cleanup() {",
    "try { styleEl.remove(); } catch (e) {}",
    "try { wallpaper.remove(); } catch (e) {}",
    "html.removeAttribute('data-dream-skin');",
    "html.removeAttribute('data-dream-art-ready');",
    "html.removeAttribute('data-dream-appearance');",
    "html.removeAttribute('data-dream-task-mode');",
    "html.style.removeProperty('--ds-tint');",
    "mo.disconnect(); clearInterval(to);",
    `delete window[${JSON.stringify(STATE_KEY)}]; } };`,
    "return JSON.stringify({ ok: true, alreadyApplied: false, revision });",
    "})()",
  ];
  return parts.join("\n");
}

async function withTarget(fn) {
  const target = await findTarget();
  if (!target) throw new Error("no Cursor Agents page target");
  const ws = await connect(target.webSocketDebuggerUrl);
  try {
    const rpc = makeRpc(ws);
    await rpc("Runtime.enable");
    return await fn(rpc, target);
  } finally {
    try { ws.close(); } catch {}
  }
}

function digest(str) {
  // revision：CSS+設定雜湊（FNV-1a 32bit 雙輪，夠用即可）
  let h1 = 0x811c9dc5, h2 = 0x01000193;
  for (let i = 0; i < str.length; i++) {
    h1 = Math.imul(h1 ^ str.charCodeAt(i), 16777619) >>> 0;
    h2 = Math.imul(h2 + str.charCodeAt(i), 2246822519) >>> 0;
  }
  return (h1 >>> 0).toString(36) + (h2 >>> 0).toString(36);
}

async function injectOnce(rpc, payload, revision) {
  const r = await rpc("Runtime.evaluate", {
    expression: injectExpression(payload, revision),
    returnByValue: true,
  });
  if (r.result?.exceptionDetails) {
    throw new Error("inject threw: " + (r.result.exceptionDetails.exception?.description || "unknown"));
  }
  const out = JSON.parse(r.result.value);
  if (!out.ok) throw new Error("inject reported failure");
  return out;
}

function verifyExpression() {
  return [
    "JSON.stringify((() => {",
    "const html = document.documentElement;",
    `const style = document.getElementById(${JSON.stringify(MARKER_ID)});`,
    `const wallpaper = document.getElementById(${JSON.stringify(WALLPAPER_ID)});`,
    "if (html.getAttribute('data-dream-skin') !== 'active') return { ok:false, reason:'marker missing' };",
    "if (!style || !style.textContent.length) return { ok:false, reason:'css missing' };",
    "if (!wallpaper || !wallpaper.isConnected) return { ok:false, reason:'wallpaper missing' };",
    "const agentPanel = document.querySelector('[data-component=\"agent-panel\"], .agent-panel');",
    "if (!agentPanel) return { ok:false, reason:'agent-panel missing' };",
    "const prompt = document.querySelector('.ui-prompt-input__container, .agent-prompt-input-root [class*=\"ui-prompt-input__container\"]');",
    "if (!prompt) return { ok:false, reason:'prompt input missing' };",
    "return { ok:true, hasAgents:true, artReady: html.getAttribute('data-dream-art-ready') };",
    "})())",
  ].join("\n");
}

const VERIFY_RETRY_REASONS = new Set([
  "marker missing",
  "css missing",
  "wallpaper missing",
  "agent-panel missing",
  "prompt input missing",
]);

function verifyDeadlineMs() {
  return Date.now() + Math.min(Math.max(TIMEOUT_MS, 8000), 30000);
}

async function waitForVerified(rpc, { allowReinject, reinject }) {
  const deadline = verifyDeadlineMs();
  let reinjected = false;
  for (;;) {
    const v = await verifyOnce(rpc);
    if (v.ok) {
      if (v.artReady === "true" || v.artReady === "error") {
        if (v.artReady === "error") throw new Error("Cursor Agents wallpaper decode failed");
        return v;
      }
      if (Date.now() > deadline) throw new Error("Cursor Agents verify timeout: wallpaper not decoded");
      await new Promise((r) => setTimeout(r, 250));
      continue;
    }
    if (
      allowReinject &&
      !reinjected &&
      reinject &&
      (v.reason === "wallpaper missing" || v.reason === "css missing" || v.reason === "marker missing")
    ) {
      reinjected = true;
      await reinject();
      await new Promise((r) => setTimeout(r, 250));
      continue;
    }
    if (VERIFY_RETRY_REASONS.has(v.reason) && Date.now() <= deadline) {
      await new Promise((r) => setTimeout(r, 500));
      continue;
    }
    throw new Error(`Cursor Agents verify failed: ${v.reason}`);
  }
}

async function verifyOnce(rpc) {
  const r = await rpc("Runtime.evaluate", { expression: verifyExpression(), returnByValue: true });
  if (r.result?.exceptionDetails) throw new Error("verify threw");
  return JSON.parse(r.result.value);
}

async function runOnce() {
  const payload = buildPayload(readTheme());
  const revision = digest(payload.css + payload.vars + payload.themeConfig);
  const runs = await withAgentsTargets(async (rpc, target) => {
    const inject = () => injectOnce(rpc, payload, revision);
    const out = await inject();
    const verify = await waitForVerified(rpc, {
      allowReinject: true,
      reinject: inject,
    });
    return { ...out, verify, title: target.title || "Cursor Agents" };
  });

  const primary = runs[0];
  return {
    ...primary.result,
    windows: runs.map((r) => ({ title: r.target.title, ok: true, hasAgents: true })),
  };
}

async function main() {
  if (MODE === "verify") {
    const runs = await withAgentsTargets((rpc) => verifyOnce(rpc));
    console.log(JSON.stringify(runs[0].result));
    process.exit(runs[0].result.ok ? 0 : 1);
  }
  if (MODE === "once") {
    const out = await runOnce();
    console.log(JSON.stringify(out));
    process.exit(0);
  }
  // watch：僅對 Cursor Agents 視窗注入
  const payload = buildPayload(readTheme());
  const revision = digest(payload.css + payload.vars + payload.themeConfig);
  let session = null;
  process.on("SIGTERM", () => process.exit(0));
  for (;;) {
    try {
      const targets = await findAgentsTargets();
      if (!targets.length) {
        session = null;
        throw new Error("no agents target");
      }
      const target = targets[0];
      const key = target.id || target.webSocketDebuggerUrl;
      if (!session || session.key !== key || session.url !== target.webSocketDebuggerUrl) {
        if (session?.ws) { try { session.ws.close(); } catch {} }
        const ws = await connect(target.webSocketDebuggerUrl);
        const rpc = makeRpc(ws);
        await rpc("Runtime.enable");
        session = { key, ws, rpc, url: target.webSocketDebuggerUrl, title: target.title };
      }
      const out = await injectOnce(session.rpc, payload, revision);
      await waitForVerified(session.rpc, {
        allowReinject: true,
        reinject: () => injectOnce(session.rpc, payload, revision),
      });
    } catch {
      if (session?.ws) { try { session.ws.close(); } catch {} }
      session = null;
    }
    await new Promise((r) => setTimeout(r, 3000));
  }
}

main().catch((err) => {
  console.error(String(err.message || err));
  process.exit(1);
});
