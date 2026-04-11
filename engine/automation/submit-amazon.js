import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { createRequire } from "node:module";

function parseArgs(argv) {
  const args = {};
  for (let index = 2; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith("--")) {
      continue;
    }
    const key = token.slice(2);
    const next = argv[index + 1];
    if (!next || next.startsWith("--")) {
      args[key] = true;
      continue;
    }
    args[key] = next;
    index += 1;
  }
  return args;
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function resetDir(dirPath) {
  fs.rmSync(dirPath, { recursive: true, force: true });
  fs.mkdirSync(dirPath, { recursive: true });
}

function shouldSkipClone(name) {
  return [
    "Network",
    "Code Cache",
    "GPUCache",
    "GrShaderCache",
    "DawnGraphiteCache",
    "BrowserMetrics",
    "DeferredBrowserMetrics",
    "Crashpad",
    "CrashpadMetrics-active.pma",
    "lockfile",
    "SingletonCookie",
    "SingletonLock",
    "SingletonSocket"
  ].includes(name);
}

function copyDirBestEffort(sourcePath, targetPath) {
  if (!fs.existsSync(sourcePath)) {
    return;
  }

  ensureDir(targetPath);
  const entries = fs.readdirSync(sourcePath, { withFileTypes: true });
  for (const entry of entries) {
    if (shouldSkipClone(entry.name)) {
      continue;
    }

    const from = path.join(sourcePath, entry.name);
    const to = path.join(targetPath, entry.name);

    try {
      if (entry.isDirectory()) {
        copyDirBestEffort(from, to);
      } else {
        ensureDir(path.dirname(to));
        fs.copyFileSync(from, to);
      }
    } catch {}
  }
}

function cloneDir(sourcePath, targetPath) {
  resetDir(targetPath);
  if (!fs.existsSync(sourcePath)) {
    return;
  }
  copyDirBestEffort(sourcePath, targetPath);
}

function readJson(filePath) {
  const raw = fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, "");
  return JSON.parse(raw);
}

function writeJson(filePath, data) {
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2), "utf8");
}

function writeLog(logPath, message) {
  const line = `[${new Date().toISOString()}] ${message}`;
  fs.appendFileSync(logPath, `${line}\n`, "utf8");
  process.stdout.write(`${line}\n`);
}

async function capturePage(page, screenshotPath) {
  try {
    await page.screenshot({ path: screenshotPath, fullPage: true });
  } catch {}
}

function detectEdgePath() {
  const envPath = process.env.SAGEWRITE_BROWSER_PATH;
  const candidates = [
    envPath,
    "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
    "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe"
  ].filter(Boolean);

  return candidates.find((candidate) => fs.existsSync(candidate)) || "";
}

function resolveMainFiles(platformRoot) {
  const files = fs.existsSync(platformRoot) ? fs.readdirSync(platformRoot) : [];
  const epub = files.find((name) => /\.epub$/i.test(name)) || "";
  const cover = files.find((name) => /^cover\.(png|jpe?g|webp)$/i.test(name)) || "";
  const metadata = files.find((name) => /^metadata\.json$/i.test(name)) || "";
  return {
    epub,
    cover,
    metadata
  };
}

function tryLoadPlaywright() {
  try {
    const require = createRequire(import.meta.url);
    return require("playwright-core");
  } catch {
    return null;
  }
}

function buildBaseResult({
  mode,
  platformRoot,
  metadata,
  edgePath,
  playwrightLoaded,
  files,
  sessionRoot,
  screenshotPath
}) {
  return {
    platform: "amazon",
    state: "prepared",
    mode,
    automation_type: "browser",
    supported_today: true,
    executed_browser: false,
    browser_engine: "msedge",
    edge_path: edgePath || "",
    playwright_available: Boolean(playwrightLoaded),
    interactive_terminal: Boolean(process.stdin.isTTY),
    folder: platformRoot,
    title: metadata.title || "",
    author: metadata.author || "",
    session_root: sessionRoot,
    screenshot_path: screenshotPath,
    files,
    target_urls: {
      home: "https://kdp.amazon.com/",
      bookshelf: "https://kdp.amazon.com/en_US/bookshelf"
    }
  };
}

async function isVisible(locator) {
  try {
    return await locator.first().isVisible({ timeout: 1000 });
  } catch {
    return false;
  }
}

async function waitForBookshelf(page, logPath, screenshotPath, timeoutMs = 10 * 60 * 1000) {
  const startedAt = Date.now();
  let announcedLoginWait = false;
  let announcedVerifyWait = false;

  while (Date.now() - startedAt < timeoutMs) {
    const currentUrl = page.url();
    const bookshelfByUrl = /kdp\.amazon\.[^/]+\/.*bookshelf/i.test(currentUrl);
    const bookshelfMarkers = [
      page.getByText("Bookshelf", { exact: true }),
      page.getByRole("heading", { name: /bookshelf/i }),
      page.getByRole("button", { name: /create new title or series/i }),
      page.getByRole("link", { name: /create new title or series/i }),
      page.getByRole("button", { name: /create (a )?(kindle )?ebook/i }),
      page.getByRole("link", { name: /create (a )?(kindle )?ebook/i })
    ];

    if (bookshelfByUrl) {
      writeLog(logPath, "Bookshelf detected by URL.");
      await capturePage(page, screenshotPath);
      return { detected: true, reason: "url", currentUrl };
    }

    for (const marker of bookshelfMarkers) {
      if (await isVisible(marker)) {
        writeLog(logPath, "Bookshelf detected by visible marker.");
        await capturePage(page, screenshotPath);
        return { detected: true, reason: "marker", currentUrl };
      }
    }

    const loginMarkers = [
      page.getByLabel(/email or mobile phone number/i),
      page.getByLabel(/password/i),
      page.getByRole("button", { name: /sign in/i })
    ];

    const verifyMarkers = [
      page.getByText(/verify/i),
      page.getByText(/enter the characters/i),
      page.getByText(/approve the notification/i)
    ];

    for (const marker of loginMarkers) {
      if (await isVisible(marker)) {
        if (!announcedLoginWait) {
          writeLog(logPath, "Login page detected. Waiting for manual sign-in.");
          announcedLoginWait = true;
        }
        break;
      }
    }

    if (/\/ap\/cvf\/verify/i.test(currentUrl)) {
      if (!announcedVerifyWait) {
        writeLog(logPath, "Amazon verification page detected. Waiting for manual verification.");
        announcedVerifyWait = true;
      }
      await capturePage(page, screenshotPath);
      return {
        detected: false,
        reason: "verification",
        currentUrl
      };
    }

    for (const marker of verifyMarkers) {
      if (await isVisible(marker)) {
        if (!announcedVerifyWait) {
          writeLog(logPath, "Amazon verification challenge detected. Waiting for manual verification.");
          announcedVerifyWait = true;
        }
        await capturePage(page, screenshotPath);
        return {
          detected: false,
          reason: "verification",
          currentUrl
        };
      }
    }

    await page.waitForTimeout(2000);
  }

  await capturePage(page, screenshotPath);
  return {
    detected: false,
    reason: "timeout",
    currentUrl: page.url()
  };
}

async function clickFirstVisible(page, candidates, logPath) {
  for (const candidate of candidates) {
    const locator = candidate(page);
    if (await isVisible(locator)) {
      await locator.first().click();
      writeLog(logPath, `Clicked candidate: ${candidate.label}`);
      return candidate.label;
    }
  }
  return "";
}

