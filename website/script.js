"use strict";

// Navigation uses a single source of truth for visibility and accessibility.
const menuButton = document.querySelector(".menu-button");
const mobileNav = document.querySelector("#mobile-nav");
function setMenu(open) {
  mobileNav.hidden = !open;
  menuButton.setAttribute("aria-expanded", String(open));
  menuButton.setAttribute("aria-label", open ? "Закрыть меню" : "Открыть меню");
}
menuButton.addEventListener("click", () => setMenu(mobileNav.hidden));
mobileNav.addEventListener("click", (event) => {
  if (event.target.closest("a")) setMenu(false);
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && !mobileNav.hidden) {
    setMenu(false);
    menuButton.focus();
  }
});
const mobileBreakpoint = window.matchMedia("(max-width: 700px)");
mobileBreakpoint.addEventListener("change", () => setMenu(false));

// The demo stays local to this page. Refreshing restores the example data.
const tabs = [...document.querySelectorAll("[data-tab]")];
const panels = [...document.querySelectorAll('[role="tabpanel"]')];
const tablist = document.querySelector(".demo-tabs");
function syncTabOrientation() {
  tablist.setAttribute(
    "aria-orientation",
    mobileBreakpoint.matches ? "horizontal" : "vertical",
  );
}
syncTabOrientation();
mobileBreakpoint.addEventListener("change", syncTabOrientation);
function selectTab(name, focus = false) {
  const selected = tabs.find((tab) => tab.dataset.tab === name);
  if (!selected) return;
  tabs.forEach((tab) => {
    const active = tab === selected;
    tab.setAttribute("aria-selected", String(active));
    tab.tabIndex = active ? 0 : -1;
  });
  panels.forEach((panel) => {
    panel.hidden = panel.id !== `panel-${name}`;
  });
  document.querySelector("#breadcrumb").textContent =
    selected.querySelector("span").textContent;
  if (focus) selected.focus();
}
tabs.forEach((tab, index) => {
  tab.addEventListener("click", () => selectTab(tab.dataset.tab));
  tab.addEventListener("keydown", (event) => {
    const nextKeys = mobileBreakpoint.matches ? ["ArrowRight"] : ["ArrowDown"];
    const previousKeys = mobileBreakpoint.matches ? ["ArrowLeft"] : ["ArrowUp"];
    let next;
    if (nextKeys.includes(event.key)) next = (index + 1) % tabs.length;
    if (previousKeys.includes(event.key))
      next = (index - 1 + tabs.length) % tabs.length;
    if (event.key === "Home") next = 0;
    if (event.key === "End") next = tabs.length - 1;
    if (next !== undefined) {
      event.preventDefault();
      selectTab(tabs[next].dataset.tab, true);
    }
  });
});
document.querySelectorAll("[data-open-demo]").forEach((link) => {
  link.addEventListener("click", () => selectTab(link.dataset.openDemo));
});
document
  .querySelector("#project-filter")
  .addEventListener("change", (event) => {
    const filter = event.target.value;
    document.querySelectorAll("[data-status]").forEach((project) => {
      project.hidden = filter !== "all" && project.dataset.status !== filter;
    });
  });

const expenses = [
  { name: "Бетон М300", category: "Материалы", amount: 248000 },
  { name: "Арматура А500", category: "Материалы", amount: 186400 },
  { name: "Аренда техники", category: "Техника", amount: 320000 },
  { name: "Монтажные работы", category: "Работы", amount: 494100 },
];
const money = new Intl.NumberFormat("ru-RU", { maximumFractionDigits: 2 });
const total = () =>
  expenses.reduce((sum, expense) => sum + Math.round(expense.amount * 100), 0) /
  100;
