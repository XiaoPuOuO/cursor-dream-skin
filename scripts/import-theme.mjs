#!/usr/bin/env node
// 將 Codex Dream Skin 匯出包（目錄或 .zip）轉為 cursor-dream-skin preset。
//
// 用法：
//   node scripts/import-theme.mjs ~/Downloads/asuna-starlight-glass-0.1.0
//   node scripts/import-theme.mjs ~/Downloads/theme.zip --out presets
//   node scripts/import-theme.mjs ./pack --force
//
// 輸出：presets/<id>/theme.json + dream-skin.css + background.*
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const ASSETS = path.join(REPO_ROOT, "assets");
const PART_MAP = JSON.parse(fs.readFileSync(path.join(ASSETS, "codex-part-map.json"), "utf8"));
const AGENTS_OVERLAY = fs.readFileSync(path.join(ASSETS, "dream-skin.agents.css"), "utf8");

function arg(name, fallback = undefined) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

const inputPath = process.argv.find((a, i) => i >= 2 && !a.startsWith("--")) || process.exit(2);
const outRoot = path.resolve(arg("out", path.join(REPO_ROOT, "presets")));
const force = process.argv.includes("--force");

function fail(msg) {
  console.error(`import-theme: ${msg}`);
  process.exit(1);
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function extractZip(zipPath) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "cds-import-"));
  execFileSync("unzip", ["-q", zipPath, "-d", tmp], { stdio: "inherit" });
  return { dir: resolvePackageDir(tmp), cleanup: () => fs.rmSync(tmp, { recursive: true, force: true }) };
}

function resolvePackageDir(root) {
  const required = ["theme.json", "theme.css"];
  const hasAll = (dir) => required.every((f) => fs.existsSync(path.join(dir, f)));
  if (hasAll(root)) return root;
  const children = fs.readdirSync(root, { withFileTypes: true }).filter((d) => d.isDirectory());
  if (children.length === 1 && hasAll(path.join(root, children[0].name))) {
    return path.join(root, children[0].name);
  }
  for (const d of children) {
    const p = path.join(root, d.name);
    if (hasAll(p)) return p;
  }
  fail(`找不到 Codex 主題根目錄（需含 theme.json + theme.css）：${root}`);
}

function loadPackage(input) {
  const abs = path.resolve(input);
  if (!fs.existsSync(abs)) fail(`路徑不存在：${abs}`);
  if (abs.endsWith(".zip")) return extractZip(abs);
  return { dir: resolvePackageDir(abs), cleanup: () => {} };
}

function parseCodexCss(cssText) {
  const parts = {};
  const re = /\[data-ds-part="([^"]+)"\]\s*\{([^}]*)\}/g;
  let m;
  while ((m = re.exec(cssText))) {
    const props = {};
    for (const line of m[2].split(";")) {
      const idx = line.indexOf(":");
      if (idx < 0) continue;
      const key = line.slice(0, idx).trim();
      const val = line.slice(idx + 1).trim();
      if (key && val) props[key] = val;
    }
    parts[m[1]] = props;
  }
  return parts;
}

function parseBlur(props) {
  const bf = props["backdrop-filter"] || props["backdropFilter"] || "";
  const m = bf.match(/blur\(\s*([^)]+)\)/);
  return m ? m[1].trim() : null;
}

function parseAlpha(color) {
  const rgba = color.match(/rgba?\(\s*[\d.]+\s*,\s*[\d.]+\s*,\s*[\d.]+\s*,\s*([\d.]+)\s*\)/i);
  if (rgba) return Number(rgba[1]);
  if (/transparent/i.test(color)) return 0;
  return null;
}

function hexToRgb(hex) {
  const n = parseInt(hex.replace("#", ""), 16);
  return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
}