function buildGlobalCreateCandidates() {
  return [
    Object.assign(
      (page) => page.getByRole("button", { name: /create new title or series/i }),
      { label: "button:create-new-title-or-series" }
    ),
    Object.assign(
      (page) => page.getByRole("link", { name: /create new title or series/i }),
      { label: "link:create-new-title-or-series" }
    ),
    Object.assign(
      (page) => page.getByText(/create new title or series/i),
      { label: "text:create-new-title-or-series" }
    ),
    Object.assign(
      (page) => page.getByRole("button", { name: /create (a )?(kindle )?ebook/i }),
      { label: "button:create-kindle-ebook" }
    ),
    Object.assign(
      (page) => page.getByRole("link", { name: /create (a )?(kindle )?ebook/i }),
      { label: "link:create-kindle-ebook" }
    ),
    Object.assign(
      (page) => page.getByText(/create (a )?(kindle )?ebook/i),
      { label: "text:create-kindle-ebook" }
    ),
    Object.assign(
      (page) => page.getByRole("button", { name: /create ebook/i }),
      { label: "button:create-ebook" }
    ),
    Object.assign(
      (page) => page.getByRole("link", { name: /create ebook/i }),
      { label: "link:create-ebook" }
    )
  ];
}

function buildKindleEbookCandidates() {
  return [
    Object.assign(
      (page) => page.getByRole("button", { name: /kindle ebook/i }),
      { label: "button:kindle-ebook" }
    ),
    Object.assign(
      (page) => page.getByRole("link", { name: /kindle ebook/i }),
      { label: "link:kindle-ebook" }
    ),
    Object.assign(
      (page) => page.getByRole("button", { name: /ebook/i }),
      { label: "button:ebook" }
    ),
    Object.assign(
      (page) => page.getByRole("link", { name: /ebook/i }),
      { label: "link:ebook" }
    ),
    Object.assign(
      (page) => page.getByText(/kindle ebook/i),
      { label: "text:kindle-ebook" }
    )
  ];
}

async function tryEnterDraftOrCreate(page, title, logPath, screenshotPath) {
  const normalizedTitle = String(title || "").trim();
  if (normalizedTitle) {
    const titleMatches = page.getByText(normalizedTitle, { exact: false });
    const titleCount = await titleMatches.count().catch(() => 0);

    for (let index = 0; index < titleCount; index += 1) {
      const row = titleMatches.nth(index).locator("xpath=ancestor::*[self::tr or self::div][1]");
      const rowCandidates = [
        row.getByRole("button", { name: /continue setup/i }),
        row.getByRole("link", { name: /continue setup/i }),
        row.getByRole("button", { name: /edit ebook content/i }),
        row.getByRole("link", { name: /edit ebook content/i }),
        row.getByRole("button", { name: /edit kindle ebook content/i }),
        row.getByRole("link", { name: /edit kindle ebook content/i })
      ];

      for (const locator of rowCandidates) {
        if (await isVisible(locator)) {
          await locator.first().click();
          await page.waitForTimeout(2500);
          await capturePage(page, screenshotPath);
          writeLog(logPath, `Entered existing draft for title: ${normalizedTitle}`);
          return {
            action: "open_existing_draft",
            matchedTitle: normalizedTitle,
            currentUrl: page.url()
          };
        }
      }
    }
  }

  const createAction = await clickFirstVisible(page, buildGlobalCreateCandidates(), logPath);
  if (createAction) {
    await page.waitForTimeout(2500);
    await capturePage(page, screenshotPath);

    let ebookTrigger = "";
    if (/create-new-title-or-series/i.test(createAction)) {
      ebookTrigger = await clickFirstVisible(page, buildKindleEbookCandidates(), logPath);
      if (ebookTrigger) {
        await page.waitForTimeout(2500);
        await capturePage(page, screenshotPath);
      }
    }

    return {
      action: ebookTrigger ? "create_new_kindle_ebook" : "create_new_ebook",
      matchedTitle: normalizedTitle || "",
      currentUrl: page.url(),
      trigger: createAction,
      ebookTrigger
    };
  }

  await capturePage(page, screenshotPath);
  return {
    action: "bookshelf_detected_but_no_entry_found",
    matchedTitle: normalizedTitle || "",
    currentUrl: page.url()
  };
}

async function fillFirstVisible(page, candidates, value, logPath) {
  if (!String(value || "").trim()) {
    return "";
  }

  for (const candidate of candidates) {
    const locator = candidate(page);
    if (await isVisible(locator)) {
      await locator.first().fill(String(value));
      writeLog(logPath, `Filled field: ${candidate.label}`);
      return candidate.label;
    }
  }

  return "";
}

async function fillBySemanticSearch(page, spec, value, logPath) {
  const trimmed = String(value || "").trim();
  if (!trimmed) {
    return "";
  }

  const result = await page.evaluate(({ spec, value }) => {
    const normalize = (text) => String(text || "")
      .toLowerCase()
      .replace(/\s+/g, " ")
      .trim();

    const includesAny = (text, patterns) => patterns.some((pattern) => normalize(text).includes(normalize(pattern)));
    const excludesAny = (text, patterns) => patterns.some((pattern) => normalize(text).includes(normalize(pattern)));

    const fillElement = (element, nextValue) => {
      if (!element) {
        return false;
      }

      const htmlElement = /** @type {HTMLElement} */ (element);
      if (!(htmlElement instanceof HTMLElement)) {
        return false;
      }

      const style = window.getComputedStyle(htmlElement);
      if (style.display === "none" || style.visibility === "hidden") {
        return false;
      }

      htmlElement.focus();

      if (htmlElement instanceof HTMLInputElement || htmlElement instanceof HTMLTextAreaElement) {
        htmlElement.value = nextValue;
        htmlElement.dispatchEvent(new Event("input", { bubbles: true }));
        htmlElement.dispatchEvent(new Event("change", { bubbles: true }));
        return true;
      }

      if (htmlElement.isContentEditable) {
        htmlElement.textContent = nextValue;
        htmlElement.dispatchEvent(new Event("input", { bubbles: true }));
        htmlElement.dispatchEvent(new Event("change", { bubbles: true }));
        return true;
      }

      return false;
    };

    const selector = spec.selector || 'input, textarea, [contenteditable="true"]';
    const elements = Array.from(document.querySelectorAll(selector));
    for (const element of elements) {
      const parts = [];
      parts.push(element.getAttribute("aria-label") || "");
      parts.push(element.getAttribute("placeholder") || "");
      parts.push(element.getAttribute("name") || "");
      parts.push(element.getAttribute("id") || "");

      const id = element.getAttribute("id");
      if (id) {
        const label = document.querySelector(`label[for="${id.replace(/"/g, '\\"')}"]`);
        if (label) {
          parts.push(label.textContent || "");
        }
      }

      let parent = element.parentElement;
      let depth = 0;
      while (parent && depth < 3) {
        parts.push((parent.textContent || "").slice(0, 240));
        parent = parent.parentElement;
        depth += 1;
      }

      const context = normalize(parts.join(" "));
      if (!includesAny(context, spec.patterns || [])) {
        continue;
      }
      if (excludesAny(context, spec.excludePatterns || [])) {
        continue;
      }
      if (fillElement(element, value)) {
        return { ok: true };
      }
    }

    return { ok: false };
  }, { spec, value: trimmed });

  if (result?.ok) {
    writeLog(logPath, `Filled field by semantic search: ${spec.label}`);
    return `semantic:${spec.label}`;
  }

  return "";
}

async function fillFieldSmart(page, fieldSpec, value, logPath) {
  const direct = await fillFirstVisible(page, fieldSpec.candidates || [], value, logPath);
  if (direct) {
    return direct;
  }

  if (fieldSpec.semantic) {
    return fillBySemanticSearch(page, fieldSpec.semantic, value, logPath);
  }

  return "";
}

