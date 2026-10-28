(() => {
  const returnParams = new URLSearchParams(window.location.search);
  const apiBase = returnParams.get("stage") === "1"
    ? `${window.location.origin}/staging-api`
    : "https://api.stroy.com.kg";
  const tokenKey = "stroy.billing.session";
  const elements = {
    notice: document.querySelector("#notice"),
    loginPanel: document.querySelector("#login-panel"),
    phoneForm: document.querySelector("#phone-form"),
    codeForm: document.querySelector("#code-form"),
    phone: document.querySelector("#phone"),
    code: document.querySelector("#code"),
    changePhone: document.querySelector("#change-phone"),
    accountPanel: document.querySelector("#account-panel"),
    accountTitle: document.querySelector("#account-title"),
    currentSubscription: document.querySelector("#current-subscription"),
    plans: document.querySelector("#plans"),
    checkoutPrice: document.querySelector("#checkout-price"),
    payButton: document.querySelector("#pay-button"),
    paymentOptions: document.querySelector("#payment-options"),
    obankAppLink: document.querySelector("#obank-app-link"),
    webPayLink: document.querySelector("#web-pay-link"),
    logout: document.querySelector("#logout"),
    billingNavCurrent: document.querySelector("#billing-nav-current"),
    billingNavCurrentMobile: document.querySelector("#billing-nav-current-mobile"),
    billingNavAction: document.querySelector("#billing-nav-action"),
    menuButton: document.querySelector(".menu-button"),
    mobileNav: document.querySelector("#mobile-nav"),
    yearlyPeriod: document.querySelector('input[name="period"][value="year"]'),
  };

  let selectedPlan = "standard";
  let billingPeriod = "month";
  let plans = [];
  let accessToken = sessionStorage.getItem(tokenKey) || "";
  let pollingTimer = null;
  let activeCheckoutID = sessionStorage.getItem("stroy.billing.order_id") || "";
  let checkoutAllowed = true;

  function updateNavigationTargets() {
    const destination = accessToken ? "#account-panel" : "#login-panel";
    if (elements.billingNavCurrent) elements.billingNavCurrent.href = destination;
    if (elements.billingNavCurrentMobile) elements.billingNavCurrentMobile.href = destination;
    if (elements.billingNavAction) {
      elements.billingNavAction.href = destination;
      elements.billingNavAction.textContent = accessToken ? "Мой аккаунт" : "Войти";
    }
  }

  function setMobileMenuOpen(open) {
    if (!elements.mobileNav || !elements.menuButton) return;
    elements.mobileNav.hidden = !open;
    elements.menuButton.setAttribute("aria-expanded", String(open));
    elements.menuButton.setAttribute("aria-label", open ? "Закрыть меню" : "Открыть меню");
  }

  elements.menuButton?.addEventListener("click", () => {
    setMobileMenuOpen(elements.mobileNav.hidden);
  });
  elements.mobileNav?.addEventListener("click", (event) => {
    if (event.target instanceof Element && event.target.closest("a")) {
      setMobileMenuOpen(false);
    }
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") setMobileMenuOpen(false);
  });
  updateNavigationTargets();

  function showNotice(message, kind = "info") {
    elements.notice.textContent = message;
    elements.notice.dataset.kind = kind;
    elements.notice.hidden = !message;
  }

  async function request(path, options = {}) {
    const headers = new Headers(options.headers || {});
    headers.set("Accept", "application/json");
    if (options.body) headers.set("Content-Type", "application/json");
    if (accessToken) headers.set("Authorization", `Bearer ${accessToken}`);
    const response = await fetch(`${apiBase}${path}`, {
      ...options,
      headers,
      credentials: "omit",
      redirect: "error",
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      if (response.status === 401) clearSession();
      throw new Error(payload.error || "Не удалось связаться с STROY. Попробуйте ещё раз.");
    }
    return payload;
  }

  function clearSession() {
    accessToken = "";
    updateNavigationTargets();
    checkoutAllowed = true;
    if (elements.yearlyPeriod) {
      elements.yearlyPeriod.closest("label")?.removeAttribute("hidden");
      elements.yearlyPeriod.checked = false;
    }
    billingPeriod = "month";
    sessionStorage.removeItem(tokenKey);
    elements.accountPanel.hidden = true;
    elements.loginPanel.hidden = false;
    elements.phoneForm.hidden = false;
    elements.codeForm.hidden = true;
    elements.phone.disabled = false;
    elements.paymentOptions.hidden = true;
    elements.payButton.hidden = false;
    sessionStorage.removeItem("stroy.billing.order_id");
    activeCheckoutID = "";
    if (pollingTimer) window.clearTimeout(pollingTimer);
  }

  function formatMoney(value) {
    return `${new Intl.NumberFormat("ru-RU").format(value)} сом`;
  }

  function periodName(value) {
    return value === "year" ? "за год" : "за месяц";
  }

  async function requestCode(event) {
    event.preventDefault();
    const phone = elements.phone.value.trim();
    const button = elements.phoneForm.querySelector("button[type=submit]");
    button.disabled = true;
    showNotice("Отправляем код…");
    try {
      const result = await request("/api/v1/auth/sms/request", {
        method: "POST",
        body: JSON.stringify({ phone }),
      });
      elements.phone.disabled = true;
      elements.phoneForm.hidden = true;
      elements.codeForm.hidden = false;
      elements.code.focus();
      showNotice(
        result.dev_code
          ? `Локальный код: ${result.dev_code}`
          : "Код отправлен. Он действует 5 минут.",
      );
    } catch (error) {
      showNotice(error.message, "error");
    } finally {
      button.disabled = false;
    }
  }

  async function verifyCode(event) {
    event.preventDefault();
    const button = elements.codeForm.querySelector("button[type=submit]");
    button.disabled = true;
    showNotice("Проверяем код…");
    try {
      const result = await request("/api/v1/auth/sms/verify", {
        method: "POST",
        body: JSON.stringify({ phone: elements.phone.value.trim(), code: elements.code.value.trim() }),
      });
      accessToken = result.access_token || "";
      if (!accessToken) throw new Error("Сервер не выдал токен входа. Попробуйте ещё раз.");
      sessionStorage.setItem(tokenKey, accessToken);
      updateNavigationTargets();
      await loadAccount();
    } catch (error) {
      showNotice(error.message, "error");
    } finally {
      button.disabled = false;
    }
  }

  async function loadAccount() {
    try {
      const [subscription, response] = await Promise.all([
        request("/api/v1/subscriptions/status"),
        request("/api/v1/subscriptions/plans"),
      ]);
      const sandboxTestMode = response.sandbox_test_mode === true;
      checkoutAllowed = response.checkout_allowed !== false;
      plans = Array.isArray(response.plans) ? response.plans.filter((plan) => plan.id !== "trial") : [];
      elements.loginPanel.hidden = true;
      elements.accountPanel.hidden = false;
      elements.accountTitle.textContent = `Аккаунт ${elements.phone.value.trim()}`;
      const endsAt = subscription.ends_at
        ? new Intl.DateTimeFormat("ru-RU", { dateStyle: "long" }).format(new Date(subscription.ends_at))
        : "";
      elements.currentSubscription.textContent =
        `Текущий тариф: ${planName(subscription.plan)}. ` +
        (endsAt ? `Действует до ${endsAt}.` : "");
      if (sandboxTestMode && checkoutAllowed && elements.yearlyPeriod) {
        billingPeriod = "month";
        elements.yearlyPeriod.checked = false;
        elements.yearlyPeriod.closest("label")?.setAttribute("hidden", "");
      }
      renderPlans();
      showNotice(sandboxTestMode
        ? checkoutAllowed
          ? `Тестовая оплата Sandbox: ${formatMoney(response.sandbox_test_price_kgs)} за месяц.`
          : "Тестовая оплата временно доступна только назначенному тестовому аккаунту."
        : "Вход выполнен. Выберите тариф и период оплаты.", sandboxTestMode && !checkoutAllowed ? "error" : "info");
      await restoreCheckoutFromReturn();
    } catch (error) {
      showNotice(error.message, "error");
    }
  }

  function planName(id) {
    return plans.find((plan) => plan.id === id)?.name || (id === "trial" ? "Пробный период" : id);
  }

  function planPrice(plan) {
    return billingPeriod === "year" ? plan.annual_price_kgs : plan.price_kgs;
  }

  function renderPlans() {
    elements.plans.replaceChildren();
    for (const plan of plans) {
      const card = document.createElement("button");
      card.type = "button";
      card.className = "plan-card";
      card.setAttribute("aria-pressed", String(plan.id === selectedPlan));
      const title = document.createElement("strong");
      title.textContent = plan.name;
      const details = document.createElement("span");
      details.className = "plan-details";
      details.textContent = `До ${plan.max_projects} объектов · до ${plan.max_invited_members} участников на объект`;
      const price = document.createElement("span");
      price.className = "plan-price";
      price.textContent = `${formatMoney(planPrice(plan))} / ${billingPeriod === "year" ? "год" : "мес."}`;
      card.append(title, details, price);
      if (billingPeriod === "year" && plan.annual_discount_percent > 0) {
        const discount = document.createElement("span");
        discount.className = "plan-discount";
        discount.textContent = `Скидка ${plan.annual_discount_percent}%`;
        card.append(discount);
      }
      card.addEventListener("click", () => {
        selectedPlan = plan.id;
        renderPlans();
      });
      elements.plans.append(card);
    }
    const selected = plans.find((plan) => plan.id === selectedPlan);
    elements.checkoutPrice.textContent = selected ? formatMoney(planPrice(selected)) : "—";
    elements.payButton.disabled = !selected || !checkoutAllowed;
  }

  async function startCheckout() {
    const selected = plans.find((plan) => plan.id === selectedPlan);
    if (!selected || !checkoutAllowed) return;
    elements.payButton.disabled = true;
    showNotice("Готовим защищённый счёт O!Dengi…");
    try {
      const checkout = await request("/api/v1/subscriptions/checkout", {
        method: "POST",
        body: JSON.stringify({
          plan_id: selectedPlan,
          billing_period: billingPeriod,
          idempotency_key: createIdempotencyKey(),
        }),
      });
      if (!isValidBankURL(checkout.payment_url)) {
        throw new Error("Банк вернул некорректную ссылку для оплаты.");
      }
      activeCheckoutID = checkout.order_id || "";
      if (activeCheckoutID) sessionStorage.setItem("stroy.billing.order_id", activeCheckoutID);
      if (isMobileBrowser() && isValidBankAppURL(checkout.app_link)) {
        elements.obankAppLink.href = checkout.app_link;
        elements.webPayLink.href = checkout.payment_url;
        elements.paymentOptions.hidden = false;
        elements.payButton.hidden = true;
        showNotice("Счёт готов. Выберите O!Bank или веб-оплату.");
        if (activeCheckoutID) {
          pollingTimer = window.setTimeout(() => refreshCheckoutStatus(activeCheckoutID), 8000);
        }
        return;
      }
      window.location.assign(checkout.payment_url);
    } catch (error) {
      showNotice(error.message, "error");
      elements.payButton.disabled = false;
    }
  }

  async function restoreCheckoutFromReturn() {
    const params = new URLSearchParams(window.location.search);
    const orderID = params.get("order_id") || activeCheckoutID;
    if (!orderID) return;
    activeCheckoutID = orderID;
    sessionStorage.setItem("stroy.billing.order_id", orderID);
    showNotice("Проверяем статус платежа…");
    await refreshCheckoutStatus(orderID);
    if (pollingTimer) window.clearTimeout(pollingTimer);
    pollingTimer = window.setTimeout(() => refreshCheckoutStatus(orderID), 5000);
  }

  async function refreshCheckoutStatus(orderID) {
    try {
      const result = await request(
        `/api/v1/subscriptions/checkout?order_id=${encodeURIComponent(orderID)}`,
      );
      if (result.status === "paid") {
        showNotice("Платёж подтверждён. Тариф активирован для этого аккаунта — войдите в приложение STROY тем же номером.");
        const subscription = await request("/api/v1/subscriptions/status");
        const endsAt = subscription.ends_at
          ? new Intl.DateTimeFormat("ru-RU", { dateStyle: "long" }).format(new Date(subscription.ends_at))
          : "";
        elements.currentSubscription.textContent = `Текущий тариф: ${planName(subscription.plan)}. Действует до ${endsAt}.`;
        if (pollingTimer) window.clearTimeout(pollingTimer);
        elements.paymentOptions.hidden = true;
        elements.payButton.hidden = false;
        elements.payButton.disabled = false;
        sessionStorage.removeItem("stroy.billing.order_id");
        activeCheckoutID = "";
        return;
      }
      if (result.status === "canceled") {
        showNotice("Счёт отменён или срок его действия закончился. При необходимости создайте новый счёт.", "error");
        if (pollingTimer) window.clearTimeout(pollingTimer);
        sessionStorage.removeItem("stroy.billing.order_id");
        activeCheckoutID = "";
        elements.paymentOptions.hidden = true;
        elements.payButton.hidden = false;
        elements.payButton.disabled = false;
      } else {
        showNotice("Банк ещё обрабатывает платёж. Обновите страницу через несколько секунд, если статус не изменится.");
        pollingTimer = window.setTimeout(() => refreshCheckoutStatus(orderID), 8000);
      }
    } catch (error) {
      showNotice(error.message, "error");
    }
  }

  function createIdempotencyKey() {
    if (globalThis.crypto?.randomUUID) return crypto.randomUUID();
    const values = new Uint8Array(24);
    crypto.getRandomValues(values);
    return Array.from(values, (value) => value.toString(16).padStart(2, "0")).join("");
  }

  function isValidBankURL(value) {
    try {
      const url = new URL(value);
      return url.protocol === "https:" && (url.hostname === "dengi.kg" || url.hostname.endsWith(".dengi.kg"));
    } catch (_) {
      return false;
    }
  }

  function isValidBankAppURL(value) {
    try {
      const url = new URL(value);
      return url.protocol === "https:" &&
        url.hostname === "o.kg" &&
        !url.port &&
        !url.username &&
        !url.password &&
        url.pathname === "/l/a" &&
        url.searchParams.get("t") === "wl_unpbill" &&
        Boolean(url.searchParams.get("id")) &&
        !url.hash;
    } catch (_) {
      return false;
    }
  }

  function isMobileBrowser() {
    return navigator.userAgentData?.mobile === true ||
      /Android|iPhone|iPad|iPod/i.test(navigator.userAgent) ||
      (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
  }

  elements.phoneForm.addEventListener("submit", requestCode);
  elements.codeForm.addEventListener("submit", verifyCode);
  elements.changePhone.addEventListener("click", () => {
    elements.phone.disabled = false;
    elements.phoneForm.hidden = false;
    elements.codeForm.hidden = true;
    elements.code.value = "";
    showNotice("");
  });
  elements.logout.addEventListener("click", () => {
    clearSession();
    elements.phone.value = "";
    showNotice("Вы вышли из аккаунта.");
  });
  elements.payButton.addEventListener("click", startCheckout);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState !== "visible" || !activeCheckoutID) return;
    if (pollingTimer) window.clearTimeout(pollingTimer);
    refreshCheckoutStatus(activeCheckoutID);
  });
  document.querySelectorAll('input[name="period"]').forEach((input) => {
    input.addEventListener("change", (event) => {
      billingPeriod = event.target.value;
      renderPlans();
    });
  });

  if (accessToken) {
    elements.loginPanel.hidden = true;
    loadAccount();
  }
})();
