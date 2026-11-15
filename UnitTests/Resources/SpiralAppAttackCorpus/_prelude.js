// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
//
// Prepended by SpiralAppAttackRunner to every attack in this folder before it
// is packed. Not an attack: the report channel and a few helpers, so each
// attack file stays one technique. The harness substitutes the __NAME__
// placeholders; MARKER is set only for the attacks that plant one.
//
// `spike.report` is the Debug-only channel the Brief 0066 probe uses; the
// harness grants it on top of the production set. Everything else an attack
// calls goes through the real shell checks and the real native session.

import { useEffect as __useEffect } from "react";

const ATTACK = "__ATTACK_ID__";
const CANARY = "http://127.0.0.1:47913/c/__ATTACK_ID__";
const CANARY_LOCALHOST = "http://localhost:47913/c/__ATTACK_ID__";
const CANARY_TLS = "https://127.0.0.1:47915/c/__ATTACK_ID__";
const CANARY_WS = "ws://127.0.0.1:47913/c/__ATTACK_ID__";
const CANARY_HOST = "127.0.0.1:47913";
const MARKER = "__MARKER__";
const SVG = "http://www.w3.org/2000/svg";
const XLINK = "http://www.w3.org/1999/xlink";

const __port = globalThis.__spiralPort;
let __seq = 0;

/** One bridge request on the real port, answered or timed out. A malformed one gets no answer at all. */
const call = (method, args, userActivation = false, id, timeoutMs = 7000) =>
  new Promise((resolve) => {
    const rid = id ?? `atk-${++__seq}`;
    const on = (event) => {
      if (event.data && event.data.id === rid) {
        clearTimeout(timer);
        __port.removeEventListener("message", on);
        resolve(event.data);
      }
    };
    const timer = setTimeout(() => {
      __port.removeEventListener("message", on);
      resolve({ ok: false, code: "no-reply" });
    }, timeoutMs);
    __port.addEventListener("message", on);
    __port.postMessage({ id: rid, method, args, userActivation });
  });

const results = [];
/** outcome: "blocked" | "REACHED" | "info" */
const note = (check, outcome, detail = "") => {
  results.push({ check, outcome, detail: String(detail).slice(0, 700) });
};
const describe = (error) => `${error && error.name}: ${error && error.message}`;
/** fn returns { reached, detail }; a throw is a refusal. */
const probe = async (check, fn) => {
  try {
    const r = await fn();
    note(check, r && r.reached ? "REACHED" : r && r.info ? "info" : "blocked", r && r.detail !== undefined ? r.detail : "no effect");
  } catch (error) {
    note(check, "blocked", describe(error));
  }
};
/** An attempt whose effect only the canary can see. */
const attempt = (check, fn) =>
  probe(check, async () => {
    const value = await fn();
    return { info: true, detail: `no exception${value === undefined ? "" : `: ${String(value).slice(0, 200)}`}` };
  });
const exists = (check, value) => note(check, value ? "REACHED" : "blocked", value ? `present: ${typeof value}` : "absent");
const bridge = (check, reply) => note(check, reply && reply.ok ? "REACHED" : "blocked", JSON.stringify(reply));
const settle = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * One step per host gesture (`@host gesture …`): each runs inside the message
 * event the gesture arrives with, so a step sees whatever activation WebKit
 * carried over. Resolves once every step ran, or after `ms`.
 */
const perGesture = (steps, ms = 20000) => new Promise((resolve) => {
  let next = 0;
  const timer = setTimeout(() => { note("host gestures", "info", `${next}/${steps.length} arrived`); resolve(); }, ms);
  window.addEventListener("message", (event) => {
    if (!event.data || event.data.spiralHostGesture === undefined || next >= steps.length) return;
    const [check, fn] = steps[next++];
    note(`${check}: activation`, "info", navigator.userActivation ? String(navigator.userActivation.isActive) : "no userActivation");
    probe(check, fn).then(() => { if (next >= steps.length) { clearTimeout(timer); resolve(); } });
  });
});

let __finished = false;
const finish = () => {
  if (__finished) return undefined;
  __finished = true;
  return call("spike.report", { attack: ATTACK, results });
};

const inject = (html, where = document.body) => {
  const box = document.createElement("div");
  box.innerHTML = html;
  where.appendChild(box);
  return box;
};
const make = (tag, attrs = {}, where = document.body, ns) => {
  const element = ns ? document.createElementNS(ns, tag) : document.createElement(tag);
  for (const [name, value] of Object.entries(attrs)) element.setAttribute(name, value);
  where.appendChild(element);
  return element;
};

/** Mounts with the attack: runs `run`, waits `after` ms, reports. */
function Done({ run, after = 1500 }) {
  __useEffect(() => {
    (async () => {
      try {
        if (run) await run();
      } catch (error) {
        note("run", "info", describe(error));
      }
      await settle(after);
      await finish();
    })();
  }, []);
  return null;
}