async function fillFieldInSection(page, spec, value, logPath) {
  const trimmed = String(value || "").trim();
  if (!trimmed) {
    return "";
  }

  const result = await page.evaluate(({ spec, value }) => {
    const normalize = (text) => String(text || "")
      .toLowerCase()
      .replace(/\s+/g, " ")
      .trim();

    const includesAny = (text, patterns) => patterns.some((pattern) => normalize(text).includes(normalize(pattern)));
    const excludesAny = (text, patterns) => patterns.some((pattern) => normalize(text).includes(normalize(pattern)));
    const escapeHtml = (text) => String(text || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");

    const isVisible = (element) => {
      if (!(element instanceof HTMLElement)) {
        return false;
      }
      const style = window.getComputedStyle(element);
      if (style.display === "none" || style.visibility === "hidden") {
        return false;
      }
      const rect = element.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0;
    };

    const fillElement = (element, nextValue) => {
      if (!(element instanceof HTMLElement) || !isVisible(element)) {
        return false;
      }

      element.focus();

      if (element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement) {
        element.value = nextValue;
        element.dispatchEvent(new Event("input", { bubbles: true }));
        element.dispatchEvent(new Event("change", { bubbles: true }));
        return true;
      }

      if (element.isContentEditable) {
        const blocks = String(nextValue)
          .split(/\n{2,}/)
          .map((part) => part.trim())
          .filter(Boolean);

        if (blocks.length > 1) {
          element.innerHTML = blocks.map((part) => `<p>${escapeHtml(part)}</p>`).join("");
        } else {
          element.textContent = nextValue;
        }
        element.dispatchEvent(new Event("input", { bubbles: true }));
        element.dispatchEvent(new Event("change", { bubbles: true }));
        return true;
      }

      return false;
    };

    const buildContext = (element) => {
      const parts = [];
      parts.push(element.getAttribute("aria-label") || "");
      parts.push(element.getAttribute("placeholder") || "");
      parts.push(element.getAttribute("name") || "");
      parts.push(element.getAttribute("id") || "");
      parts.push(element.getAttribute("data-testid") || "");
      parts.push(element.textContent || "");

      const id = element.getAttribute("id");
      if (id) {
        const label = document.querySelector(`label[for="${id.replace(/"/g, '\\"')}"]`);
        if (label) {
          parts.push(label.textContent || "");
        }
      }

      let parent = element.parentElement;
      let depth = 0;
      while (parent && depth < 3) {
        parts.push((parent.textContent || "").slice(0, 240));
        parent = parent.parentElement;
        depth += 1;
      }

      return normalize(parts.join(" "));
    };

    const sectionSelector = spec.sectionSelector || 'section, fieldset, [role="region"], [role="group"], form > div, div';
    const fieldSelector = spec.fieldSelector || 'input, textarea, [contenteditable="true"]';
    const sectionNodes = Array.from(document.querySelectorAll(sectionSelector));
    const sectionCandidates = sectionNodes
      .filter((node) => node instanceof HTMLElement && isVisible(node))
      .map((node) => ({ node, text: normalize(node.textContent || "") }))
      .filter(({ text }) => includesAny(text, spec.sectionPatterns || []))
      .sort((left, right) => left.text.length - right.text.length);

    for (const { node } of sectionCandidates) {
      const fields = Array.from(node.querySelectorAll(fieldSelector))
        .filter((field) => field instanceof HTMLElement && isVisible(field));

      let firstVisibleField = null;
      for (const field of fields) {
        if (!firstVisibleField) {
          firstVisibleField = field;
        }

        const context = buildContext(field);
        if ((spec.excludePatterns || []).length && excludesAny(context, spec.excludePatterns || [])) {
          continue;
        }

        if ((spec.fieldPatterns || []).length && !includesAny(context, spec.fieldPatterns || [])) {
          continue;
        }

        if (fillElement(field, value)) {
          return { ok: true };
        }
      }

      if (spec.allowFirstFieldFallback && firstVisibleField && fillElement(firstVisibleField, value)) {
        return { ok: true, fallback: true };
      }
    }

    return { ok: false };
  }, { spec, value: trimmed });

  if (result?.ok) {
    const label = result.fallback ? `section-fallback:${spec.label}` : `section:${spec.label}`;
    writeLog(logPath, `Filled field by section search: ${label}`);
    return label;
  }

  return "";
}

async function fillDescriptionField(page, value, logPath) {
  const trimmed = String(value || "").trim();
  if (!trimmed) {
    return "";
  }

  const sectionFilled = await fillFieldInSection(page, {
    label: "description",
    sectionPatterns: ["description"],
    fieldPatterns: [],
    excludePatterns: ["short description"],
    fieldSelector: 'textarea, [contenteditable="true"]',
    allowFirstFieldFallback: true
  }, trimmed, logPath);
  if (sectionFilled) {
    return sectionFilled;
  }

  const sourceControls = [
    page.getByRole("button", { name: /^source$/i }),
    page.getByRole("link", { name: /^source$/i }),
    page.locator('button, a').filter({ hasText: /^Source$/i }).first()
  ];

  if (await clickFirstVisibleLocator(sourceControls, logPath, "description-source-toggle")) {
    await page.waitForTimeout(400);
    const sourceFilled = await fillFieldInSection(page, {
      label: "description-source",
      sectionPatterns: ["description"],
      fieldPatterns: [],
      excludePatterns: ["short description"],
      fieldSelector: 'textarea',
      allowFirstFieldFallback: true
    }, trimmed, logPath);
    if (sourceFilled) {
      return sourceFilled;
    }
  }

  for (const frame of page.frames()) {
    if (frame === page.mainFrame()) {
      continue;
    }

    const editorLocators = [
      frame.locator('body[contenteditable="true"]').first(),
      frame.locator('.cke_editable').first(),
      frame.locator('[contenteditable="true"]').first(),
      frame.locator('body').first()
    ];

    for (const locator of editorLocators) {
      if (await isVisible(locator)) {
        try {
          await locator.evaluate((element, nextValue) => {
            const target = /** @type {HTMLElement} */ (element);
            const escapeHtml = (text) => String(text || "")
              .replace(/&/g, "&amp;")
              .replace(/</g, "&lt;")
              .replace(/>/g, "&gt;");
            const blocks = String(nextValue)
              .split(/\n{2,}/)
              .map((part) => part.trim())
              .filter(Boolean);

            target.focus();
            if (blocks.length > 1) {
              target.innerHTML = blocks.map((part) => `<p>${escapeHtml(part)}</p>`).join("");
            } else {
              target.textContent = nextValue;
            }
            target.dispatchEvent(new Event("input", { bubbles: true }));
            target.dispatchEvent(new Event("change", { bubbles: true }));
          }, trimmed);
          writeLog(logPath, "Filled field via iframe editor: description");
          return "iframe:description";
        } catch {}
      }
    }
  }

  return "";
}

async function fillKeywordFieldInSection(page, index, value, logPath) {
  const trimmed = String(value || "").trim();
  if (!trimmed) {
    return "";
  }

  const number = index + 1;
  const result = await page.evaluate(({ index, number, value }) => {
    const normalize = (text) => String(text || "")
      .toLowerCase()
      .replace(/\s+/g, " ")
      .trim();

    const visible = (element) => {
      if (!(element instanceof HTMLElement)) {
        return false;
      }
      const style = window.getComputedStyle(element);
      if (style.display === "none" || style.visibility === "hidden") {
        return false;
      }
      const rect = element.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0;
    };

    const fill = (element, nextValue) => {
      if (!(element instanceof HTMLInputElement || element instanceof HTMLTextAreaElement) || !visible(element)) {
        return false;
      }
      element.focus();
      element.value = nextValue;
      element.dispatchEvent(new Event("input", { bubbles: true }));
      element.dispatchEvent(new Event("change", { bubbles: true }));
      return true;
    };

    const buildContext = (element) => {
      const parts = [];
      parts.push(element.getAttribute("aria-label") || "");
      parts.push(element.getAttribute("placeholder") || "");
      parts.push(element.getAttribute("name") || "");
      parts.push(element.getAttribute("id") || "");
      const id = element.getAttribute("id");
      if (id) {
        const label = document.querySelector(`label[for="${id.replace(/"/g, '\\"')}"]`);
        if (label) {
          parts.push(label.textContent || "");
        }
      }
      let parent = element.parentElement;
      let depth = 0;
      while (parent && depth < 4) {
        parts.push((parent.textContent || "").slice(0, 280));
        parent = parent.parentElement;
        depth += 1;
      }
      return normalize(parts.join(" "));
    };

    const sectionCandidates = Array.from(document.querySelectorAll('section, fieldset, [role="region"], [role="group"], form > div, div'))
      .filter((node) => node instanceof HTMLElement && visible(node))
      .map((node) => ({ node, text: normalize(node.textContent || "") }))
      .filter(({ text }) => text.includes("keyword") || text.includes("search terms") || text.includes("search keywords"))
      .sort((left, right) => left.text.length - right.text.length);

    for (const { node } of sectionCandidates) {
      const fields = Array.from(node.querySelectorAll('input, textarea'))
        .filter((field) => visible(field));

      const ranked = fields.map((field, fieldIndex) => ({
        field,
        fieldIndex,
        context: buildContext(field)
      }));

      for (const candidate of ranked) {
        if (
          candidate.context.includes(`keyword ${number}`) ||
          candidate.context.includes(`search term ${number}`) ||
          candidate.context.includes(`search terms ${number}`) ||
          candidate.context.includes(`box ${number}`)
        ) {
          if (fill(candidate.field, value)) {
            return { ok: true, mode: "numbered" };
          }
        }
      }

      if (ranked[index] && fill(ranked[index].field, value)) {
        return { ok: true, mode: "indexed" };
      }

      const emptyField = ranked.find((candidate) => {
        if (candidate.field instanceof HTMLInputElement || candidate.field instanceof HTMLTextAreaElement) {
          return String(candidate.field.value || "").trim() === "";
        }
        return false;
      });
      if (emptyField && fill(emptyField.field, value)) {
        return { ok: true, mode: "empty-slot" };
      }
    }

    return { ok: false };
  }, { index, number, value: trimmed });

  if (result?.ok) {
    const label = `section:keyword-${number}:${result.mode}`;
    writeLog(logPath, `Filled keyword by section search: ${label}`);
    return label;
  }

  return "";
}

async function clickFirstVisibleLocator(locators, logPath, label) {
  for (const locator of locators) {
    if (await isVisible(locator)) {
      try {
        const first = locator.first();
        if (typeof first.isEnabled === "function") {
          const enabled = await first.isEnabled().catch(() => true);
          if (!enabled) {
            continue;
          }
        }
        await first.click({ timeout: 3000 });
        writeLog(logPath, `Clicked field control: ${label}`);
        return true;
      } catch {}
    }
  }
  return false;
}

function buildTitleCandidates() {
  return [
    Object.assign(
      (page) => page.getByLabel(/book title/i),
      { label: "label:book-title" }
    ),
    Object.assign(
      (page) => page.getByRole("textbox", { name: /book title/i }),
      { label: "textbox:book-title" }
    ),
    Object.assign(
      (page) => page.locator('input[aria-label*="book title" i], input[placeholder*="book title" i], input[name*="booktitle" i], input[id*="booktitle" i]').first(),
      { label: "css:book-title-input" }
    ),
    Object.assign(
      (page) => page.locator('input[name*="title" i]:not([name*="subtitle" i]):not([id*="subtitle" i]):not([aria-label*="subtitle" i]):not([placeholder*="subtitle" i])').first(),
      { label: "css:title-input" }
    )
  ];
}

function buildSubtitleCandidates() {
  return [
    Object.assign(
      (page) => page.getByLabel(/subtitle/i),
      { label: "label:subtitle" }
    ),
    Object.assign(
      (page) => page.getByRole("textbox", { name: /subtitle/i }),
      { label: "textbox:subtitle" }
    ),
    Object.assign(
      (page) => page.locator('input[name*="subtitle" i]').first(),
      { label: "css:subtitle-input" }
    )
  ];
}

function buildDescriptionCandidates() {
  return [
    Object.assign(
      (page) => page.getByLabel(/description/i),
      { label: "label:description" }
    ),
    Object.assign(
      (page) => page.getByRole("textbox", { name: /description/i }),
      { label: "textbox:description" }
    ),
    Object.assign(
      (page) => page.locator('textarea[name*="description" i]').first(),
      { label: "css:description-textarea" }
    ),
    Object.assign(
      (page) => page.locator('[contenteditable="true"][aria-label*="description" i], [contenteditable="true"][data-placeholder*="description" i]').first(),
      { label: "css:description-contenteditable" }
    )
  ];
}

function buildKeywordCandidates(index) {
  const number = index + 1;
  return [
    Object.assign(
      (page) => page.getByLabel(new RegExp(`keyword\\s*${number}`, "i")),
      { label: `label:keyword-${number}` }
    ),
    Object.assign(
      (page) => page.getByRole("textbox", { name: new RegExp(`keyword\\s*${number}`, "i") }),
      { label: `textbox:keyword-${number}` }
    ),
    Object.assign(
      (page) => page.locator(`input[name*="keyword${number}" i], input[placeholder*="keyword ${number}" i]`).first(),
      { label: `css:keyword-${number}` }
    ),
    Object.assign(
      (page) => page.locator(`input[name*="searchterm${number}" i], input[id*="searchterm${number}" i], input[name*="search-term-${index}" i], input[id*="search-term-${index}" i]`).first(),
      { label: `css:search-term-${number}` }
    )
  ];
}

function parseAuthorName(author) {
  const trimmed = String(author || "").trim();
  if (!trimmed) {
    return {
      firstName: "",
      lastName: ""
    };
  }

  const spacedParts = trimmed.split(/\s+/).filter(Boolean);
  if (spacedParts.length > 1) {
    return {
      firstName: spacedParts[0],
      lastName: spacedParts.slice(1).join(" ")
    };
  }

  const cjkChars = Array.from(trimmed).filter((char) => /[\u3400-\u9fff]/.test(char));
  if (cjkChars.length >= 2 && cjkChars.length === Array.from(trimmed).length) {
    return {
      firstName: cjkChars[0],
      lastName: cjkChars.slice(1).join("")
    };
  }

  return {
    firstName: trimmed,
    lastName: trimmed
  };
}

function escapeRegex(text) {
  return String(text || "").replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function buildCategoryPlans(metadata) {
  const normalizePath = (value) => String(value || "")
    .split(">")
    .map((part) => part.trim())
    .filter(Boolean);

  const pathPlans = [];
  const recommended = Array.isArray(metadata?.platform_recommended_categories?.amazon)
    ? metadata.platform_recommended_categories.amazon
    : [];
  const directCategories = Array.isArray(metadata?.categories)
    ? metadata.categories
    : [];

  for (const item of [...directCategories, ...recommended.map((entry) => entry?.path)]) {
    const segments = normalizePath(item);
    if (segments.length >= 3) {
      const tail = segments.slice(-3);
      pathPlans.push({
        category: tail[0],
        subcategory: tail[1],
        placement: tail[2],
        sourcePath: segments.join(" > ")
      });
    }
  }

  if (pathPlans.length > 0) {
    return pathPlans;
  }

  const plans = [];
  const keywords = Array.isArray(metadata?.keywords) ? metadata.keywords.map((item) => String(item || "").toLowerCase()) : [];
  const combinedText = [
    metadata?.title,
    metadata?.subtitle,
    metadata?.type,
    metadata?.style,
    ...(metadata?.categories || []),
    ...keywords
  ].join(" ").toLowerCase();

  if (
    combinedText.includes("ai") ||
    combinedText.includes("technology") ||
    combinedText.includes("computer") ||
    combinedText.includes("digital") ||
    combinedText.includes("sagewrite")
  ) {
    plans.push({
      category: "Computers & Technology",
      subcategory: "Computer Science",
      placement: "General"
    });
  }

  if (plans.length === 0) {
    plans.push({
      category: "Computers & Technology",
      subcategory: "Computer Science",
      placement: "General"
    });
  }

  return plans;
}

async function waitForCategorySurface(pageLike, logPath, screenshotPath, timeoutMs = 15000) {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    const dialog = pageLike.getByRole("dialog").first();
    if (await isVisible(dialog)) {
      await capturePage(pageLike, screenshotPath);
      writeLog(logPath, "Category selector detected as in-page dialog.");
      return {
        surface: pageLike,
        root: dialog,
        mode: "dialog"
      };
    }

    const markers = [
      pageLike.getByRole("heading", { name: /^categories$/i }),
      pageLike.getByText(/^categories$/i),
      pageLike.getByText(/select categories and subcategories/i),
      pageLike.getByLabel(/category/i),
      pageLike.getByLabel(/subcategory/i)
    ];

    for (const marker of markers) {
      if (await isVisible(marker)) {
        await capturePage(pageLike, screenshotPath);
        writeLog(logPath, "Category selector detected as separate page/window.");
        return {
          surface: pageLike,
          root: pageLike.locator("body"),
          mode: "page"
        };
      }
    }

    await pageLike.waitForTimeout(400);
  }

  return null;
}

async function clickCategoryTriggerByDom(page, logPath) {
  const clicked = await page.evaluate(() => {
    const normalize = (text) => String(text || "").toLowerCase().replace(/\s+/g, " ").trim();
    const visible = (element) => {
      if (!(element instanceof HTMLElement)) {
        return false;
      }
      const style = window.getComputedStyle(element);
      if (style.display === "none" || style.visibility === "hidden" || style.pointerEvents === "none") {
        return false;
      }
      const rect = element.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0;
    };

    const sectionCandidates = Array.from(document.querySelectorAll('section, fieldset, [role="group"], [role="region"], form > div, div'))
      .filter((node) => node instanceof HTMLElement && visible(node))
      .filter((node) => normalize(node.textContent || "").includes("categories"))
      .sort((left, right) => (left.textContent || "").length - (right.textContent || "").length);

    const triggerPatterns = ["choose categories", "set categories", "add categories"];
    for (const section of sectionCandidates) {
      const controls = Array.from(section.querySelectorAll('button, a, [role="button"], input[type="button"], input[type="submit"], div, span'))
        .filter((node) => node instanceof HTMLElement && visible(node));
      for (const control of controls) {
        const text = normalize(control.textContent || control.getAttribute("value") || control.getAttribute("aria-label") || "");
        if (!triggerPatterns.some((pattern) => text.includes(pattern))) {
          continue;
        }
        if (control.getAttribute("disabled") !== null || control.getAttribute("aria-disabled") === "true") {
          continue;
        }
        control.click();
        return text || "categories-trigger";
      }
    }

    return "";
  });

  if (clicked) {
    writeLog(logPath, `Clicked category trigger by DOM fallback: ${clicked}`);
    return true;
  }

  return false;
}

async function openCategorySurface(page, logPath, screenshotPath) {
  const openLocators = [
    page.getByRole("button", { name: /set categories/i }),
    page.getByRole("button", { name: /choose categories/i }),
    page.getByRole("button", { name: /add categories/i }),
    page.getByRole("link", { name: /set categories/i }),
    page.getByRole("link", { name: /choose categories/i }),
    page.getByRole("link", { name: /add categories/i })
  ];

  for (const locator of openLocators) {
    if (!(await isVisible(locator))) {
      continue;
    }

    const first = locator.first();
    const enabled = typeof first.isEnabled === "function"
      ? await first.isEnabled().catch(() => true)
      : true;
    if (!enabled) {
      continue;
    }

    const popupPromise = page.waitForEvent("popup", { timeout: 5000 }).catch(() => null);
    const newPagePromise = page.context().waitForEvent("page", { timeout: 5000 }).catch(() => null);

    try {
      await first.click({ timeout: 3000 });
      writeLog(logPath, "Clicked field control: categories-open");
    } catch {
      continue;
    }

    let popupPage = await popupPromise;
    if (!popupPage) {
      popupPage = await newPagePromise;
    }

    if (popupPage) {
      try {
        await popupPage.waitForLoadState("domcontentloaded", { timeout: 15000 });
      } catch {}
      const popupSurface = await waitForCategorySurface(popupPage, logPath, screenshotPath, 15000);
      if (popupSurface) {
        writeLog(logPath, "Categories opened in a separate popup/window.");
        return popupSurface;
      }
    }

    const inlineSurface = await waitForCategorySurface(page, logPath, screenshotPath, 5000);
    if (inlineSurface) {
      return inlineSurface;
    }
  }

  const popupPromise = page.waitForEvent("popup", { timeout: 5000 }).catch(() => null);
  const newPagePromise = page.context().waitForEvent("page", { timeout: 5000 }).catch(() => null);
  const domClicked = await clickCategoryTriggerByDom(page, logPath);
  if (domClicked) {
    let popupPage = await popupPromise;
    if (!popupPage) {
      popupPage = await newPagePromise;
    }

    if (popupPage) {
      try {
        await popupPage.waitForLoadState("domcontentloaded", { timeout: 15000 });
      } catch {}
      const popupSurface = await waitForCategorySurface(popupPage, logPath, screenshotPath, 15000);
      if (popupSurface) {
        writeLog(logPath, "Categories opened in a separate popup/window via DOM fallback.");
        return popupSurface;
      }
    }

    const inlineSurface = await waitForCategorySurface(page, logPath, screenshotPath, 5000);
    if (inlineSurface) {
      return inlineSurface;
    }
  }

  writeLog(logPath, "Could not open categories selector from the details page.");

  return null;
}

async function setAdultOnlyNo(page, logPath) {
  const result = await page.evaluate(() => {
    const normalize = (text) => String(text || "").toLowerCase().replace(/\s+/g, " ").trim();
    const visible = (element) => {
      if (!(element instanceof HTMLElement)) {
        return false;
      }
      const style = window.getComputedStyle(element);
      if (style.display === "none" || style.visibility === "hidden") {
        return false;
      }
      const rect = element.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0;
    };

    const containers = Array.from(document.querySelectorAll('section, fieldset, [role="group"], [role="region"], form > div, div'))
      .filter((node) => node instanceof HTMLElement && visible(node))
      .filter((node) => {
        const text = normalize(node.textContent || "");
        return (
          text.includes("adult-only") ||
          text.includes("adult only") ||
          text.includes("adult content") ||
          text.includes("sexually explicit images or title") ||
          text.includes("sexually explicit") ||
          text.includes("explicit images") ||
          text.includes("explicit language")
        );
      })
      .sort((left, right) => (left.textContent || "").length - (right.textContent || "").length);

    for (const container of containers) {
      const noLikeNodes = Array.from(container.querySelectorAll('label, span, div, button'))
        .filter((node) => visible(node))
        .filter((node) => normalize(node.textContent || "") === "no");
      for (const node of noLikeNodes) {
        node.click();
        return true;
      }

      const radios = Array.from(container.querySelectorAll('input[type="radio"], input[type="checkbox"]'))
        .filter((node) => visible(node));
      for (const input of radios) {
        const valueText = normalize(input.getAttribute("value") || input.getAttribute("aria-label") || input.id || "");
        if (valueText === "no" || valueText.endsWith("-no")) {
          input.click();
          return true;
        }
      }
    }

    return false;
  });

  if (result) {
    writeLog(logPath, "Answered adult-only question with No.");
    return "adult-only:no";
  }

  return "";
}

async function selectOptionFromDropdown(page, rootLocator, labelText, optionText, logPath, actionLabel) {
  const escapedLabel = escapeRegex(labelText);
  const escapedOption = escapeRegex(optionText);
  const byLabel = rootLocator.getByLabel(new RegExp(`^${escapedLabel}$`, "i")).first();
  const byCombobox = rootLocator.getByRole("combobox", { name: new RegExp(`^${escapedLabel}$`, "i") }).first();

  try {
    if (await isVisible(byLabel)) {
      await byLabel.selectOption({ label: optionText }).catch(async () => {
        await byLabel.selectOption({ value: optionText });
      });
      writeLog(logPath, `Selected dropdown option: ${actionLabel} -> ${optionText}`);
      return true;
    }
  } catch {}

  try {
    if (await isVisible(byCombobox)) {
      try {
        await byCombobox.selectOption({ label: optionText });
        writeLog(logPath, `Selected combobox option: ${actionLabel} -> ${optionText}`);
        return true;
      } catch {}

      await byCombobox.click({ timeout: 3000 });
      await page.waitForTimeout(400);

      const openListCandidates = [
        page.getByRole("option", { name: new RegExp(`^${escapedOption}$`, "i") }),
        page.getByRole("listbox").getByText(new RegExp(`^${escapedOption}$`, "i")),
        page.getByRole("menuitem", { name: new RegExp(`^${escapedOption}$`, "i") }),
        page.getByText(new RegExp(`^${escapedOption}$`, "i"))
      ];

      if (await clickFirstVisibleLocator(openListCandidates, logPath, `${actionLabel}-option:${optionText}`)) {
        writeLog(logPath, `Selected dropdown option via popup list: ${actionLabel} -> ${optionText}`);
        return true;
      }
    }
  } catch {}

  const fallback = await page.evaluate(({ labelText, optionText }) => {
    const normalize = (text) => String(text || "").toLowerCase().replace(/\s+/g, " ").trim();
    const visible = (element) => {
      if (!(element instanceof HTMLElement)) {
        return false;
      }
      const style = window.getComputedStyle(element);
      if (style.display === "none" || style.visibility === "hidden") {
        return false;
      }
      const rect = element.getBoundingClientRect();
      return rect.width > 0 && rect.height > 0;
    };

    const labels = Array.from(document.querySelectorAll('label, div, span'))
      .filter((node) => node instanceof HTMLElement && visible(node))
      .filter((node) => normalize(node.textContent || "") === normalize(labelText));

    for (const labelNode of labels) {
      let parent = labelNode.parentElement;
      let depth = 0;
      while (parent && depth < 4) {
        const select = Array.from(parent.querySelectorAll('select')).find((node) => visible(node));
        if (select) {
          const option = Array.from(select.options).find((item) => normalize(item.textContent || item.label || item.value) === normalize(optionText));
          if (option) {
            select.value = option.value;
            select.dispatchEvent(new Event("input", { bubbles: true }));
            select.dispatchEvent(new Event("change", { bubbles: true }));
            return true;
          }
        }
        parent = parent.parentElement;
        depth += 1;
      }
    }

    return false;
  }, { labelText, optionText });

  if (fallback) {
    writeLog(logPath, `Selected dropdown option by DOM fallback: ${actionLabel} -> ${optionText}`);
    return true;
  }

  return false;
}

async function setPrimaryAudience(page, logPath) {
  const selected = [];

  const explicitSet = await setAdultOnlyNo(page, logPath);
  if (explicitSet) {
    selected.push(explicitSet);
    await page.waitForTimeout(300);
  }

  return selected;
}

async function fillAuthorSection(page, author, logPath) {
  const trimmed = String(author || "").trim();
  if (!trimmed) {
    return [];
  }

  const filled = [];
  await clickFirstVisibleLocator([
    page.getByRole("button", { name: /add primary author/i }),
    page.getByRole("button", { name: /add author/i }),
    page.getByRole("link", { name: /add primary author/i }),
    page.getByRole("link", { name: /add author/i })
  ], logPath, "author-expander");

  const parsedAuthor = parseAuthorName(trimmed);
  const firstNameValue = parsedAuthor.firstName;
  const lastNameValue = parsedAuthor.lastName;

  const firstFilled = await fillFieldInSection(page, {
    label: "author:first-name",
    sectionPatterns: ["author", "primary author or contributor"],
    fieldPatterns: ["first name"],
    excludePatterns: ["contributors"],
    fieldSelector: 'input, textarea'
  }, firstNameValue, logPath);
  if (firstFilled) {
    filled.push(firstFilled);
    if (lastNameValue) {
      const lastFilled = await fillFieldInSection(page, {
        label: "author:last-name",
        sectionPatterns: ["author", "primary author or contributor"],
        fieldPatterns: ["last name"],
        excludePatterns: ["contributors"],
        fieldSelector: 'input, textarea'
      }, lastNameValue, logPath);
      if (lastFilled) {
        filled.push(lastFilled);
      }
    }
    return filled;
  }

  const fallbackFirst = await fillFirstVisible(page, [
    Object.assign(
      (pageRef) => pageRef.getByLabel(/first name/i),
      { label: "label:first-name" }
    ),
    Object.assign(
      (pageRef) => pageRef.getByRole("textbox", { name: /first name/i }),
      { label: "textbox:first-name" }
    ),
    Object.assign(
      (pageRef) => pageRef.locator('input[name*="firstName" i], input[name*="first_name" i]').first(),
      { label: "css:first-name" }
    )
  ], firstNameValue, logPath);
  if (fallbackFirst) {
    filled.push(fallbackFirst);
    if (lastNameValue) {
      const fallbackLast = await fillFirstVisible(page, [
        Object.assign(
          (pageRef) => pageRef.getByLabel(/last name/i),
          { label: "label:last-name" }
        ),
        Object.assign(
          (pageRef) => pageRef.getByRole("textbox", { name: /last name/i }),
          { label: "textbox:last-name" }
        ),
        Object.assign(
          (pageRef) => pageRef.locator('input[name*="lastName" i], input[name*="last_name" i]').first(),
          { label: "css:last-name" }
        )
      ], lastNameValue, logPath);
      if (fallbackLast) {
        filled.push(fallbackLast);
      }
    }
    return filled;
  }

  const singleFilled = await fillFieldInSection(page, {
    label: "author:single",
    sectionPatterns: ["author", "primary author or contributor"],
    fieldPatterns: ["author"],
    excludePatterns: ["contributors"],
    fieldSelector: 'input, textarea'
  }, trimmed, logPath);
  if (singleFilled) {
    filled.push(singleFilled);
  }

  return filled;
}

async function setPublishingRights(page, logPath) {
  const candidates = [
    page.getByLabel(/i own the copyright/i),
    page.getByText(/i own the copyright/i),
    page.getByRole("radio", { name: /i own the copyright/i })
  ];

  if (await clickFirstVisibleLocator(candidates, logPath, "publishing-rights")) {
    return "publishing-rights";
  }

  return "";
}

async function setCategories(page, metadata, logPath, screenshotPath) {
  const categoryPlans = buildCategoryPlans(metadata);
  const selected = [];

  const audienceSelections = await setPrimaryAudience(page, logPath);
  selected.push(...audienceSelections);

  const categorySurface = await openCategorySurface(page, logPath, screenshotPath);
  if (!categorySurface) {
    return [];
  }

  const pickerPage = categorySurface.surface;
  const modalRoot = categorySurface.root;

  for (const plan of categoryPlans.slice(0, 1)) {
    const categorySet = await selectOptionFromDropdown(pickerPage, modalRoot, "Category", plan.category, logPath, "category");
    if (categorySet) {
      selected.push(`category-root:${plan.category}`);
      await page.waitForTimeout(500);
    }

    const subcategorySet = await selectOptionFromDropdown(pickerPage, modalRoot, "Subcategory", plan.subcategory, logPath, "subcategory");
    if (subcategorySet) {
      selected.push(`category-sub:${plan.subcategory}`);
      await page.waitForTimeout(800);
    }

    const placementPattern = new RegExp(`^${escapeRegex(plan.placement)}$`, "i");
    const placementClicked = await clickFirstVisibleLocator([
      modalRoot.getByRole("checkbox", { name: placementPattern }),
      modalRoot.getByRole("radio", { name: placementPattern }),
      modalRoot.getByText(placementPattern)
    ], logPath, `category-placement:${plan.placement}`);

    if (placementClicked) {
      selected.push(`category-placement:${plan.placement}`);
    }
  }

  const saved = await clickFirstVisibleLocator([
    modalRoot.getByRole("button", { name: /save/i }),
    modalRoot.getByRole("button", { name: /done/i }),
    modalRoot.getByRole("button", { name: /apply/i }),
    modalRoot.getByRole("button", { name: /confirm/i }),
    modalRoot.getByRole("button", { name: /add another category/i })
  ], logPath, "categories-save");

  if (saved && pickerPage !== page) {
    try {
      await pickerPage.waitForLoadState("domcontentloaded", { timeout: 5000 });
    } catch {}
    try {
      await pickerPage.close({ runBeforeUnload: true });
    } catch {}
    try {
      await page.bringToFront();
    } catch {}
  }

  await page.waitForTimeout(1200);
  await capturePage(page, screenshotPath);
  return selected;
}

async function waitForDetailsPage(page, logPath, screenshotPath, timeoutMs = 120000) {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    const currentUrl = page.url();
    if (/\/title-setup\/kindle\/.*\/details/i.test(currentUrl)) {
      await capturePage(page, screenshotPath);
      writeLog(logPath, "Kindle details page detected by URL.");
      return {
        detected: true,
        reason: "url",
        currentUrl
      };
    }

    const titleMarkers = [
      page.getByLabel(/book title/i),
      page.getByRole("textbox", { name: /book title/i }),
      page.getByText(/book title/i)
    ];

    for (const marker of titleMarkers) {
      if (await isVisible(marker)) {
        await capturePage(page, screenshotPath);
        writeLog(logPath, "Kindle details page detected by visible title field.");
        return {
          detected: true,
          reason: "marker",
          currentUrl
        };
      }
    }

    await page.waitForTimeout(1500);
  }

  await capturePage(page, screenshotPath);
  return {
    detected: false,
    reason: "timeout",
    currentUrl: page.url()
  };
}

