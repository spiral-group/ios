// Copyright 2026 the Spiral authors. AGPL-3.0-or-later.
// @attack api-insertadjacenthtml
// @threat network
// @expect blocked
// @checklist api-insertadjacenthtml

export default () => <Done after={2000} run={async () => {

  document.body.insertAdjacentHTML("beforeend", '<img src="' + CANARY + '/adjacent-img"><video poster="' + CANARY + '/adjacent-poster"></video>');
  document.body.insertAdjacentHTML("afterbegin", '<svg><image href="' + CANARY + '/adjacent-svg"/></svg>');
  const r = document.createRange(); document.body.appendChild(r.createContextualFragment('<img src="' + CANARY + '/fragment">'));
  new DOMParser().parseFromString('<img src="' + CANARY + '/domparser">', "text/html");
}} />;
