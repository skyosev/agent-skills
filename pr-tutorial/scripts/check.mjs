#!/usr/bin/env node
// Checks a pr-tutorial page before it is published.
// Usage: node check.mjs <page.html>. Exit code 1 when an error is found.
import { readFileSync } from 'node:fs';
import { Script } from 'node:vm';

const VOID = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'source', 'track', 'wbr']);
const SHA = /^[0-9a-f]{40}$/;

const file = process.argv[2];
if (!file) {
    console.error('usage: node check.mjs <page.html>');
    process.exit(2);
}
const html = readFileSync(file, 'utf8');
const errors = [];
const lineOf = (index) => html.slice(0, index).split('\n').length;

// Scripts: each inline script must parse.
for (const m of html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)) {
    try {
        new Script(m[1]);
    } catch (e) {
        errors.push(`line ${lineOf(m.index)}: script does not parse: ${e.message}`);
    }
}

// Tags: every open tag has its close tag, in order. Script, style and comment bodies are blanked first, keeping their length.
const blank = (s) => s.replace(/[^\n]/g, ' ');
const markup = html
    .replace(/<!--[\s\S]*?-->/g, blank)
    .replace(/(<(script|style)\b[^>]*>)([\s\S]*?)(<\/\2>)/g, (_, open, _tag, body, close) => open + blank(body) + close);
const stack = [];
for (const m of markup.matchAll(/<(\/?)([a-zA-Z][\w-]*)\b[^>]*?(\/?)>/g)) {
    const [, closing, rawName, selfClosing] = m;
    const name = rawName.toLowerCase();
    if (VOID.has(name) || selfClosing) {
        continue;
    }
    if (!closing) {
        stack.push({ name, line: lineOf(m.index) });
        continue;
    }
    const top = stack.pop();
    if (!top || top.name !== name) {
        errors.push(`line ${lineOf(m.index)}: </${name}> closes ${top ? `<${top.name}> from line ${top.line}` : 'nothing'}`);
        if (top) {
            stack.push(top);
        }
    }
}
for (const open of stack) {
    errors.push(`line ${open.line}: <${open.name}> is never closed`);
}

// Placeholders from the template.
for (const m of html.matchAll(/\[\[FILL/g)) {
    errors.push(`line ${lineOf(m.index)}: a [[FILL]] placeholder is left`);
}

// Tabs and panels: each tab controls a panel that exists, and each panel has a tab.
const controls = [...html.matchAll(/role="tab"[^>]*aria-controls="([^"]+)"/g)].map((m) => m[1]);
const panelIds = [...html.matchAll(/<section[^>]*role="tabpanel"[^>]*id="([^"]+)"/g)].map((m) => m[1]);
for (const id of controls.filter((c) => !panelIds.includes(c))) {
    errors.push(`tab controls "${id}", but no tabpanel has that id`);
}
for (const id of panelIds.filter((p) => !controls.includes(p))) {
    errors.push(`tabpanel "${id}" has no tab`);
}

// Source links: a full SHA, and one commit for the whole page.
const shas = new Set();
for (const m of html.matchAll(/href="https:\/\/github\.com\/[^/"]+\/[^/"]+\/blob\/([^/"]+)\//g)) {
    if (SHA.test(m[1])) {
        shas.add(m[1]);
    } else {
        errors.push(`line ${lineOf(m.index)}: source link uses "${m[1]}", not a full 40-character SHA`);
    }
}
if (shas.size > 1) {
    errors.push(`source links name ${shas.size} commits: ${[...shas].join(', ')}`);
}

console.log(`${controls.length} tabs, ${panelIds.length} panels, ${shas.size} pinned commit(s)`);
for (const e of errors) {
    console.log(`error: ${e}`);
}
process.exit(errors.length > 0 ? 1 : 0);
