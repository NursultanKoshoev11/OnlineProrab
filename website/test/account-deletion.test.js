"use strict";

const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const pageScript = readFileSync(
  path.join(__dirname, "..", "account-deletion.js"),
  "utf8",
);

test("public pages and resources comply with the production CSP", () => {
  const websiteRoot = path.join(__dirname, "..");
  const pages = [
    "index.html",
    "privacy/index.html",
    "terms/index.html",
    "support/index.html",
    "account-deletion/index.html",
    "billing/index.html",
  ];
  const html = pages
    .map((page) => readFileSync(path.join(websiteRoot, page), "utf8"))
    .join("\n");
  const nginx = readFileSync(path.join(websiteRoot, "nginx.conf"), "utf8");
  const css = readFileSync(path.join(websiteRoot, "styles.css"), "utf8");
  const privacy = readFileSync(
    path.join(websiteRoot, "privacy/index.html"),
    "utf8",
  );
  const policy = nginx.match(
    /add_header Content-Security-Policy "([^"]+)" always;/,
  )?.[1];

  assert.ok(policy, "CSP must be present on successful and error responses");
  for (const directive of [
    "default-src 'self'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    "object-src 'none'",
    "script-src 'self'",
    "style-src 'self'",
    "img-src 'self'",
    "font-src 'self'",
  ]) {
    assert.ok(policy.includes(directive), `CSP is missing ${directive}`);
  }
  assert.ok(
    policy.includes("connect-src 'self' https://api.stroy.com.kg"),
    "CSP must permit the account-deletion API origin",
  );

  assert.doesNotMatch(html, /<script(?![^>]*\bsrc\s*=)[^>]*>/i);
  assert.doesNotMatch(html, /<style\b/i);
  assert.doesNotMatch(html, /\sstyle\s*=/i);
  assert.doesNotMatch(
    html,
    /<(?:script|img|link(?!\b[^>]*\brel\s*=\s*["']canonical["'])|source|iframe)\b[^>]*\b(?:src|href)\s*=\s*["']https?:\/\//i,
  );
  assert.doesNotMatch(css, /url\(\s*["']?https?:\/\//i);

  for (const header of [
    "Referrer-Policy",
    "Strict-Transport-Security",
    "X-Content-Type-Options",
    "X-Frame-Options",
    "Permissions-Policy",
  ]) {
    assert.match(nginx, new RegExp(`add_header ${header} .+ always;`));
  }
  assert.match(
    nginx,
    /add_header Strict-Transport-Security "max-age=31536000" always;/,
  );
  assert.match(privacy, /аудио.*серверы Apple для распознавания/s);
  assert.match(privacy, /Google Gemini, Groq или\s+OpenRouter/);
  assert.match(privacy, /суммы, валюты,\s+поставщиков и даты/);
  assert.match(privacy, /бессрочно храним в закрытом журнале/);
  assert.match(
    privacy,
    /идентификатор удалённого\s+аккаунта\s+либо путь удалённого файла/,
  );
  assert.match(privacy, /нормализованный\s+номер телефона, IP-адрес клиента/);
  assert.match(privacy, /обычно хранятся 7 дней/);
  assert.match(privacy, /24\s+часа после\s+истечения срока действия кода/);
  assert.match(
    privacy,
    /Плановая очистка запускается\s+примерно каждые 6 часов/,
  );
});

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
    focus() {},
    scrollIntoView() {},
  };
}

function createPage(fetchImplementation) {
  const ids = [
    "phone-form",
    "code-form",
    "phone",
    "code",
    "request-code",
    "verify-code",
    "resend-code",
    "confirm-section",
    "confirm-delete",
    "delete-account",
    "verified-phone",
    "account-delete-status",
  ];
  const elements = new Map(ids.map((id) => [id, createElement()]));
  const document = {
    querySelector(selector) {
      const element = elements.get(selector.slice(1));
      assert.ok(element, `unexpected page selector: ${selector}`);
      return element;
    },
  };

  vm.runInNewContext(pageScript, { document, fetch: fetchImplementation });
  return elements;
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

async function submit(element) {
  await element.listeners.get("submit")({ preventDefault() {} });
}

test("account deletion requests SMS, verifies the code, then deletes with the bearer token", async () => {
  const calls = [];
  const responses = [
    jsonResponse(202, { status: "code_requested" }),
    jsonResponse(200, { access_token: "test-access-token" }),
    jsonResponse(200, { status: "deleted" }),
  ];
  const elements = createPage(async (url, options) => {
    calls.push({ url, options });
    return responses.shift();
  });

  elements.get("phone").value = "+996 700 000 000";
  await submit(elements.get("phone-form"));
  assert.equal(elements.get("phone").value, "+996700000000");
  assert.equal(elements.get("code-form").hidden, false);

  elements.get("code").value = "001234";
  await submit(elements.get("code-form"));
  assert.equal(elements.get("phone-form").hidden, true);
  assert.equal(elements.get("confirm-section").hidden, false);
  assert.equal(elements.get("verified-phone").textContent, "+996700000000");

  elements.get("confirm-delete").checked = true;
  elements.get("confirm-delete").listeners.get("change")();
  await elements.get("delete-account").listeners.get("click")();

  assert.equal(calls.length, 3);
  assert.equal(
    calls[0].url,
    "https://api.stroy.com.kg/api/v1/auth/sms/request",
  );
  assert.equal(calls[0].options.method, "POST");
  assert.deepEqual(JSON.parse(calls[0].options.body), {
    phone: "+996700000000",
  });
  assert.equal(
    calls[1].url,
    "https://api.stroy.com.kg/api/v1/account/deletion/verify",
  );
  assert.deepEqual(JSON.parse(calls[1].options.body), {
    phone: "+996700000000",
    code: "001234",
  });
  assert.equal(calls[2].url, "https://api.stroy.com.kg/api/v1/account");
  assert.equal(calls[2].options.method, "DELETE");
  assert.equal(
    calls[2].options.headers.Authorization,
    "Bearer test-access-token",
  );
  for (const call of calls) {
    assert.equal(call.options.credentials, "omit");
    assert.equal(call.options.cache, "no-store");
    assert.equal(call.options.referrerPolicy, "no-referrer");
  }
  assert.match(
    elements.get("account-delete-status").textContent,
    /данные удалены/,
  );
});

test("expired deletion token requires a new SMS verification before retry", async () => {
  const calls = [];
  const responses = [
    jsonResponse(202, { status: "code_requested" }),
    jsonResponse(200, { access_token: "expired-test-token" }),
    jsonResponse(401, { error: "session expired" }),
  ];
  const elements = createPage(async (url, options) => {
    calls.push({ url, options });
    return responses.shift();
  });

  elements.get("phone").value = "+996700000000";
  await submit(elements.get("phone-form"));
  elements.get("code").value = "001234";
  await submit(elements.get("code-form"));
  elements.get("confirm-delete").checked = true;
  elements.get("confirm-delete").listeners.get("change")();
  await elements.get("delete-account").listeners.get("click")();

  assert.equal(elements.get("confirm-section").hidden, true);
  assert.equal(elements.get("confirm-delete").checked, false);
  assert.equal(elements.get("phone-form").hidden, false);
  assert.equal(elements.get("code-form").hidden, false);
  assert.match(
    elements.get("account-delete-status").textContent,
    /Сессия истекла/,
  );

  elements.get("confirm-delete").checked = true;
  elements.get("confirm-delete").listeners.get("change")();
  await elements.get("delete-account").listeners.get("click")();
  assert.equal(
    calls.length,
    3,
    "retry must not reuse the expired bearer token",
  );
});
