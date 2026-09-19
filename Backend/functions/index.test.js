const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

function loadModuleForTests() {
  const source = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
  const feedbackDocuments = [];
  const supportDocuments = [];
  const context = {
    exports: {},
    feedbackDocuments,
    supportDocuments,
    fetch: async () => {
      throw new Error("Network calls are not expected in proofreading unit tests");
    },
    require(moduleName) {
      if (moduleName === "firebase-functions") {
        return { logger: { error() {}, warn() {} } };
      }
      if (moduleName === "firebase-functions/params") {
        return { defineSecret: () => ({ value: () => "test" }) };
      }
      if (moduleName === "firebase-functions/v2/https") {
        return { onRequest: (_options, handler) => handler };
      }
      if (moduleName === "firebase-functions/v2/scheduler") {
        return { onSchedule: (_options, handler) => handler };
      }
      if (moduleName === "firebase-admin/app") {
        return { initializeApp: () => ({}) };
      }
      if (moduleName === "firebase-admin/firestore") {
        return {
          FieldValue: {
            serverTimestamp: () => "server-timestamp",
            increment: (value) => value,
            arrayUnion: (...values) => ({ __arrayUnion: values }),
          },
          Timestamp: {
            fromDate: (value) => value,
            now: () => new Date(),
          },
          getFirestore: () => ({
            collection: (name) => ({
              add: async (document) => feedbackDocuments.push(document),
              where: (field, operator, values) => ({
                get: async () => ({
                  docs: supportDocuments
                    .filter((document) => operator === "in" && values.includes(document[field]))
                    .map((document) => ({
                      id: document.id,
                      data: () => document,
                    })),
                }),
              }),
              doc: (id) => ({
                set: async (document) => supportDocuments.push({ id, ...document }),
                get: async () => {
                  const document = [...supportDocuments].reverse().find((item) => item.id === id);
                  return {
                    exists: Boolean(document),
                    data: () => document,
                  };
                },
              }),
            }),
          }),
        };
      }
      if (moduleName === "firebase-admin/messaging") {
        return { getMessaging: () => ({ send: async () => "test-message" }) };
      }
      throw new Error(`Unexpected module: ${moduleName}`);
    },
  };
  vm.runInNewContext(source, context);
  return context;
}

const moduleContext = loadModuleForTests();
const safeResult = moduleContext.safeProofreadingResult;
const parseReminderOutput = moduleContext.parseReminderOutput;
const reminderNotificationCopy = moduleContext.reminderNotificationCopy;

test("allows punctuation and an obvious one-letter typo", () => {
  assert.equal(
    safeResult("привет как дела я очен устал", "Привет! Как дела? Я очень устал."),
    "Привет! Как дела? Я очень устал.",
  );
});

test("rejects a stylistic rewrite", () => {
  assert.equal(
    safeResult("я не успею доделать доклад", "Я не смогу закончить доклад."),
    null,
  );
});

test("rejects added, removed, and reordered words", () => {
  assert.equal(safeResult("я приду завтра", "Я точно приду завтра."), null);
  assert.equal(safeResult("я приду завтра", "Завтра я приду."), null);
});

test("preserves emoji and line-break positions", () => {
  assert.equal(safeResult("привет 👋", "Привет!"), null);
  assert.equal(safeResult("привет\nкак дела", "Привет, как\nдела?"), null);
});

