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

function detectChromiumBrowser() {
  const envPath = process.env.SAGEWRITE_BROWSER_PATH;
  const candidates = [
    { engine: "custom", path: envPath },
    { engine: "chrome", path: "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe" },
    { engine: "chrome", path: "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe" },
    { engine: "msedge", path: "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe" },
    { engine: "msedge", path: "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe" }
  ].filter((candidate) => candidate.path);

  return candidates.find((candidate) => fs.existsSync(candidate.path)) || { engine: "", path: "" };
}

async function canConnectToDebugUrl(debugUrl) {
  try {
    const response = await fetch(`${debugUrl.replace(/\/$/, "")}/json/version`, {
      method: "GET"
    });
    return response.ok;
  } catch {
    return false;
  }
}

function tryLoadPlaywright() {
  try {
    const require = createRequire(import.meta.url);
    return require("playwright-core");
  } catch {
    return null;
  }
}

function findFirstFile(platformRoot, patterns) {
  if (!fs.existsSync(platformRoot)) {
    return "";
  }

  const files = fs.readdirSync(platformRoot);
  return files.find((name) => patterns.some((pattern) => pattern.test(name))) || "";
}

function resolveBookRoot(platformRoot) {
  return path.resolve(platformRoot, "..", "..", "..");
}

function resolveUploadPath(bookRoot, relativePath) {
  if (!relativePath) {
    return "";
  }
  if (path.isAbsolute(relativePath)) {
    return relativePath;
  }
  return path.resolve(bookRoot, relativePath);
}

function collectFiles(platformRoot, packageData) {
  const bookRoot = resolveBookRoot(platformRoot);
  const epub = findFirstFile(platformRoot, [/\.epub$/i]);
  const pdf = findFirstFile(platformRoot, [/\.pdf$/i]);
  const cover = findFirstFile(platformRoot, [/^cover\.(png|jpe?g|webp)$/i]);
  const metadata = findFirstFile(platformRoot, [/^metadata\.json$/i]);
  const packageJson = findFirstFile(platformRoot, [/^google_play_books_package\.json$/i]);

  const packageBook = resolveUploadPath(bookRoot, packageData?.upload_assets?.book || "");
  const packageCover = resolveUploadPath(bookRoot, packageData?.upload_assets?.cover || "");
  const packageMetadata = resolveUploadPath(bookRoot, packageData?.upload_assets?.metadata || "");

  return {
    epub_file: epub,
    pdf_file: pdf,
    cover_file: cover,
    metadata_file: metadata,
    package_file: packageJson,
    resolved_book_path: packageBook || (epub ? path.join(platformRoot, epub) : pdf ? path.join(platformRoot, pdf) : ""),
    resolved_cover_path: packageCover || (cover ? path.join(platformRoot, cover) : ""),
    resolved_metadata_path: packageMetadata || (metadata ? path.join(platformRoot, metadata) : "")
  };
}

