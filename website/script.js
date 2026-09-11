const menuButton = document.querySelector('.menu-button');
const mobileNav = document.querySelector('.mobile-nav');

menuButton?.addEventListener('click', () => {
  const isOpen = mobileNav.classList.toggle('open');
  menuButton.setAttribute('aria-expanded', String(isOpen));
  mobileNav.setAttribute('aria-hidden', String(!isOpen));
});

mobileNav?.querySelectorAll('a').forEach((link) => {
  link.addEventListener('click', () => {
    mobileNav.classList.remove('open');
    menuButton?.setAttribute('aria-expanded', 'false');
    mobileNav.setAttribute('aria-hidden', 'true');
  });
});

const demoContent = {
  object: {
    number: '01',
    title: 'Объект — это<br /><em>единая картина.</em>',
    text: 'Фото, ключевые показатели и текущий статус собраны на одном экране — без поиска по чатам и заметкам.',
    points: ['✓ Фото объекта', '✓ Общая сумма', '✓ Статус работы'],
  },
  expenses: {
    number: '02',
    title: 'Каждый расход<br /><em>под контролем.</em>',
    text: 'Добавляйте покупку за несколько секунд, прикладывайте чек и сразу видьте, как меняется бюджет объекта.',
    points: ['✓ Название и сумма', '✓ Фото чека', '✓ Дата и описание'],
  },
  report: {
    number: '03',
    title: 'Отчёт готов<br /><em>для решения.</em>',
    text: 'Общий итог, расходы и PDF‑предпросмотр — в одном понятном экране для владельца, клиента и команды.',
    points: ['✓ Общий итог', '✓ PDF‑предпросмотр', '✓ Поделиться отчётом'],
  },
};

const setDemo = (name) => {
  const item = demoContent[name];
  if (!item) return;
  document.querySelectorAll('.demo-tab').forEach((tab) => tab.classList.toggle('active', tab.dataset.demo === name));
  document.querySelector('#demoNumber').textContent = item.number;
  document.querySelector('#demoTitle').innerHTML = item.title;
  document.querySelector('#demoText').textContent = item.text;
  document.querySelector('#demoPoints').innerHTML = item.points.map((point) => `<span>${point}</span>`).join('');
  const visual = document.querySelector('#demoVisual');
  visual.dataset.mode = name;
};

document.querySelectorAll('.demo-tab').forEach((tab) => tab.addEventListener('click', () => setDemo(tab.dataset.demo)));

const flowItems = document.querySelectorAll('.flow-item');
flowItems.forEach((item) => item.addEventListener('mouseenter', () => {
  flowItems.forEach((other) => other.classList.remove('active'));
  item.classList.add('active');
}));

const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const finePointer = window.matchMedia('(pointer: fine)').matches;

if (!reduceMotion && finePointer) {
  document.querySelectorAll('.browser-screen, .feature-card').forEach((card) => {
    const surface = card.matches('.browser-screen') ? card.querySelector('.browser-window') : card;
    if (!surface) return;

    card.addEventListener('pointermove', (event) => {
      const rect = card.getBoundingClientRect();
      const x = (event.clientX - rect.left) / rect.width - 0.5;
      const y = (event.clientY - rect.top) / rect.height - 0.5;
      const tiltX = (-y * 3.2).toFixed(2);
      const tiltY = (x * 3.2).toFixed(2);
      surface.style.transform = `perspective(1100px) rotateX(${tiltX}deg) rotateY(${tiltY}deg) translateY(-7px)`;
    });

    card.addEventListener('pointerleave', () => {
      surface.style.transform = '';
    });
  });
}

const revealObserver = 'IntersectionObserver' in window
  ? new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) entry.target.classList.add('is-visible');
      });
    }, { threshold: 0.16 })
  : null;

revealObserver?.observe(document.querySelector('.screen-showcase-grid'));
