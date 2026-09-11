# STROY website

Лендинг для приложения STROY: объекты, расходы, AI-поиск, отчёты и командная работа.

## Запуск через Docker

Из папки `website`:

```bash
docker compose up --build -d
```

Открыть: <http://localhost:8090>

Остановить:

```bash
docker compose down
```

Сайт не требует Node.js, базы данных или интернет-соединения после сборки контейнера.