function buildBaseResult({
  mode,
  metadata,
  packageData,
  platformRoot,
  resultPath,
  sessionRoot,
  screenshotPath,
  browserInfo,
  attachBrowser,
  remoteDebugUrl,
  playwrightLoaded,
  files
}) {
  return {
    platform: "google",
    state: "prepared",
    mode,
    automation_type: "browser",
    supported_today: true,
    executed_browser: false,
    connection_mode: attachBrowser ? "cdp_attach" : "launch",
    browser_engine: browserInfo.engine || "",
    browser_path: browserInfo.path || "",
    remote_debug_url: remoteDebugUrl || "",
    playwright_available: Boolean(playwrightLoaded),
    folder: platformRoot,
    result_file: resultPath,
    session_root: sessionRoot,
    screenshot_path: screenshotPath,
    title: metadata.title || "",
    author: metadata.author || "",
    publisher: metadata.publisher || "",
    package_ready: Boolean(packageData?.package_ready),
    files,
    target_urls: {
      portal: "https://play.google.com/books/publish/",
      help_add_book: "https://support.google.com/books/partner/answer/3289675?hl=en",
      help_upload_files: "https://support.google.com/books/partner/answer/3297415?hl=en"
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

async function clickFirstVisibleLocator(candidates, logPath, label) {
  for (const locator of candidates) {
    if (!(await isVisible(locator))) {
      continue;
    }

    try {
      await locator.first().click({ timeout: 3000 });
      writeLog(logPath, `Clicked: ${label}`);
      return true;
    } catch {}
  }

  return false;
}

async function waitForGoogleEntry(page, logPath, screenshotPath, timeoutMs = 120000) {
  const startedAt = Date.now();
  let announcedLoginWait = false;

  while (Date.now() - startedAt < timeoutMs) {
    const currentUrl = page.url();
    const signInVisible = await isVisible(page.getByRole("button", { name: /sign in/i }))
      || await isVisible(page.getByRole("link", { name: /sign in/i }))
      || await isVisible(page.getByText(/sign in/i));
    const catalogVisible = await isVisible(page.getByText(/book catalog/i))
      || await isVisible(page.getByRole("link", { name: /book catalog/i }))
      || await isVisible(page.getByRole("button", { name: /book catalog/i }));
    const addBookVisible = await isVisible(page.getByText(/add book/i))
      || await isVisible(page.getByRole("button", { name: /add book/i }))
      || await isVisible(page.getByRole("link", { name: /add book/i }));
    const dashboardVisible = await isVisible(page.getByText(/partner center/i))
      || await isVisible(page.getByText(/catalog/i))
      || await isVisible(page.getByText(/book catalog/i));

    if (signInVisible || catalogVisible || addBookVisible || dashboardVisible || /play\.google\.com\/books\/publish/i.test(currentUrl)) {
      await capturePage(page, screenshotPath);
      return {
        detected: true,
        requiresLogin: signInVisible && !catalogVisible && !addBookVisible,
        currentUrl
      };
    }

    if (/accounts\.google\.com/i.test(currentUrl) && !announcedLoginWait) {
      writeLog(logPath, "Google sign-in flow detected. Waiting for manual login and verification.");
      announcedLoginWait = true;
    }

    await page.waitForTimeout(1500);
  }

  await capturePage(page, screenshotPath);
  return {
    detected: false,
    requiresLogin: false,
    currentUrl: page.url()
  };
}

async function waitForAuthenticatedPortal(page, logPath, screenshotPath, timeoutMs = 10 * 60 * 1000) {
  const startedAt = Date.now();
  let announced = false;

  while (Date.now() - startedAt < timeoutMs) {
    const currentUrl = page.url();
    const catalogVisible = await isVisible(page.getByText(/book catalog/i))
      || await isVisible(page.getByRole("link", { name: /book catalog/i }))
      || await isVisible(page.getByRole("button", { name: /book catalog/i }));
    const addBookVisible = await isVisible(page.getByText(/add book/i))
      || await isVisible(page.getByRole("button", { name: /add book/i }))
      || await isVisible(page.getByRole("link", { name: /add book/i }));
    const signInVisible = await isVisible(page.getByRole("button", { name: /sign in/i }))
      || await isVisible(page.getByRole("link", { name: /sign in/i }));

    if ((catalogVisible || addBookVisible) && !signInVisible && /play\.google\.com/i.test(currentUrl)) {
      await capturePage(page, screenshotPath);
      return {
        authenticated: true,
        currentUrl
      };
    }

    if (!announced) {
      writeLog(logPath, "Waiting for Google Play Books sign-in to complete.");
      announced = true;
    }

    await page.waitForTimeout(2000);
  }

  await capturePage(page, screenshotPath);
  return {
    authenticated: false,
    currentUrl: page.url()
  };
}

async function advanceToAddBook(page, logPath, screenshotPath) {
  const actions = [];

  const openedCatalog = await clickFirstVisibleLocator([
    page.getByRole("link", { name: /book catalog/i }),
    page.getByRole("button", { name: /book catalog/i }),
    page.getByText(/book catalog/i)
  ], logPath, "book-catalog");
  if (openedCatalog) {
    actions.push("book-catalog");
    await page.waitForTimeout(2000);
    await capturePage(page, screenshotPath);
  }

  const addBook = await clickFirstVisibleLocator([
    page.getByRole("button", { name: /add book/i }),
    page.getByRole("link", { name: /add book/i }),
    page.getByText(/add book/i)
  ], logPath, "add-book");
  if (addBook) {
    actions.push("add-book");
    await page.waitForTimeout(2500);
    await capturePage(page, screenshotPath);
  }

  return actions;
}

async function detectAddBookSurface(page, logPath, screenshotPath, timeoutMs = 60000) {
  const startedAt = Date.now();

  while (Date.now() - startedAt < timeoutMs) {
    const markers = [
      page.getByText(/type of book id/i),
      page.getByText(/save and continue/i),
      page.getByText(/get a google book id/i),
      page.getByText(/book info/i),
      page.getByText(/provide a description of the book/i),
      page.getByText(/upload content and cover files/i)
    ];

    for (const marker of markers) {
      if (await isVisible(marker)) {
        await capturePage(page, screenshotPath);
        writeLog(logPath, "Google add-book surface detected.");
        return {
          detected: true,
          currentUrl: page.url()
        };
      }
    }

    await page.waitForTimeout(1500);
  }

  await capturePage(page, screenshotPath);
  return {
    detected: false,
    currentUrl: page.url()
  };
}

async function main() {
  const args = parseArgs(process.argv);
  const mode = String(args.mode || "prepare").trim().toLowerCase();
  const attachBrowser = Boolean(args["attach-browser"]);
  const remoteDebugUrl = String(args["remote-debug-url"] || "").trim();
  const platformRoot = path.resolve(String(args["platform-root"] || ""));
  const metadataPath = path.resolve(String(args["metadata-path"] || ""));
  const packagePath = path.resolve(String(args["package-path"] || ""));
  const runRoot = path.resolve(String(args["run-root"] || ""));
  const resultPath = path.resolve(String(args["result-path"] || path.join(runRoot, "google_result.json")));
  const sessionRoot = path.resolve(String(args["session-root"] || path.join(platformRoot, ".automation", "edge-profile")));
  const screenshotsRoot = path.join(runRoot, "screenshots");
  const screenshotPath = path.join(screenshotsRoot, "google-portal.png");
  const logPath = path.join(runRoot, "session.log");

  ensureDir(runRoot);
  ensureDir(sessionRoot);
  ensureDir(screenshotsRoot);

  if (!fs.existsSync(metadataPath)) {
    throw new Error(`Google metadata.json not found: ${metadataPath}`);
  }
  if (!fs.existsSync(packagePath)) {
    throw new Error(`Google package file not found: ${packagePath}`);
  }

  const metadata = readJson(metadataPath);
  const packageData = readJson(packagePath);
  const playwright = tryLoadPlaywright();
  const browserInfo = detectChromiumBrowser();
  const files = collectFiles(platformRoot, packageData);

  const result = buildBaseResult({
    mode,
    metadata,
    packageData,
    platformRoot,
    resultPath,
    sessionRoot,
    screenshotPath,
    browserInfo,
    attachBrowser,
    remoteDebugUrl,
    playwrightLoaded: playwright,
    files
  });

  if (mode === "prepare") {
    result.state = packageData?.package_ready ? "prepared" : "blocked";
    result.next_step = result.playwright_available
      ? "Use -Mode draft or -Mode assist to open the Google Play Books Partner Center."
      : "Install engine/automation dependencies with npm install before browser-assisted Google runs.";
    result.notes = [
      "Google prepare mode validates the package and Partner Center entry wiring.",
      "Google's documented flow is Book Catalog -> Add book -> book info -> upload files -> pricing -> review and publish.",
      "Pricing, regions, and tax/payment setup still need to be completed in Partner Center."
    ];
    if (attachBrowser) {
      result.notes.push("Prepare mode is configured to attach to a manually started Chrome debugging session.");
    }
    writeJson(resultPath, result);
    writeLog(logPath, `Google prepare completed: ${result.state}`);
    return;
  }

  if (!playwright) {
    result.state = "blocked";
    result.next_step = "Install automation dependencies with npm install before Google draft/assist runs.";
    result.notes = [
      "playwright-core is not installed.",
      "Run npm install inside engine/automation and retry."
    ];
    writeJson(resultPath, result);
    writeLog(logPath, "Google browser automation blocked because playwright-core is unavailable.");
    return;
  }

  if (!browserInfo.path) {
    result.state = "blocked";
    result.next_step = "Install Google Chrome, Microsoft Edge, or set SAGEWRITE_BROWSER_PATH to a Chromium-based browser executable.";
    result.notes = [
      "Google browser automation requires a local browser executable.",
      "No supported Chromium browser path was detected on this machine."
    ];
    writeJson(resultPath, result);
    writeLog(logPath, "Google browser automation blocked because no supported Chromium executable was found.");
    return;
  }

  if (attachBrowser && !remoteDebugUrl) {
    result.state = "blocked";
    result.next_step = "Provide --remote-debug-url or pass -ChromeDebugPort from 09h/09f submit.";
    result.notes = [
      "Attach mode was requested but no remote debugging URL was provided."
    ];
    writeJson(resultPath, result);
    writeLog(logPath, "Google attach mode blocked because no remote debugging URL was provided.");
    return;
  }

  if (attachBrowser) {
    const debugReady = await canConnectToDebugUrl(remoteDebugUrl);
    if (!debugReady) {
      result.state = "awaiting_debug_browser";
      result.next_step = "Start Chrome manually with --remote-debugging-port and rerun with the same port.";
      result.notes = [
        "Could not reach the requested Chrome remote debugging endpoint.",
        "Example: chrome.exe --remote-debugging-port=9222"
      ];
      writeJson(resultPath, result);
      writeLog(logPath, `Google attach mode could not reach ${remoteDebugUrl}.`);
      return;
    }
  }

  let context = null;
  let browser = null;
  let keepBrowserOpen = false;
  try {
    if (attachBrowser) {
      browser = await playwright.chromium.connectOverCDP(remoteDebugUrl);
      context = browser.contexts()[0];
      if (!context) {
        throw new Error(`No browser context was available at ${remoteDebugUrl}`);
      }
      writeLog(logPath, `Attached to existing Chrome debugging session: ${remoteDebugUrl}`);
    } else {
      context = await playwright.chromium.launchPersistentContext(sessionRoot, {
        executablePath: browserInfo.path,
        headless: false,
        viewport: null,
        args: ["--start-maximized"]
      });
    }

    const existingPages = context.pages();
    const page = existingPages[0] || await context.newPage();
    result.executed_browser = true;

    await page.goto(result.target_urls.portal, {
      waitUntil: "domcontentloaded",
      timeout: 120000
    });
    await capturePage(page, screenshotPath);
    writeLog(logPath, "Opened Google Play Books Partner Center.");

    const entryState = await waitForGoogleEntry(page, logPath, screenshotPath);
    if (!entryState.detected) {
      result.state = "portal_timeout";
      result.next_step = "Open the screenshot and session log to see what blocked Google portal detection.";
      result.notes = [
        "Could not detect the Google Play Books Partner Center entry state within the timeout."
      ];
      writeJson(resultPath, result);
      return;
    }

    if (entryState.requiresLogin) {
      const clicked = await clickFirstVisibleLocator([
        page.getByRole("button", { name: /sign in/i }),
        page.getByRole("link", { name: /sign in/i }),
        page.getByText(/^sign in$/i)
      ], logPath, "sign-in");

      if (clicked) {
        await page.waitForTimeout(2000);
        await capturePage(page, screenshotPath);
      }

      const loginState = await waitForAuthenticatedPortal(page, logPath, screenshotPath);
      if (!loginState.authenticated) {
        result.state = "awaiting_login";
        result.next_step = "Finish Google sign-in and any verification steps, then rerun with -ReuseSession.";
        result.notes = [
          "The Google Partner Center session was created and can be reused.",
          "Google account login and verification still require manual completion."
        ];
        writeJson(resultPath, result);
        keepBrowserOpen = !attachBrowser;
        return;
      }
    }

    const actions = await advanceToAddBook(page, logPath, screenshotPath);
    const surface = await detectAddBookSurface(page, logPath, screenshotPath);

    result.actions = actions;
    if (surface.detected) {
      result.state = mode === "assist" ? "assist_ready" : "draft_ready";
      result.next_step = mode === "assist"
        ? "Continue filling the Google add-book flow, upload assets, and stop before final publish."
        : "Use the open Partner Center session to complete the draft setup.";
      result.notes = [
        "Google Partner Center entry and add-book flow were opened successfully.",
        "Metadata mapping is only partially automated in this phase; finish remaining Partner Center fields manually."
      ];
    } else {
      result.state = "portal_ready";
      result.next_step = "Use the open Google session or rerun with -ReuseSession to continue from the Partner Center.";
      result.notes = [
        "The Google Play Books Partner Center opened successfully.",
        "The add-book form was not conclusively detected after the initial clicks."
      ];
    }

    writeJson(resultPath, result);
    writeLog(logPath, `Google browser automation finished with state: ${result.state}`);
    keepBrowserOpen = !attachBrowser && ["assist_ready", "draft_ready", "portal_ready"].includes(result.state);
  } finally {
    if (context && keepBrowserOpen) {
      writeLog(logPath, "Keeping Google browser session open for manual review. Close the browser when you are done.");
      await new Promise((resolve) => {
        let settled = false;
        const finish = () => {
          if (!settled) {
            settled = true;
            resolve();
          }
        };

        try {
          context.on("close", finish);
        } catch {
          finish();
        }

        try {
          const pages = context.pages();
          if (pages.length === 0) {
            finish();
          }
        } catch {}
      });
    }

    if (context && !keepBrowserOpen) {
      if (!attachBrowser) {
        try {
          await context.close();
        } catch {}
      }
    }
  }
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