test("stores valid feedback without keyboard content metadata", async () => {
  let statusCode = 0;
  let responseBody;
  const response = {
    set() { return this; },
    status(code) { statusCode = code; return this; },
    json(value) { responseBody = value; return this; },
  };
  const request = {
    method: "POST",
    body: {
      type: "suggestion",
      message: "Добавьте быстрый перевод",
      contact: "@tester",
      locale: "ru",
      appVersion: "1.0",
    },
    get(name) {
      return name === "x-budy-client" ? "8e20f7353e04590aa7e550840116ac322eaa30bda8e28c39" : undefined;
    },
  };

  await moduleContext.exports.budyFeedback(request, response);

  assert.equal(statusCode, 201);
  assert.equal(responseBody.ok, true);
  assert.equal(moduleContext.feedbackDocuments.length, 1);
  assert.equal(moduleContext.feedbackDocuments[0].message, "Добавьте быстрый перевод");
  assert.equal(moduleContext.feedbackDocuments[0].status, "new");
  assert.equal(Object.hasOwn(moduleContext.feedbackDocuments[0], "build"), false);
  assert.equal(Object.hasOwn(moduleContext.feedbackDocuments[0], "keyboardText"), false);
});

test("stores support metadata for a threaded request", async () => {
  let statusCode = 0;
  const response = {
    set() { return this; },
    status(code) { statusCode = code; return this; },
    json() { return this; },
  };
  const request = {
    method: "POST",
    body: {
      type: "issue",
      message: "Я",
      contact: "tester@example.com",
      locale: "ru",
      appVersion: "1.0",
      threadId: "11111111-1111-4111-8111-111111111111",
      subject: "Экран поддержки",
      category: "issue",
      installationId: "22222222-2222-4222-8222-222222222222",
      messageId: "33333333-3333-4333-8333-333333333333",
      messageCreatedAt: "2026-08-20T10:00:00.000Z",
      threadCreatedAt: "2026-08-20T09:00:00.000Z",
    },
    get(name) {
      return name === "x-budy-client" ? "8e20f7353e04590aa7e550840116ac322eaa30bda8e28c39" : undefined;
    },
  };

  await moduleContext.exports.budyFeedback(request, response);

  assert.equal(statusCode, 201);
  const document = moduleContext.supportDocuments.at(-1);
  assert.equal(document.id, "11111111-1111-4111-8111-111111111111");
  assert.equal(document.threadId, "11111111-1111-4111-8111-111111111111");
  assert.equal(document.category, "issue");
  assert.equal(document.messages.__arrayUnion[0].id, "33333333-3333-4333-8333-333333333333");
});

test("syncs read receipts for the matching installation", async () => {
  moduleContext.supportDocuments.push({
    id: "44444444-4444-4444-8444-444444444444",
    installationId: "55555555-5555-4555-8555-555555555555",
    messages: [{
      id: "66666666-6666-4666-8666-666666666666",
      author: "user",
      text: "Проверка статуса",
      createdAt: "2026-08-20T10:00:00.000Z",
    }],
    readMessageIds: ["66666666-6666-4666-8666-666666666666"],
    status: "awaiting_support",
  });

  let statusCode = 0;
  let responseBody;
  const response = {
    set() { return this; },
    status(code) { statusCode = code; return this; },
    json(value) { responseBody = value; return this; },
  };
  const request = {
    method: "POST",
    body: {
      action: "sync",
      threadId: "44444444-4444-4444-8444-444444444444",
      installationId: "55555555-5555-4555-8555-555555555555",
    },
    get(name) {
      return name === "x-budy-client" ? "8e20f7353e04590aa7e550840116ac322eaa30bda8e28c39" : undefined;
    },
  };

  await moduleContext.exports.budyFeedback(request, response);

  assert.equal(statusCode, 200);
  assert.equal(responseBody.readMessageIds[0], "66666666-6666-4666-8666-666666666666");
});

