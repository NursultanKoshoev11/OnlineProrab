const supportForm = document.querySelector("[data-support-form]");

if (supportForm instanceof HTMLFormElement) {
  const supportStatus = supportForm.querySelector("[data-support-status]");
  const submitButton = supportForm.querySelector('button[type="submit"]');
  const submitLabel = supportForm.querySelector("[data-submit-label]");

  supportForm.addEventListener("submit", (event) => {
    event.preventDefault();
    if (!supportForm.reportValidity()) return;

    const formData = new FormData(supportForm);
    const subject = String(formData.get("subject") ?? "").trim();
    const description = String(formData.get("description") ?? "").trim();

    if (!(submitButton instanceof HTMLButtonElement)) return;
    if (!(submitLabel instanceof HTMLElement)) return;

    submitButton.disabled = true;
    submitButton.setAttribute("aria-busy", "true");
    submitLabel.textContent = "Отправляем…";
    if (supportStatus instanceof HTMLElement) {
      supportStatus.textContent = "";
      supportStatus.className = "support-form-status";
    }

    fetch("https://api.stroy.com.kg/api/v1/support/public-tickets", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ subject, message: description }),
    })
      .then(async (response) => {
        const result = await response.json().catch(() => ({}));
        if (!response.ok || result.status !== "sent") {
          throw new Error(
            response.status === 429
              ? "rate-limited"
              : response.status === 503
                ? "unavailable"
                : "send-failed",
          );
        }
        supportForm.reset();
        if (supportStatus instanceof HTMLElement) {
          supportStatus.textContent = "Обращение отправлено в поддержку STROY.";
          supportStatus.classList.add("is-success");
        }
      })
      .catch((error) => {
        if (supportStatus instanceof HTMLElement) {
          if (error instanceof Error && error.message === "rate-limited") {
            supportStatus.textContent =
              "Вы отправили несколько обращений. Попробуйте позже.";
          } else if (error instanceof Error && error.message === "unavailable") {
            supportStatus.textContent =
              "Форма поддержки временно недоступна. Попробуйте позже.";
          } else if (error instanceof TypeError) {
            supportStatus.textContent =
              "Не удалось связаться с сервером. Проверьте подключение и попробуйте ещё раз.";
          } else {
            supportStatus.textContent =
              "Не удалось отправить сообщение. Попробуйте позже.";
          }
          supportStatus.classList.add("is-error");
        }
      })
      .finally(() => {
        submitButton.disabled = false;
        submitButton.removeAttribute("aria-busy");
        submitLabel.textContent = "Отправить сообщение";
      });
  });
}
