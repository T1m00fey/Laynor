# Laynor MVP

Laynor — iOS-приложение и системная клавиатура, которая помогает переписывать и исправлять текст прямо в любом приложении.

## Архитектура

```text
Laynor → Firebase HTTPS Function → OpenAI Responses API
```

- Firebase project: `factorial-9c9f3`;
- function: `budyRewrite`;
- region: `europe-west1`;
- endpoint: `https://europe-west1-factorial-9c9f3.cloudfunctions.net/budyRewrite`;
- OpenAI-ключ доступен только функции через Firebase Secret Manager;
- прямых запросов к OpenAI из iOS-приложения нет;
- Firebase Apple SDK не требуется: приложение использует `URLSession`.

## Firebase deploy

Полная инструкция находится в [`Backend/README.md`](Backend/README.md). Кратко:

```bash
cd Backend/functions
npm install

cd ..
firebase login
firebase use factorial-9c9f3
firebase functions:secrets:set BUDY_OPENAI_API_KEY
firebase deploy --only functions:budy:budyRewrite
```

Пользователю ничего вводить не нужно: адрес функции и идентификатор клиента уже встроены в приложение. Сам OpenAI API-ключ хранится только в Firebase Secret Manager и в iOS-приложение не попадает.

## Запуск iOS-приложения

1. Откройте `BudyAI.xcodeproj` в Xcode.
2. Для targets `BudyAI` и `KeyboardExtension` выберите свою Team в Signing & Capabilities.
3. Создайте App Group `group.Tim.BudyAI` в Apple Developer и подключите его к обеим targets.
4. На iPhone откройте Настройки → Основные → Клавиатура → Клавиатуры → Новые клавиатуры → Laynor.
5. Включите «Полный доступ» — он нужен iOS-клавиатуре для HTTPS-запросов к Firebase.

## Ограничения MVP

- сторонние клавиатуры недоступны в защищённых полях паролей и некоторых системных полях;
- встроенный идентификатор клиента защищает endpoint только от случайных запросов; перед App Store его следует дополнить Firebase App Check и rate limiting;
- функция ограничивает размер текста и количество одновременно работающих инстансов, но полноценный per-user rate limiting ещё не добавлен.
