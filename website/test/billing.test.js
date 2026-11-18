"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const pageScript = readFileSync(
  path.join(__dirname, "..", "billing", "billing.js"),
  "utf8",
);

function createElement() {
  return {
    listeners: new Map(),
    dataset: {},
    value: "",
    checked: false,
    disabled: false,
    hidden: false,
    textContent: "",
    addEventListener(name, listener) {
      this.listeners.set(name, listener);
    },
    setAttribute() {},
    removeAttribute() {},
    closest() {
      return null;
    },
    querySelector() {
      return createElement();
    },
    append() {},
    replaceChildren() {},
    focus() {},
    reportValidity() {},
  };
}

function createStorage() {
  const values = new Map();
  return {
    getItem: (key) => (values.has(key) ? values.get(key) : null),
    setItem: (key, value) => values.set(key, String(value)),
    removeItem: (key) => values.delete(key),
    values,
  };
}

function createPage(fetchImplementation) {
  const elements = new Map();
  const element = (selector) => {
    if (!elements.has(selector)) elements.set(selector, createElement());
    return elements.get(selector);
  };
  const document = {
    querySelector: element,
    querySelectorAll: () => [],
    addEventListener() {},
    createElement: () => createElement(),
    visibilityState: "visible",
  };
  const sessionStorage = createStorage();
  const window = {
    location: { search: "", origin: "https://stroy.com.kg", assign() {} },
    setTimeout: () => 0,
    clearTimeout() {},
    setInterval: () => 0,
    clearInterval() {},
  };
  vm.runInNewContext(pageScript, {
    document,
    window,
    sessionStorage,
    fetch: fetchImplementation,
    URLSearchParams,
    URL,
    Headers,
    AbortController,
    Intl,
    navigator: { userAgent: "node", platform: "node", maxTouchPoints: 0 },
    crypto: globalThis.crypto,
    Element: function Element() {},
  });
  return { element, sessionStorage };
}

function jsonResponse(status, payload) {
  return {
    status,
    ok: status >= 200 && status < 300,
    async json() {
      return payload;
    },
  };
}

function authHeader(call) {
  return call.options.headers.get("Authorization");
}

test("billing login exchanges the bootstrap token for a session before loading the account", async () => {
  const calls = [];
  const responses = {
    "/api/v1/auth/sms/verify": jsonResponse(200, {
      access_token: "bootstrap-token",
    }),
    "/api/v1/auth/session": jsonResponse(201, {
      access_token: "session-access",
      refresh_token: "session-refresh",
    }),
    "/api/v1/subscriptions/status": jsonResponse(200, { plan: "trial" }),
    "/api/v1/subscriptions/plans": jsonResponse(200, { plans: [] }),
    "/api/v1/auth/session/logout": jsonResponse(200, {
      status: "logged_out",
    }),
  };
  const page = createPage(async (url, options) => {
    const route = new URL(url).pathname;
    calls.push({ route, options });
    const response = responses[route];
    assert.ok(response, `unexpected request: ${route}`);
    return response;
  });

  page.element("#phone").value = "+996700000000";
  page.element("#code").value = "123456";
  await page.element("#code-form").listeners.get("submit")({
    preventDefault() {},
  });

  const routes = calls.map((call) => call.route);
  assert.deepEqual(routes.slice(0, 2), [
    "/api/v1/auth/sms/verify",
    "/api/v1/auth/session",
  ]);
  assert.equal(authHeader(calls[1]), "Bearer bootstrap-token");
  assert.equal(calls[1].options.method, "POST");

  const accountCalls = calls.slice(2);
  assert.ok(accountCalls.length >= 2);
  for (const call of accountCalls) {
    assert.equal(authHeader(call), "Bearer session-access");
  }
  assert.equal(
    page.sessionStorage.getItem("stroy.billing.session"),
    "session-access",
  );
  assert.equal(
    page.sessionStorage.getItem("stroy.billing.refresh"),
    "session-refresh",
  );

  page.element("#logout").listeners.get("click")();
  const logout = calls.at(-1);
  assert.equal(logout.route, "/api/v1/auth/session/logout");
  assert.equal(authHeader(logout), "Bearer session-access");
  assert.deepEqual(JSON.parse(logout.options.body), {
    refresh_token: "session-refresh",
  });
  assert.equal(page.sessionStorage.getItem("stroy.billing.session"), null);
  assert.equal(page.sessionStorage.getItem("stroy.billing.refresh"), null);
});

test("billing login fails closed when the session exchange is rejected", async () => {
  const page = createPage(async (url) => {
    const route = new URL(url).pathname;
    if (route === "/api/v1/auth/sms/verify") {
      return jsonResponse(200, { access_token: "bootstrap-token" });
    }
    if (route === "/api/v1/auth/session") {
      return jsonResponse(401, { error: "login session token is expired" });
    }
    throw new Error(`unexpected request: ${route}`);
  });

  page.element("#phone").value = "+996700000000";
  page.element("#code").value = "123456";
  await page.element("#code-form").listeners.get("submit")({
    preventDefault() {},
  });

  assert.equal(page.sessionStorage.getItem("stroy.billing.session"), null);
  assert.equal(page.element("#notice").dataset.kind, "error");
  assert.equal(page.element("#login-panel").hidden, false);
});
