const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

function loadModuleForTests() {
  const source = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
  const feedbackDocuments = [];
  const context = {
    exports: {},
    feedbackDocuments,
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
      if (moduleName === "firebase-admin/app") {
        return { initializeApp: () => ({}) };
      }
      if (moduleName === "firebase-admin/firestore") {
        return {
          FieldValue: { serverTimestamp: () => "server-timestamp" },
          getFirestore: () => ({
            collection: () => ({
              add: async (document) => feedbackDocuments.push(document),
            }),
          }),
        };
      }
      throw new Error(`Unexpected module: ${moduleName}`);
    },
  };
  vm.runInNewContext(source, context);
  return context;
}

const moduleContext = loadModuleForTests();
const safeResult = moduleContext.safeProofreadingResult;

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
