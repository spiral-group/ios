// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-tap-gesture
// @threat device
// @expect contained
// @checklist —
// @checks real-tap
// @wait 600000
// @note Device pass: a person taps the post six times; each tap is a real user gesture spent on one API. Run alone (TEST_RUNNER_SPIRAL_CORPUS_ONLY=spiral-tap-gesture); the main run skips it.

import { useState as __useState } from "react";

// One API per tap: some of them spend the gesture (share, fullscreen), so they
// never share one.
const STEPS = [
  ["clipboard.writeText", async () => { await navigator.clipboard.writeText("spiral " + ATTACK); return { reached: true, detail: "resolved" }; }],
  ["clipboard.write ClipboardItem", async () => {
    await navigator.clipboard.write([new ClipboardItem({ "text/plain": new Blob(["spiral item " + ATTACK], { type: "text/plain" }) })]);
    return { reached: true, detail: "resolved" };
  }],
  ["navigator.share", async () => {
    if (!navigator.share) return { reached: false, detail: "absent" };
    await navigator.share({ text: "spiral " + ATTACK, url: CANARY + "/share" });
    return { reached: true, detail: "resolved" };
  }],
  ["getDisplayMedia", async () => {
    const md = navigator.mediaDevices;
    if (!md || !md.getDisplayMedia) return { reached: false, detail: md ? "getDisplayMedia absent" : "mediaDevices absent" };
    const stream = await md.getDisplayMedia({ video: true });
    stream.getTracks().forEach((t) => t.stop());
    return { reached: true, detail: "a stream" };
  }],
  ["fullscreen", async () => {
    const el = document.documentElement;
    const request = el.requestFullscreen || el.webkitRequestFullscreen;
    if (!request) return { reached: false, detail: "no requestFullscreen" };
    await request.call(el);
    await settle(500);
    const on = document.fullscreenElement || document.webkitFullscreenElement;
    if (document.exitFullscreen && on) await document.exitFullscreen();
    return { reached: !!on, detail: on ? "went fullscreen" : "resolved, nothing fullscreen" };
  }],
  ["audio after a tap", async () => {
    const c = new AudioContext();
    const o = c.createOscillator();
    const g = c.createGain();
    g.gain.value = 0.05;
    o.connect(g).connect(c.destination);
    o.start();
    await c.resume();
    await settle(400);
    o.stop();
    const state = c.state;
    await c.close();
    return { info: true, detail: `AudioContext ${state} (a post may play sound after a tap; this records whether it can)` };
  }],
];

function Tap() {
  const [step, setStep] = __useState(0);
  const [last, setLast] = __useState("");
  __useEffect(() => {
    const giveUp = setTimeout(() => { note("taps", "info", "timed out before every step was tapped"); finish(); }, 540000);
    return () => clearTimeout(giveUp);
  }, []);
  const onTap = async (event) => {
    if (step >= STEPS.length) return;
    const [name, fn] = STEPS[step];
    setStep(step + 1);
    note(`tap ${step + 1}: isTrusted`, "info", String(event.isTrusted) + " / userActivation.isActive " + String(navigator.userActivation && navigator.userActivation.isActive));
    await probe(name, fn);
    setLast(`${name}: ${results[results.length - 1].outcome}`);
    if (step + 1 >= STEPS.length) { await settle(1500); finish(); }
  };
  const done = step >= STEPS.length;
  return (
    <div onClick={onTap} style={{ position: "fixed", inset: 0, display: "flex", flexDirection: "column", alignItems: "center",
      justifyContent: "center", background: done ? "#1b5e20" : "#b71c1c", color: "white", font: "bold 28px -apple-system", textAlign: "center" }}>
      <div>{done ? "DONE" : `TAP HERE ${step + 1}/${STEPS.length}`}</div>
      <div style={{ font: "16px -apple-system", marginTop: 12 }}>{done ? "" : STEPS[step][0]}</div>
      <div style={{ font: "13px -apple-system", marginTop: 12, opacity: 0.8 }}>{last}</div>
    </div>
  );
}

export default Tap;
