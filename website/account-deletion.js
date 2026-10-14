"use strict";

const API_BASE_URL = "https://api.stroy.com.kg";
const phoneForm = document.querySelector("#phone-form");
const codeForm = document.querySelector("#code-form");
const phoneInput = document.querySelector("#phone");
const codeInput = document.querySelector("#code");
const requestButton = document.querySelector("#request-code");
const verifyButton = document.querySelector("#verify-code");
const resendButton = document.querySelector("#resend-code");
const confirmSection = document.querySelector("#confirm-section");
const confirmCheckbox = document.querySelector("#confirm-delete");
const deleteButton = document.querySelector("#delete-account");
const verifiedPhone = document.querySelector("#verified-phone");
const statusElement = document.querySelector("#account-delete-status");

let accessToken = "";

function normalizedPhone() {
  return phoneInput.value.trim().replace(/[^0-9+]/g, "");
}

function setStatus(message, isError = false) {
  statusElement.textContent = message;
  statusElement.dataset.state = isError ? "error" : "success";
}

async function postJSON(path, body) {
  const response = await fetch(`${API_BASE_URL}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    cache: "no-store",
    credentials: "omit",
    referrerPolicy: "no-referrer",
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(payload.error || "Не удалось выполнить запрос.");
    error.status = response.status;
    throw error;
  }
  return payload;
}

function requestErrorMessage(error) {
  if (error.status === 429) {
    return "Слишком много запросов. Подождите и попробуйте снова.";
  }
  if (error.status === 503 || error.status === 502) {
    return "Сервис SMS временно недоступен. Попробуйте позже или обратитесь в поддержку.";
  }
  return (
    error.message ||
    "Не удалось отправить SMS-код. Проверьте номер и попробуйте снова."
  );
}

async function requestCode() {
  const phone = normalizedPhone();
  if (!/^\+?[0-9]{9,15}$/.test(phone)) {
    setStatus(
      "Введите номер телефона в международном формате, например +996 700 000 000.",
      true,
    );
    phoneInput.focus();
    return;
  }

  phoneInput.value = phone;
  requestButton.disabled = true;
  resendButton.disabled = true;
  setStatus("Отправляем SMS-код…");
  try {
    await postJSON("/api/v1/auth/sms/request", { phone });
    codeForm.hidden = false;
    codeInput.value = "";
    codeInput.focus();
    setStatus("Если номер введён верно, SMS-код скоро придёт.");
  } catch (error) {
    setStatus(requestErrorMessage(error), true);
  } finally {
    requestButton.disabled = false;
    resendButton.disabled = false;
  }
}

phoneForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  await requestCode();
});

resendButton.addEventListener("click", requestCode);

codeInput.addEventListener("input", () => {
  codeInput.value = codeInput.value.replace(/\D/g, "").slice(0, 6);
});

codeForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  verifyButton.disabled = true;
  setStatus("Проверяем код…");
  try {
    const payload = await postJSON("/api/v1/auth/sms/verify", {
      phone: normalizedPhone(),
      code: codeInput.value,
    });
    if (!payload.access_token) {
      throw new Error("Не удалось подтвердить номер. Запросите новый код.");
    }
    accessToken = payload.access_token;
    phoneForm.hidden = true;
    codeForm.hidden = true;
    codeInput.value = "";
    verifiedPhone.textContent = normalizedPhone();
    confirmSection.hidden = false;
    confirmSection.scrollIntoView({ behavior: "smooth", block: "center" });
    setStatus(
      "Номер подтверждён. Проверьте предупреждение и подтвердите удаление.",
    );
  } catch (error) {
    setStatus(requestErrorMessage(error), true);
  } finally {
    verifyButton.disabled = false;
  }
});

confirmCheckbox.addEventListener("change", () => {
  deleteButton.disabled = !confirmCheckbox.checked;
});

deleteButton.addEventListener("click", async () => {
  if (!accessToken || !confirmCheckbox.checked) return;

  deleteButton.disabled = true;
  verifyButton.disabled = true;
  requestButton.disabled = true;
  setStatus("Удаляем аккаунт и связанные данные…");
  try {
    const response = await fetch(`${API_BASE_URL}/api/v1/account`, {
      method: "DELETE",
      headers: { Authorization: `Bearer ${accessToken}` },
      cache: "no-store",
      credentials: "omit",
      referrerPolicy: "no-referrer",
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      const error = new Error(
        payload.error || "Не удалось удалить аккаунт. Обратитесь в поддержку.",
      );
      error.status = response.status;
      throw error;
    }

    accessToken = "";
    phoneForm.hidden = true;
    codeForm.hidden = true;
    phoneInput.value = "";
    confirmSection.hidden = true;
    verifiedPhone.textContent = "";
    confirmCheckbox.checked = false;
    setStatus("Аккаунт и связанные с ним данные удалены.");
  } catch (error) {
    if (error.status === 401) {
      accessToken = "";
      confirmSection.hidden = true;
      confirmCheckbox.checked = false;
      deleteButton.disabled = true;
      phoneForm.hidden = false;
      codeForm.hidden = false;
      codeInput.value = "";
      setStatus(
        "Сессия истекла. Отправьте новый SMS-код и подтвердите номер снова.",
        true,
      );
    } else {
      deleteButton.disabled = false;
      setStatus(
        error.message ||
          "Не удалось удалить аккаунт. Попробуйте снова или обратитесь в поддержку.",
        true,
      );
    }
  } finally {
    requestButton.disabled = false;
    verifyButton.disabled = false;
  }
});