async function clickSaveAndContinue(page, logPath, screenshotPath) {
  const candidates = [
    page.getByRole("button", { name: /save and continue/i }),
    page.getByRole("link", { name: /save and continue/i }),
    page.locator('button, a').filter({ hasText: /save and continue/i }).first(),
    page.getByRole("button", { name: /continue/i }),
    page.getByRole("link", { name: /continue/i })
  ];

  if (await clickFirstVisibleLocator(candidates, logPath, "save-and-continue")) {
    await page.waitForTimeout(2500);
    await capturePage(page, screenshotPath);
    return "save-and-continue";
  }

  return "";
}

async function waitForContentPage(page, logPath, screenshotPath, timeoutMs = 120000) {
  const startedAt = Date.now();
  while (Date.now() - startedAt < timeoutMs) {
    const currentUrl = page.url();
    if (/\/title-setup\/kindle\/.*\/content/i.test(currentUrl)) {
      await capturePage(page, screenshotPath);
      writeLog(logPath, "Kindle content page detected by URL.");
      return {
        detected: true,
        reason: "url",
        currentUrl
      };
    }

    const markers = [
      page.getByText(/kindle ebook content/i),
      page.getByRole("heading", { name: /kindle ebook content/i }),
      page.getByText(/upload ebook manuscript/i),
      page.getByText(/manuscript/i),
      page.getByText(/ebook cover/i),
      page.getByText(/digital rights management/i),
      page.getByText(/upload your ebook manuscript/i)
    ];

    for (const marker of markers) {
      if (await isVisible(marker)) {
        if (/\/title-setup\/kindle\/.*\/details/i.test(currentUrl)) {
          continue;
        }
        await capturePage(page, screenshotPath);
        writeLog(logPath, "Kindle content page detected by visible marker.");
        return {
          detected: true,
          reason: "marker",
          currentUrl
        };
      }
    }

    await page.waitForTimeout(1500);
  }

  await capturePage(page, screenshotPath);
  return {
    detected: false,
    reason: "timeout",
    currentUrl: page.url()
  };
}

