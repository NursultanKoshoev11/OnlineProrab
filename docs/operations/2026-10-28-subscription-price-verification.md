# Временная проверка оплаты O!Bank — 28 октября 2026

## Что изменено

Для сквозной проверки production-платежа O!Bank включён операторский параметр
`SUBSCRIPTION_PRICE_OVERRIDE_KGS=10` на API-хосте. Он применяется только к
платным тарифам (`standard` и `max`) и к обоим периодам оплаты. Пробный тариф
остаётся бесплатным.

Это изменение не меняет лимиты тарифов и не меняет данные подписчиков в базе.
Production O!Bank продолжает работать в боевом режиме (`OBANK_TEST=false`), а
не через sandbox.

## Зачем

Нужно проверить полный цикл: вход в STROY → создание счёта → открытие счёта в
O!Bank → callback банка → активация подписки. Небольшая сумма снижает стоимость
проверки, но платёж остаётся реальным production-платежом.

## Проверка после включения

- production API образ: ревизия `51399efce3c1f562ff916a2d5baffc0d01d104f1`;
- `/ready`: `200`, API сообщает `{"status":"ready"}`;
- `/health`: `200`;
- `GET /api/v1/subscriptions/plans`: платные месячные и годовые варианты отдают
  `10` KGS;
- production O!Bank URL остаётся `https://api.dengi.o.kg/api/json/json.php`;
- секреты (`OBANK_PASSWORD`, `DATABASE_URL`, JWT и ключи AWS) в Git не записываются.

## Как вернуть обычные цены

На production-хосте изменить только runtime-параметр в
`/opt/stroy-api/.env`:

```dotenv
SUBSCRIPTION_PRICE_OVERRIDE_KGS=0
```

Затем пересоздать API-контейнер через production Compose с текущими
`API_IMAGE` и `current/backend/docker-compose.prod.yml`, дождаться healthcheck и
проверить, что `/api/v1/subscriptions/plans` снова отдаёт `3000` KGS для
`standard` и `5000` KGS для `max` (годовые цены — с обычной скидкой).

Runtime `.env` намеренно не коммитится: в нём находятся merchant credentials и
другие production-секреты. Сам переключатель, его смысл и rollback-процедура
зафиксированы в Git, а код переключателя добавлен в PR #50.