function renderExpenses() {
  const rows = expenses.map((expense) => {
    const row = document.createElement("tr");
    [expense.name, expense.category, money.format(expense.amount)].forEach(
      (value) => {
        const cell = document.createElement("td");
        cell.textContent = value;
        row.append(cell);
      },
    );
    return row;
  });
  document.querySelector("#expense-rows").replaceChildren(...rows);
  document.querySelectorAll("[data-expense-total]").forEach((element) => {
    element.textContent = `${money.format(total())} сом`;
  });
  document.querySelector("#project-expense-total").textContent =
    `${money.format(total())} сом`;
  const overallTotal = document.querySelector(
    ".app-stats > div:nth-child(2) strong",
  );
  overallTotal.replaceChildren(
    document.createTextNode(`${money.format(11231500 + total())} `),
  );
  const unit = document.createElement("small");
  unit.textContent = "сом";
  overallTotal.append(unit);
  const categories = ["Материалы", "Работы", "Техника"].map((category) => {
    const row = document.createElement("div");
    const label = document.createElement("span");
    const value = document.createElement("span");
    label.textContent = category;
    value.textContent = `${money.format(expenses.filter((item) => item.category === category).reduce((sum, item) => sum + Math.round(item.amount * 100), 0) / 100)} сом`;
    row.append(label, value);
    return row;
  });
  document.querySelector("#report-categories").replaceChildren(...categories);
}
renderExpenses();

let toastTimer;
function notify(message) {
  const toast = document.querySelector("#toast");
  clearTimeout(toastTimer);
  toast.textContent = message;
  toast.classList.add("is-visible");
  toastTimer = setTimeout(() => toast.classList.remove("is-visible"), 4000);
}
const dialog = document.querySelector("#expense-dialog");
const form = document.querySelector("#expense-form");
document
  .querySelector("#add-expense")
  .addEventListener("click", () => dialog.showModal());
dialog
  .querySelector(".dialog-close")
  .addEventListener("click", () => dialog.close());
dialog.addEventListener("click", (event) => {
  const bounds = dialog.getBoundingClientRect();
  if (
    event.target === dialog &&
    (event.clientX < bounds.left ||
      event.clientX > bounds.right ||
      event.clientY < bounds.top ||
      event.clientY > bounds.bottom)
  )
    dialog.close();
});
form.addEventListener("submit", (event) => {
  event.preventDefault();
  const fields = new FormData(form);
  const name = String(fields.get("name")).trim();
  const amount = Number(fields.get("amount"));
  if (!name) {
    form.elements.name.setCustomValidity("Укажите название расхода.");
    form.elements.name.reportValidity();
    return;
  }
  if (!Number.isFinite(amount) || amount < 1 || amount > 100000000) return;
  expenses.unshift({
    name,
    category: String(fields.get("category")),
    amount: Math.round(amount * 100) / 100,
  });
  renderExpenses();
  dialog.close();
  form.reset();
  notify("Расход добавлен. Итоги и отчёт обновлены.");
});
form.elements.name.addEventListener("input", () =>
  form.elements.name.setCustomValidity(""),
);

function csvCell(value) {
  // Quoting alone does not prevent spreadsheet formula interpretation.
  const text = String(value);
  const safe = /^[=+\-@\t\r\n]/.test(text) ? `'${text}` : text;
  return `"${safe.replaceAll('"', '""')}"`;
}
document.querySelector("#download-report").addEventListener("click", () => {
  const rows = [
    ["STROY — Демонстрационный отчёт", "Дом у озера", ""],
    ["Название", "Категория", "Сумма (сом)"],
    ...expenses.map((expense) => [
      expense.name,
      expense.category,
      expense.amount.toFixed(2).replace(".", ","),
    ]),
    ["Итого", "", total().toFixed(2).replace(".", ",")],
  ];
  const csv =
    "\uFEFF" + rows.map((row) => row.map(csvCell).join(";")).join("\r\n");
  const url = URL.createObjectURL(
    new Blob([csv], { type: "text/csv;charset=utf-8;" }),
  );
  const link = document.createElement("a");
  link.href = url;
  link.download = "stroy-demo-report.csv";
  document.body.append(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
  notify("Демо-отчёт скачан в формате CSV.");
});