async function fillKindleDetailsPage(page, metadata, logPath, screenshotPath) {
  const filledFields = [];

  const titleField = await fillFieldInSection(page, {
    label: "book-title",
    sectionPatterns: ["book title"],
    fieldPatterns: ["book title"],
    excludePatterns: ["subtitle", "series"],
    fieldSelector: 'input, textarea'
  }, metadata.title || "", logPath) || await fillFieldSmart(page, {
    candidates: buildTitleCandidates(),
    semantic: {
      label: "book-title",
      patterns: ["book title", "title"],
      excludePatterns: ["subtitle", "series title"],
      selector: 'input, textarea, [contenteditable="true"]'
    }
  }, metadata.title || "", logPath);
  if (titleField) {
    filledFields.push(titleField);
  }

  const subtitleField = await fillFieldInSection(page, {
    label: "subtitle",
    sectionPatterns: ["book title"],
    fieldPatterns: ["subtitle"],
    excludePatterns: [],
    fieldSelector: 'input, textarea'
  }, metadata.subtitle || "", logPath) || await fillFieldSmart(page, {
    candidates: buildSubtitleCandidates(),
    semantic: {
      label: "subtitle",
      patterns: ["subtitle"],
      excludePatterns: [],
      selector: 'input, textarea, [contenteditable="true"]'
    }
  }, metadata.subtitle || "", logPath);
  if (subtitleField) {
    filledFields.push(subtitleField);
  }

  const authorFields = await fillAuthorSection(page, metadata.author || "", logPath);
  filledFields.push(...authorFields);

  const descriptionValue = metadata.long_description || metadata.description || "";
  const descriptionField = await fillDescriptionField(page, descriptionValue, logPath) || await fillFieldSmart(page, {
    candidates: buildDescriptionCandidates(),
    semantic: {
      label: "description",
      patterns: ["description", "book description", "product description"],
      excludePatterns: ["short description"],
      selector: 'textarea, [contenteditable="true"], input'
    }
  }, descriptionValue, logPath);
  if (descriptionField) {
    filledFields.push(descriptionField);
  }

  const rightsField = await setPublishingRights(page, logPath);
  if (rightsField) {
    filledFields.push(rightsField);
  }

  const categoryFields = await setCategories(page, metadata, logPath, screenshotPath);
  filledFields.push(...categoryFields);

  const keywords = Array.isArray(metadata.keywords) ? metadata.keywords.slice(0, 7) : [];
  for (let index = 0; index < keywords.length; index += 1) {
    const keywordField = await fillKeywordFieldInSection(page, index, keywords[index], logPath) || await fillFieldSmart(page, {
      candidates: buildKeywordCandidates(index),
      semantic: {
        label: `keyword-${index + 1}`,
        patterns: [
          `keyword ${index + 1}`,
          `keyword box ${index + 1}`,
          `search term ${index + 1}`,
          `search terms ${index + 1}`
        ],
        excludePatterns: [],
        selector: 'input, textarea'
      }
    }, keywords[index], logPath);
    if (keywordField) {
      filledFields.push(keywordField);
    }
  }

  await capturePage(page, screenshotPath);
  return filledFields;
}