test("marks support messages read for the matching installation", async () => {
  moduleContext.supportDocuments.push({
    id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    installationId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    unreadForUser: true,
    messages: [
      {
        id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
        author: "support",
        text: "Ответ команды",
        createdAt: "2026-08-20T10:00:00.000Z",
      },
    ],
    readMessageIds: [],
  });

  let statusCode = 0;
  let responseBody;
  const response = {
    set() { return this; },
    status(code) { statusCode = code; return this; },
    json(value) { responseBody = value; return this; },
  };
  const request = {
    method: "POST",
    body: {
      action: "support_mark_read",
      threadId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      installationId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    },
    get(name) {
      return name === "x-budy-client" ? "8e20f7353e04590aa7e550840116ac322eaa30bda8e28c39" : undefined;
    },
  };

  await moduleContext.exports.budyFeedback(request, response);

  assert.equal(statusCode, 200);
  assert.equal(responseBody.ok, true);
  const update = moduleContext.supportDocuments.at(-1);
  assert.equal(update.unreadForUser, false);
  assert.deepEqual(update.readMessageIds.__arrayUnion, ["cccccccc-cccc-4ccc-8ccc-cccccccccccc"]);
});

test("authenticates support with an enabled Firestore access code", async () => {
  moduleContext.supportDocuments.push({
    id: "2468",
    enabled: true,
    role: "support",
  });

  let statusCode = 0;
  let responseBody;
  const response = {
    set() { return this; },
    status(code) { statusCode = code; return this; },
    json(value) { responseBody = value; return this; },
  };
  const request = {
    method: "POST",
    body: { action: "support_auth", code: "2468" },
    get(name) {
      return name === "x-budy-client" ? "8e20f7353e04590aa7e550840116ac322eaa30bda8e28c39" : undefined;
    },
  };

  await moduleContext.exports.budyFeedback(request, response);

  assert.equal(statusCode, 200);
  assert.equal(responseBody.ok, true);
  assert.equal(responseBody.role, "support");
});

test("lists only open support threads for an authenticated operator", async () => {
  moduleContext.supportDocuments.push(
    { id: "1357", enabled: true, role: "support" },
    {
      id: "77777777-7777-4777-8777-777777777777",
      subject: "Открытое обращение",
      category: "question",
      status: "awaiting_support",
      messages: [],
      createdAt: "2026-08-20T10:00:00.000Z",
      updatedAt: "2026-08-20T10:00:00.000Z",
    },
    {
      id: "88888888-8888-4888-8888-888888888888",
      subject: "Закрытое обращение",
      status: "closed",
      messages: [],
    },
  );

  let statusCode = 0;
  let responseBody;
  const response = {
    set() { return this; },
    status(code) { statusCode = code; return this; },
    json(value) { responseBody = value; return this; },
  };
  const request = {
    method: "POST",
    body: { action: "support_list", code: "1357" },
    get(name) {
      return name === "x-budy-client" ? "8e20f7353e04590aa7e550840116ac322eaa30bda8e28c39" : undefined;
    },
  };

  await moduleContext.exports.budyFeedback(request, response);

  assert.equal(statusCode, 200);
  assert.equal(
    responseBody.threads.some((thread) => thread.subject === "Открытое обращение"),
    true,
  );
  assert.equal(
    responseBody.threads.some((thread) => thread.subject === "Закрытое обращение"),
    false,
  );
});

test("moves a thread to in progress after a support reply", async () => {
  moduleContext.supportDocuments.push(
    { id: "8642", enabled: true, role: "support" },
    {
      id: "99999999-9999-4999-8999-999999999999",
      status: "awaiting_support",
      messages: [{
        id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        author: "user",
        text: "Нужна помощь",
        createdAt: "2026-08-20T10:00:00.000Z",
      }],
    },
  );

  let statusCode = 0;
  const response = {
    set() { return this; },
    status(code) { statusCode = code; return this; },
    json() { return this; },
  };
  const request = {
    method: "POST",
    body: {
      action: "support_reply",
      code: "8642",
      threadId: "99999999-9999-4999-8999-999999999999",
      messageId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
      message: "Поможем разобраться",
      createdAt: "2026-08-20T10:05:00.000Z",
    },
    get(name) {
      return name === "x-budy-client" ? "8e20f7353e04590aa7e550840116ac322eaa30bda8e28c39" : undefined;
    },
  };

  await moduleContext.exports.budyFeedback(request, response);

  assert.equal(statusCode, 201);
  const update = moduleContext.supportDocuments.at(-1);
  assert.equal(update.status, "awaiting_user");
  assert.equal(update.messages.__arrayUnion[0].author, "support");
  assert.deepEqual(update.readMessageIds.__arrayUnion, ["aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"]);
});