function normalizeHex(color) {
  if (!color) return null;
  const c = color.trim();
  if (/^#[0-9a-f]{6}$/i.test(c)) return c.toLowerCase();
  if (/^#[0-9a-f]{3}$/i.test(c)) {
    return `#${c[1]}${c[1]}${c[2]}${c[2]}${c[3]}${c[3]}`.toLowerCase();
  }
  return c;
}

function mapSafeArea(codexSafe) {
  const map = { auto: "center", none: "center", left: "left", right: "right", center: "center" };
  return map[String(codexSafe || "center").toLowerCase()] || "center";
}

function buildCursorTheme(codex, manifest, partStyles) {
  const art = codex.art || {};
  const colors = codex.colors || {};
  const sidebarProps = partStyles.sidebar || {};
  const sidebarAlpha = parseAlpha(sidebarProps["background-color"] || "") ?? 0.62;
  const composerTransparent = /transparent/i.test(partStyles.composer?.["background-color"] || "transparent");

  const bgHex = normalizeHex(colors.background) || "#080b18";
  const { r, g, b } = /^#/.test(bgHex) ? hexToRgb(bgHex) : { r: 8, g: 11, b: 24 };

  return {
    schema: "cursor-dream-skin-theme/1",
    name: codex.name || codex.id,
    id: codex.id,
    version: 1,
    appearance: codex.appearance || "auto",
    background: codex.image || codex.background || "background.png",
    opacity: {
      workbench: 0.38,
      sidebar: Math.round(Math.min(0.72, sidebarAlpha * 0.36) * 100) / 100,
      panel: 0.45,
      editor: composerTransparent ? 0.32 : 0.58,
    },
    tint: {
      dark: `rgba(${r}, ${g}, ${b}, 0.12)`,
      light: `rgba(${Math.min(r + 20, 255)}, ${Math.min(g + 15, 255)}, ${Math.min(b + 30, 255)}, 0.18)`,
    },
    safeArea: {
      position: mapSafeArea(art.safeArea),
      focusX: art.focusX ?? 0.5,
      focusY: art.focusY ?? 0.5,
    },
    taskMode: {
      raiseOpacity: art.taskMode === "ambient" ? 0.1 : 0.12,
    },
    source: {
      codex: {
        schemaVersion: codex.schemaVersion ?? 1,
        themeId: codex.id,
        packageVersion: manifest?.packageVersion ?? null,
        importedAt: new Date().toISOString(),
      },
    },
  };
}

function cssDecl(props) {
  const lines = [];
  const map = {
    "background-color": "background",
    "border-color": "border-color",
    "border-width": "border-width",
    "border-style": "border-style",
    "border-radius": "border-radius",
    "box-shadow": "box-shadow",
    "backdrop-filter": "backdrop-filter",
  };
  for (const [from, to] of Object.entries(map)) {
    if (props[from]) lines.push(`  ${to}: ${props[from]} !important;`);
  }
  if (props["background-color"]?.includes("transparent")) {
    lines.push("  backdrop-filter: none !important;");
  }
  return lines.join("\n");
}

function selectorsForPart(partKey) {
  const entry = PART_MAP.parts[partKey];
  if (!entry) return [];
  return [...(entry.classic || []), ...(entry.classicInner || []), ...(entry.agents || [])];
}

function buildDreamSkinCss(codex, partStyles) {
  const colors = codex.colors || {};
  const sidebarProps = partStyles.sidebar || {};
  const dialogProps = partStyles.dialog || {};
  const blur = parseBlur(sidebarProps) || parseBlur(dialogProps) || "22px";
  const line = sidebarProps["border-color"] || "rgba(215, 228, 255, 0.18)";
  const lineStrong = dialogProps["border-color"] || line;
  const glassSidebar = sidebarProps["background-color"] || "rgba(8, 11, 24, 0.62)";
  const glassDialog = dialogProps["background-color"] || "rgba(18, 26, 49, 0.78)";

  const chunks = [];
  chunks.push(`/*
 * ${codex.name || codex.id} — 由 Codex 包匯入
 * source: ${codex.id} (schemaVersion ${codex.schemaVersion ?? 1})
 * 錨點對照：assets/codex-part-map.json
 */

:root {
  --ds-workbench-opacity: 0.38;
  --ds-sidebar-opacity: 0.22;
  --ds-panel-opacity: 0.45;
  --ds-editor-opacity: 0.32;
  --ds-tint: rgba(8, 11, 24, 0.12);
  --ds-blur: ${blur};
  --ds-bg: ${normalizeHex(colors.background) || "#080b18"};
  --ds-panel: ${normalizeHex(colors.panel) || "#121a31"};
  --ds-panel-alt: ${normalizeHex(colors.panelAlt) || "#1a2244"};
  --ds-accent: ${normalizeHex(colors.accent) || "#a7c7ff"};
  --ds-accent-alt: ${normalizeHex(colors.accentAlt) || "#d7e4ff"};
  --ds-line: ${line};
  --ds-line-strong: ${lineStrong};
  --ds-glass-sidebar: ${glassSidebar};
  --ds-glass-input: ${glassDialog};
  --ds-glass-dialog: ${glassDialog};
}

#cursor-dream-skin-wallpaper {
  position: fixed;
  inset: 0;
  z-index: 0;
  pointer-events: none;
  background-position: var(--ds-art-position, center);
  background-size: var(--ds-art-size, cover);
  background-repeat: no-repeat;
  background-image: var(--ds-art-image);
}

#cursor-dream-skin-wallpaper::after {
  content: "";
  position: absolute;
  inset: 0;
  background: var(--ds-tint);
}

html[data-dream-skin="active"] .monaco-workbench {
  background: transparent !important;
}

html[data-dream-skin="active"] .monaco-workbench .part.statusbar {
  background: color-mix(in srgb, var(--ds-panel) 55%, transparent) !important;
  border-top: 1px solid var(--ds-line);
}

html[data-dream-skin="active"] .monaco-workbench .part.panel,
html[data-dream-skin="active"] .monaco-workbench .part.panel .composite.title {
  background: transparent !important;
}

html[data-dream-skin="active"] .monaco-workbench .part.panel {
  backdrop-filter: blur(var(--ds-blur)) saturate(1.15);
  background: color-mix(in srgb, var(--ds-panel) calc(var(--ds-panel-opacity) * 100%), transparent) !important;
  border-top: 1px solid var(--ds-line);
}

html[data-dream-skin="active"] .monaco-workbench .part.editor,
html[data-dream-skin="active"] .monaco-workbench .part.editor > .content,
html[data-dream-skin="active"] .monaco-workbench .editor-group-container,
html[data-dream-skin="active"] .monaco-workbench .editor-group-container > .title,
html[data-dream-skin="active"] .monaco-workbench .monaco-editor,
html[data-dream-skin="active"] .monaco-workbench .monaco-editor .monaco-editor-background,
html[data-dream-skin="active"] .monaco-workbench .monaco-editor .margin {
  background: transparent !important;
}

html[data-dream-skin="active"] .monaco-workbench .part.auxiliarybar {
  border-left: none;
}
`);

  for (const [partKey, props] of Object.entries(partStyles)) {
    const sels = selectorsForPart(partKey);
    if (!sels.length) continue;
    const body = cssDecl(props);
    if (!body.trim()) continue;
    chunks.push(`/* Codex [data-ds-part="${partKey}"] */`);
    chunks.push(`html[data-dream-skin="active"] ${sels.join(",\nhtml[data-dream-skin=\"active\"] ")} {`);
    chunks.push(body);
    chunks.push("}\n");
  }

  chunks.push("/* --- Cursor Agents overlay（import 附加） --- */\n");
  chunks.push(AGENTS_OVERLAY.trim());
  chunks.push("");
  return chunks.join("\n");
}

function validateManifest(manifest, dir) {
  if (!manifest?.files?.length) return;
  for (const f of manifest.files) {
    if (!f.path || !f.sha256) continue;
    const fp = path.join(dir, f.path);
    if (!fs.existsSync(fp)) fail(`manifest 缺少檔案：${f.path}`);
  }
}

// --- main ---
const pkg = loadPackage(inputPath);
let cleanup = pkg.cleanup;
try {
  const dir = pkg.dir;
  const codexThemePath = path.join(dir, "theme.json");
  const codexCssPath = path.join(dir, "theme.css");
  const codexTheme = readJson(codexThemePath);
  const codexCss = fs.readFileSync(codexCssPath, "utf8");
  if (!codexTheme.id) fail("theme.json 缺少 id");
  if (!codexCss.trim()) fail("theme.css 為空");

  const manifestPath = path.join(dir, "manifest.json");
  const manifest = fs.existsSync(manifestPath) ? readJson(manifestPath) : null;
  validateManifest(manifest, dir);

  const bgName = codexTheme.image || codexTheme.background || "background.png";
  const bgPath = path.join(dir, bgName);
  if (!fs.existsSync(bgPath)) fail(`找不到背景圖：${bgName}`);

  const partStyles = parseCodexCss(codexCss);
  const cursorTheme = buildCursorTheme(codexTheme, manifest, partStyles);
  cursorTheme.background = path.basename(bgName);
  const dreamSkinCss = buildDreamSkinCss(codexTheme, partStyles);

  const dest = path.join(outRoot, codexTheme.id);
  if (fs.existsSync(dest) && !force) {
    fail(`preset 已存在：${dest}（加 --force 覆寫）`);
  }
  fs.mkdirSync(dest, { recursive: true });
  fs.writeFileSync(path.join(dest, "theme.json"), `${JSON.stringify(cursorTheme, null, 2)}\n`);
  fs.writeFileSync(path.join(dest, "dream-skin.css"), dreamSkinCss);
  fs.copyFileSync(bgPath, path.join(dest, cursorTheme.background));

  console.log(JSON.stringify({
    ok: true,
    id: codexTheme.id,
    name: codexTheme.name,
    dest,
    parts: Object.keys(partStyles),
    background: cursorTheme.background,
  }, null, 2));
} finally {
  cleanup();
}
