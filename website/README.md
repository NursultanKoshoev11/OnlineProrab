# STROY website

Адаптивный сайт STROY на HTML, Tailwind CSS 4 и JavaScript.
Все изображения и скомпилированные стили локальные; CDN и браузерный
компилятор Tailwind не используются.

## Локальный запуск

Готовый `styles.css` включён в проект. Для просмотра достаточно:

```bash
python3 -m http.server 8090 --bind 127.0.0.1
```

Открыть: <http://localhost:8090>.

## Разработка стилей

Требуется Node.js 20 или новее.

```bash
npm ci
npm run dev
```

`npm run dev` следит за изменениями в HTML, JavaScript и исходных стилях,
пересобирая `styles.css`. HTTP-сервер запускается отдельно командой выше.

```bash
npm run build # Минифицированная production-сборка CSS
npm run check # Синтаксис JavaScript и форматирование исходников
```

После изменения классов или исходных стилей выполните `npm run build`.
`styles.css` — генерируемый файл, не редактируйте его вручную.

## Структура и Tailwind

- `src/styles.css` — вход Tailwind, явные `@source` и токены `@theme`.
- `src/base.css` — общий минимальный сброс стилей.
- `src/components.css` — компоненты и адаптивные состояния через `@apply`;
  обычный CSS оставлен для иллюстраций и сложных эффектов.
- `src/legal.css` — компоненты страниц документов и поддержки через `@apply`.
- `index.html` — главная страница, utility-классы сеток, интерактивное демо и FAQ.
- `script.js` — мобильное меню, доступные вкладки, фильтр объектов и демо-расходы.
- `privacy/`, `terms/`, `support/`, `account-deletion/` — документы,
  поддержка и самостоятельное удаление аккаунта.
- `account-deletion.js` — подтверждение номера по SMS и запрос удаления аккаунта.
- `account-deletion.css` — стили публичной страницы удаления аккаунта.
- `assets/` — локальные изображения и логотипы.
- `styles.css` — единый скомпилированный CSS для всех страниц.

Цвета доступны как `bg-paper`, `text-ink`, `bg-lime`, `text-muted` и другие
utility-классы. Варианты `compact:`, `tablet:` и `mobile:` соответствуют
ширинам до 1150, 900 и 700 px включительно. Повторяющиеся компоненты используют `@apply`; небольшие сетки
и простые элементы используют utilities прямо в HTML. Существующий сброс
сохранён вместо Preflight, чтобы не менять списки документов и нативный диалог.
Служебные semantic-классы, используемые JavaScript, остаются стабильными.

## Docker

```bash
docker compose up --build -d
```

Открыть: <http://localhost:8090>. Остановить: `docker compose down`.

На этапе сборки Node.js устанавливает зависимости из lockfile и компилирует
Tailwind. Финальный nginx-образ содержит только статические файлы сайта,
без Node.js, `node_modules`, исходников стилей и проверочных артефактов.
Контейнер работает как UID 101 с read-only root filesystem; запись разрешена
только во временную файловую систему `/tmp`. Compose публикует сайт на
`127.0.0.1:8090`, чтобы Caddy на том же хосте мог проксировать запросы,
не открывая порт контейнера напрямую в сеть. Docker JSON logs ограничены пятью
файлами по 10 МБ для каждого контейнера.

## Production deploy через GitHub Actions и SSH

`Website Production Deploy` запускается после успешного `CI`, запущенного
push в `main` или вручную из `main`. Workflow собирает проверенный revision
в образ, передаёт его и Compose-конфигурацию на Caddy-хост по SSH, ждёт
healthcheck контейнера и проверяет публичные страницы и заголовки по HTTPS.
Перед SSH-подключением workflow сверяет SHA с текущим `main` и пропускает
запоздавший запуск CI. Workflow не меняет Caddy. Публичная проверка
подтверждает, что proxy отдаёт страницы и security headers. Порт `8090`
остаётся только на loopback.

Создайте GitHub Environment `production-website` и разрешите deployment только
из `main`. Добавьте Variables:

- `WEBSITE_DEPLOY_HOST` — DNS-имя SSH-сервера.
- `WEBSITE_DEPLOY_USER` — отдельный пользователь развёртывания.
- `WEBSITE_DEPLOY_PATH` — выделенный абсолютный каталог, например
  `/opt/stroy-website`.

Добавьте Environment Secrets:

- `WEBSITE_DEPLOY_SSH_KEY` — отдельный SSH private key пользователя deploy.
- `WEBSITE_DEPLOY_KNOWN_HOSTS` — проверенная запись `known_hosts` для сервера.

На сервере установите Docker Engine и Docker Compose v2 с поддержкой `up
--wait`, добавьте deploy-пользователя в группу Docker, создайте каталог deploy
с его владельцем и проверьте, что Caddy уже проксирует на `127.0.0.1:8090`.
Для существующего контейнера `stroy-website` перед первым запуском сохраните
текущий production Compose-файл как baseline и установите ссылку `current`:

```bash
DEPLOY_PATH=/opt/stroy-website
install -d -m 0750 "$DEPLOY_PATH/releases/baseline/website"
cp /path/to/active/website/docker-compose.yml \
  "$DEPLOY_PATH/releases/baseline/website/docker-compose.yml"
ln -s "$DEPLOY_PATH/releases/baseline" "$DEPLOY_PATH/current"
```

Задайте здесь тот же путь, что и в `WEBSITE_DEPLOY_PATH`. Вместо
`/path/to/active` укажите путь к конфигурации, с которой запущен текущий
контейнер. Deploy откажется заменять существующий контейнер, если такой
baseline не найден, чтобы не терять возможность отката.
Проверьте, что baseline публикует старый порт сайта только на loopback
(`127.0.0.1:8090:80`). Если исходный Compose публикует его на всех интерфейсах,
исправьте привязку в копии до создания ссылки `current`. При откате workflow
добавляет к baseline явное имя предыдущего Docker image.
Проверьте fingerprint SSH host key по независимому каналу перед сохранением
`known_hosts`; workflow не использует `ssh-keyscan` на лету и не отключает
проверку ключа. Не открывайте порт `8090` во внешнюю сеть.

После слияния изменений в `main` дождитесь зелёного `CI`: затем workflow
автоматически развернёт проверенный revision. Если контейнер не пройдёт
healthcheck, скрипт вернёт предыдущий Docker image. После запуска workflow
проверит публичные `/` и `/account-deletion/`, CSP, Permissions-Policy и HSTS.
Если публичная проверка завершится ошибкой, проверьте Caddy и DNS вместе с
логами контейнера:

```bash
docker compose -p website -f /opt/stroy-website/current/website/docker-compose.yml logs --tail=200 stroy-website
```

История Compose-файлов хранится в `WEBSITE_DEPLOY_PATH/releases/<commit>` для
восстановления конфигурации. Удалять портовую публикацию или ослаблять
host-key checking нельзя.

## Демо

Демо не подключено к API: изменения существуют только до обновления страницы.
Добавление расхода обновляет сумму объекта, общий итог и отчёт. CSV-экспорт
содержит актуальные демо-данные, UTF-8 BOM и защиту текстовых полей от формул.

Вкладки поддерживают стрелки, Home и End. На мобильных экранах используются
горизонтальные вкладки, на широких — вертикальные. Учитывается настройка
`prefers-reduced-motion`.