test("keeps an in-progress thread when the user replies", async () => {
  moduleContext.supportDocuments.push({
    id: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
    installationId: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
    status: "awaiting_user",
    messages: [],
  });

  let statusCode = 0;
  const response = {
    set() { return this; },
    status(code) { statusCode = code; return this; },
    json() { return this; },
  };
  const request = {
    method: "POST",
    body: {
      type: "issue",
      message: "Есть уточнение",
      threadId: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
      installationId: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
      messageId: "ffffffff-ffff-4fff-8fff-ffffffffffff",
    },
    get(name) {
      return name === "x-budy-client" ? "8e20f7353e04590aa7e550840116ac322eaa30bda8e28c39" : undefined;
    },
  };

  await moduleContext.exports.budyFeedback(request, response);

  assert.equal(statusCode, 201);
  assert.equal(moduleContext.supportDocuments.at(-1).status, "awaiting_user");
});

test("closes a support thread", async () => {
  moduleContext.supportDocuments.push(
    { id: "9753", enabled: true, role: "support" },
    {
      id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
      status: "awaiting_user",
      messages: [],
    },
  );

  let statusCode = 0;
  const response = {
    set() { return this; },
    status(code) { statusCode = code; return this; },
    json() { return this; },
  };
  const request = {
    method: "POST",
    body: {
      action: "support_close",
      code: "9753",
      threadId: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
    },
    get(name) {
      return name === "x-budy-client" ? "8e20f7353e04590aa7e550840116ac322eaa30bda8e28c39" : undefined;
    },
  };

  await moduleContext.exports.budyFeedback(request, response);

  assert.equal(statusCode, 200);
  assert.equal(moduleContext.supportDocuments.at(-1).status, "closed");
});

test("accepts a valid future reminder response", () => {
  const now = new Date("2026-07-23T08:00:00.000Z");
  const result = parseReminderOutput(
    '{"title":"Отправить договор","fireDate":"2026-07-24T18:00:00+04:00","needsClarification":false}',
    now,
  );
  assert.equal(result.needsClarification, false);
  assert.equal(result.title, "Отправить договор");
  assert.equal(result.fireDate, "2026-07-24T14:00:00.000Z");
});

test("rejects reminder dates in the past", () => {
  const now = new Date("2026-07-23T08:00:00.000Z");
  assert.equal(
    parseReminderOutput(
      '{"title":"Отправить договор","fireDate":"2026-07-22T18:00:00+04:00","needsClarification":false}',
      now,
    ),
    null,
  );
});

test("preserves the clarification response", () => {
  const result = parseReminderOutput(
    '{"title":"","fireDate":"","needsClarification":true}',
    new Date("2026-07-23T08:00:00.000Z"),
  );
  assert.equal(result.needsClarification, true);
});

test("formats an early reminder in the device language and time zone", () => {
  const copy = reminderNotificationCopy({
    locale: "ru",
    timeZone: "Europe/Samara",
    title: "Пообедать",
    eventDate: new Date("2026-07-23T12:30:00.000Z"),
    notificationDate: new Date("2026-07-23T12:15:00.000Z"),
  });

  assert.equal(copy.title, "Через 15 минут");
  assert.match(copy.body, /^Пообедать\n/);
  assert.match(copy.body, /16:30/);
});

test("uses the Laynor title for an at-time reminder", () => {
  const eventDate = new Date("2026-07-23T12:30:00.000Z");
  assert.equal(
    reminderNotificationCopy({
      locale: "ru",
      timeZone: "Europe/Samara",
      title: "Пообедать",
      eventDate,
      notificationDate: eventDate,
    }).title,
    "Laynor напоминает",
  );
});
