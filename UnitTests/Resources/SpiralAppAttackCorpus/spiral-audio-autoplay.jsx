// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack spiral-audio-autoplay
// @threat annoyance
// @expect blocked
// @checklist —

export default () => <Done after={2000} run={async () => {

  await probe("AudioContext runs without a tap", async () => { const c = new AudioContext(); const o = c.createOscillator(); o.connect(c.destination); o.start(); await settle(300); return { reached: c.state === "running", detail: c.state }; });
  await probe("audio element plays without a tap", async () => { const a = make("audio"); a.src = "data:audio/wav;base64,UklGRiQAAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YQAAAAA="; await a.play(); return { reached: true }; });
  await probe("speechSynthesis without a tap", async () => { speechSynthesis.speak(new SpeechSynthesisUtterance("hello")); await settle(300); return { reached: speechSynthesis.speaking }; });
}} />;
