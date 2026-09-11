(() => {
  const apiBaseUrl = 'https://api.stroy.com.kg';
  const form = document.querySelector('#deletion-form');
  if (!form) return;

  const phoneInput = document.querySelector('#deletion-phone');
  const codeInput = document.querySelector('#deletion-code');
  const requestButton = document.querySelector('#request-code');
  const codeStep = document.querySelector('#deletion-code-step');
  const confirmButton = document.querySelector('#confirm-deletion');
  const status = document.querySelector('#deletion-status');
  let phone = '';

  const setStatus = (message, kind = '') => {
    status.textContent = message;
    status.className = `deletion-status ${kind}`.trim();
  };

  const request = async (path, options) => {
    const response = await fetch(`${apiBaseUrl}${path}`, {
      ...options,
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        ...(options?.headers || {}),
      },
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(data.error || 'Не удалось выполнить запрос.');
    return data;
  };

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    phone = phoneInput.value.trim();
    if (phone.length < 9) {
      setStatus('Введите корректный номер телефона.', 'error');
      return;
    }
    requestButton.disabled = true;
    setStatus('Отправляем код подтверждения…');
    try {
      const data = await request('/api/v1/auth/sms/request', {
        method: 'POST',
        body: JSON.stringify({phone}),
      });
      codeStep.hidden = false;
      confirmButton.hidden = false;
      requestButton.textContent = 'Отправить код повторно →';
      codeInput.focus();
      setStatus(data.dev_code ? `Код для разработки: ${data.dev_code}` : 'Код отправлен. Проверьте SMS.', 'success');
    } catch (error) {
      setStatus(error.message, 'error');
    } finally {
      requestButton.disabled = false;
    }
  });

  confirmButton.addEventListener('click', async () => {
    const code = codeInput.value.trim();
    if (!/^\d{6}$/.test(code)) {
      setStatus('Введите 6-значный код из SMS.', 'error');
      return;
    }
    confirmButton.disabled = true;
    requestButton.disabled = true;
    setStatus('Проверяем номер и удаляем данные…');
    try {
      const auth = await request('/api/v1/auth/sms/verify', {
        method: 'POST',
        body: JSON.stringify({phone, code}),
      });
      await request('/api/v1/account', {
        method: 'DELETE',
        headers: {Authorization: `Bearer ${auth.access_token}`},
      });
      form.reset();
      codeStep.hidden = true;
      confirmButton.hidden = true;
      requestButton.hidden = true;
      setStatus('Аккаунт и связанные данные удалены.', 'success');
    } catch (error) {
      setStatus(error.message, 'error');
      confirmButton.disabled = false;
      requestButton.disabled = false;
    }
  });
})();