async function run() {
  const args = parseArgs(process.argv);
  const mode = args.mode || "prepare";
  const platformRoot = args["platform-root"];
  const metadataPath = args["metadata-path"];
  const runRoot = args["run-root"];
  const resultPath = args["result-path"];
  const sessionRoot = args["session-root"];

  if (!platformRoot || !metadataPath || !runRoot || !resultPath || !sessionRoot) {
    throw new Error("Missing required arguments for submit-amazon.js.");
  }

  ensureDir(runRoot);
  ensureDir(sessionRoot);
  ensureDir(path.join(runRoot, "screenshots"));
  const logPath = path.join(runRoot, "amazon-automation.log");
  const screenshotPath = path.join(runRoot, "screenshots", "amazon-browser.png");
  const fallbackSessionRoot = path.join(runRoot, "artifacts", "edge-profile-clone");

  const metadata = readJson(metadataPath);
  const files = resolveMainFiles(platformRoot);
  const edgePath = detectEdgePath();
  const playwright = tryLoadPlaywright();

  const result = buildBaseResult({
    mode,
    platformRoot,
    metadata,
    edgePath,
    playwrightLoaded: playwright,
    files,
    sessionRoot,
    screenshotPath
  });

  const missingItems = [];
  if (!files.metadata) missingItems.push("metadata.json");
  if (!files.epub) missingItems.push("book.epub");
  if (!files.cover) missingItems.push("cover image");
  if (!metadata.title) missingItems.push("title");
  if (!metadata.author) missingItems.push("author");

  result.package_ready = missingItems.length === 0;
  result.missing_items = missingItems;
  result.session_root_fallback = fallbackSessionRoot;

  writeLog(logPath, `Amazon automation mode: ${mode}`);
  writeLog(logPath, `Platform root: ${platformRoot}`);

  if (mode === "prepare") {
    result.state = result.package_ready ? "prepared" : "blocked";
    result.next_step = result.package_ready
      ? "Amazon package is complete. Next step is interactive browser automation."
      : "Fix missing package items before starting browser automation.";
    result.notes = [
      "Prepare mode does not start a browser.",
      result.playwright_available
        ? "playwright-core is available."
        : "playwright-core is not installed yet in engine/automation.",
      edgePath
        ? `Edge detected at ${edgePath}`
        : "Microsoft Edge executable was not found."
    ];
    writeJson(resultPath, result);
    return;
  }

  if (!result.package_ready) {
    result.state = "blocked";
    result.next_step = "Package is incomplete; browser automation was not started.";
    result.notes = ["Missing package items must be fixed before automation can continue."];
    writeJson(resultPath, result);
    return;
  }

  if (!playwright) {
    result.state = "blocked";
    result.next_step = "Install playwright-core in engine/automation before using draft or assist.";
    result.notes = ["Run npm install inside engine/automation."];
    writeJson(resultPath, result);
    return;
  }

  if (!edgePath) {
    result.state = "blocked";
    result.next_step = "Install Microsoft Edge or set SAGEWRITE_BROWSER_PATH.";
    result.notes = ["Browser executable could not be resolved."];
    writeJson(resultPath, result);
    return;
  }

  const { chromium } = playwright;
  let browserContext;
  try {
    try {
      browserContext = await chromium.launchPersistentContext(sessionRoot, {
        headless: false,
        executablePath: edgePath,
        viewport: { width: 1440, height: 960 }
      });
      result.session_launch_mode = "primary";
    } catch (error) {
      writeLog(logPath, `Primary session launch failed. Falling back to cloned session. Reason: ${error.message}`);
      cloneDir(sessionRoot, fallbackSessionRoot);
      browserContext = await chromium.launchPersistentContext(fallbackSessionRoot, {
        headless: false,
        executablePath: edgePath,
        viewport: { width: 1440, height: 960 }
      });
      result.session_launch_mode = "fallback_clone";
      result.session_root_active = fallbackSessionRoot;
    }

    if (!result.session_root_active) {
      result.session_root_active = sessionRoot;
    }

    const page = browserContext.pages()[0] || await browserContext.newPage();
    const targetUrl = "https://kdp.amazon.com/en_US/bookshelf";

    writeLog(logPath, `Opening ${targetUrl}`);
    await page.goto(targetUrl, { waitUntil: "domcontentloaded", timeout: 120000 });
    await capturePage(page, screenshotPath);

    result.executed_browser = true;
    result.state = "browser_opened";
    result.current_url = page.url();
    result.next_step = "Waiting for manual login and bookshelf detection.";
    result.notes = [
      "A persistent Edge profile has been created for Amazon automation.",
      "Close the browser window after finishing this assist session.",
      "The same session profile can be reused in the next run."
    ];
    writeJson(resultPath, result);

    writeLog(logPath, "Browser session opened. Waiting for login, verification, and bookshelf detection.");
    const bookshelfResult = await waitForBookshelf(page, logPath, screenshotPath);
    result.login_detected = !bookshelfResult.detected;
    result.bookshelf_detected = bookshelfResult.detected;
    result.bookshelf_reason = bookshelfResult.reason;
    result.current_url = bookshelfResult.currentUrl || page.url();

    if (bookshelfResult.detected) {
      const entryResult = await tryEnterDraftOrCreate(page, metadata.title || "", logPath, screenshotPath);
      result.entry_action = entryResult.action;
      result.entry_target = entryResult.matchedTitle || "";
      result.entry_url = entryResult.currentUrl || page.url();
      if (entryResult.trigger) {
        result.entry_trigger = entryResult.trigger;
      }
      if (entryResult.ebookTrigger) {
        result.entry_ebook_trigger = entryResult.ebookTrigger;
      }
      result.state = "bookshelf_ready";

      const detailsResult = await waitForDetailsPage(page, logPath, screenshotPath);
      result.details_page_detected = detailsResult.detected;
      result.details_page_reason = detailsResult.reason;
      result.details_page_url = detailsResult.currentUrl || page.url();

      if (detailsResult.detected) {
        const filledFields = await fillKindleDetailsPage(page, metadata, logPath, screenshotPath);
        result.filled_fields = filledFields;
        result.state = "details_prefilled";

        const continueAction = await clickSaveAndContinue(page, logPath, screenshotPath);
        if (continueAction) {
          result.continue_action = continueAction;
          const contentResult = await waitForContentPage(page, logPath, screenshotPath);
          result.content_page_detected = contentResult.detected;
          result.content_page_reason = contentResult.reason;
          result.content_page_url = contentResult.currentUrl || page.url();

          if (contentResult.detected) {
            result.state = "content_page_ready";
            result.next_step = "Details were prefilled and Save and Continue succeeded. Review the Kindle eBook Content page next.";
          } else {
            result.next_step = "Details were prefilled and Save and Continue was clicked, but the content page was not confirmed automatically.";
          }
        } else {
          result.next_step = "Core fields have been prefilled. Review the page, then continue manually to the next KDP step.";
        }
      } else {
        result.next_step = mode === "draft"
          ? "Bookshelf entered. Review the opened draft/create page and continue saving draft manually."
          : "Bookshelf entered. Continue manually until just before final publish confirmation.";
      }
    } else if (bookshelfResult.reason === "verification") {
      result.state = "verification_required";
      result.next_step = "Amazon requested verification. Complete the verification step, then re-run assist.";
    } else {
      result.state = "waiting_for_login";
      result.next_step = "Login was not completed before timeout or window close. Re-run assist and sign in.";
    }

    writeJson(resultPath, result);
    writeLog(logPath, "Close the browser window to finish this assist session.");
    await new Promise((resolve) => browserContext.once("close", resolve));
  } catch (error) {
    if (browserContext) {
      try {
        await browserContext.close();
      } catch {}
    }
    throw error;
  }

  result.state = "completed_interactive_session";
  result.next_step = "Browser session closed. Review screenshot, logs, and current Amazon draft status.";
  writeJson(resultPath, result);
}

run().catch((error) => {
  const args = parseArgs(process.argv);
  const resultPath = args["result-path"];
  const failure = {
    platform: "amazon",
    state: "failed",
    mode: args.mode || "prepare",
    summary: error.message
  };

  if (resultPath) {
    try {
      writeJson(resultPath, failure);
    } catch {}
  }

  process.stderr.write(`${error.message}\n`);
  process.exit(1);
});
