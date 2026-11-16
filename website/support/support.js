const supportForm = document.querySelector("[data-support-form]");

if (supportForm instanceof HTMLFormElement) {
  supportForm.addEventListener("submit", (event) => {
    event.preventDefault();
    if (!supportForm.reportValidity()) return;

    const formData = new FormData(supportForm);
    const subject = String(formData.get("subject") ?? "").trim();
    const description = String(formData.get("description") ?? "").trim();
    const query = `subject=${encodeURIComponent(`STROY — ${subject}`)}&body=${encodeURIComponent(description)}`;
    window.location.href = `mailto:nursultankosoev2@gmail.com?${query}`;
  });
}
