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

function detectEdgePath() {
  const envPath = process.env.SAGEWRITE_BROWSER_PATH;
  const candidates = [
    envPath,
    "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
    "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe"
  ].filter(Boolean);

  return candidates.find((candidate) => fs.existsSync(candidate)) || "";
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
  const cover = findFirstFile(platformRoot, [/^cover\.(png|jpe?g|webp)$/i]);
  const sample = findFirstFile(platformRoot, [/^sample\.(epub|pdf)$/i, /sample/i]);
  const metadata = findFirstFile(platformRoot, [/^metadata\.json$/i]);
  const packageJson = findFirstFile(platformRoot, [/^apple_books_package\.json$/i]);

  const packageBook = resolveUploadPath(bookRoot, packageData?.upload_assets?.book || "");
  const packageCover = resolveUploadPath(bookRoot, packageData?.upload_assets?.cover || "");
  const packageMetadata = resolveUploadPath(bookRoot, packageData?.upload_assets?.metadata || "");

  return {
    epub_file: epub,
    cover_file: cover,
    sample_file: sample,
    metadata_file: metadata,
    package_file: packageJson,
    resolved_book_path: packageBook || (epub ? path.join(platformRoot, epub) : ""),
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
  edgePath,
  playwrightLoaded,
  files
}) {
  return {
    platform: "apple",
    state: "prepared",
    mode,
    automation_type: "browser",
    supported_today: true,
    executed_browser: false,
    browser_engine: "msedge",
    edge_path: edgePath || "",
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
      portal: "https://authors.apple.com/epub-upload",
      help: "https://authors.apple.com/support/4574-publish-book-from-web",
      pricing: "https://itunesconnect.apple.com/"
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

async function waitForAppleEntry(page, logPath, screenshotPath, timeoutMs = 120000) {
  const startedAt = Date.now();
  let announcedLoginWait = false;

  while (Date.now() - startedAt < timeoutMs) {
    const currentUrl = page.url();
    const signInVisible = await isVisible(page.getByText(/sign in to itunes connect/i))
      || await isVisible(page.getByRole("button", { name: /sign in to itunes connect/i }))
      || await isVisible(page.getByRole("link", { name: /sign in to itunes connect/i }));
    const continueVisible = await isVisible(page.getByRole("button", { name: /^continue$/i }))
      || await isVisible(page.getByRole("link", { name: /^continue$/i }));
    const submitVisible = await isVisible(page.getByRole("button", { name: /submit a new book/i }))
      || await isVisible(page.getByRole("link", { name: /submit a new book/i }))
      || await isVisible(page.getByText(/submit a new book/i));
    const updateVisible = await isVisible(page.getByText(/update a previously submitted book/i));

    if (signInVisible || continueVisible || submitVisible || updateVisible || /authors\.apple\.com\/epub-upload/i.test(currentUrl)) {
      await capturePage(page, screenshotPath);
      return {
        detected: true,
        requiresLogin: signInVisible,
        currentUrl
      };
    }

    if (/appleid\.apple\.com|idmsa\.apple\.com|auth/i.test(currentUrl) && !announcedLoginWait) {
      writeLog(logPath, "Apple sign-in flow detected. Waiting for manual login and verification.");
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
    const submitVisible = await isVisible(page.getByRole("button", { name: /submit a new book/i }))
      || await isVisible(page.getByRole("link", { name: /submit a new book/i }))
      || await isVisible(page.getByText(/submit a new book/i));
    const updateVisible = await isVisible(page.getByText(/update a previously submitted book/i));
    const continueVisible = await isVisible(page.getByRole("button", { name: /^continue$/i }))
      || await isVisible(page.getByRole("link", { name: /^continue$/i }));
    const signInVisible = await isVisible(page.getByText(/sign in to itunes connect/i))
      || await isVisible(page.getByRole("button", { name: /sign in to itunes connect/i }))
      || await isVisible(page.getByRole("link", { name: /sign in to itunes connect/i }));

    if ((submitVisible || updateVisible || continueVisible) && !signInVisible) {
      await capturePage(page, screenshotPath);
      return {
        authenticated: true,
        currentUrl
      };
    }

    if (!announced) {
      writeLog(logPath, "Waiting for Apple Books sign-in to complete.");
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

async function advanceToSubmissionStart(page, logPath, screenshotPath) {
  const actions = [];

  const continued = await clickFirstVisibleLocator([
    page.getByRole("button", { name: /^continue$/i }),
    page.getByRole("link", { name: /^continue$/i })
  ], logPath, "continue");
  if (continued) {
    actions.push("continue");
    await page.waitForTimeout(2000);
    await capturePage(page, screenshotPath);
  }

  const submitted = await clickFirstVisibleLocator([
    page.getByRole("button", { name: /submit a new book/i }),
    page.getByRole("link", { name: /submit a new book/i }),
    page.getByText(/submit a new book/i)
  ], logPath, "submit-a-new-book");
  if (submitted) {
    actions.push("submit-a-new-book");
    await page.waitForTimeout(2500);
    await capturePage(page, screenshotPath);
  }

  return actions;
}

async function detectSubmissionSurface(page, logPath, screenshotPath, timeoutMs = 60000) {
  const startedAt = Date.now();

  while (Date.now() - startedAt < timeoutMs) {
    const currentUrl = page.url();
    const markers = [
      page.getByText(/upload your book/i),
      page.getByText(/cover art/i),
      page.getByText(/sample/i),
      page.getByText(/title and description/i),
      page.getByText(/publisher name/i),
      page.getByText(/interest age/i)
    ];

    for (const marker of markers) {
      if (await isVisible(marker)) {
        await capturePage(page, screenshotPath);
        writeLog(logPath, "Apple submission form detected.");
        return {
          detected: true,
          currentUrl
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
  const platformRoot = path.resolve(String(args["platform-root"] || ""));
  const metadataPath = path.resolve(String(args["metadata-path"] || ""));
  const packagePath = path.resolve(String(args["package-path"] || ""));
  const runRoot = path.resolve(String(args["run-root"] || ""));
  const resultPath = path.resolve(String(args["result-path"] || path.join(runRoot, "apple_result.json")));
  const sessionRoot = path.resolve(String(args["session-root"] || path.join(platformRoot, ".automation", "edge-profile")));
  const screenshotsRoot = path.join(runRoot, "screenshots");
  const screenshotPath = path.join(screenshotsRoot, "apple-portal.png");
  const logPath = path.join(runRoot, "session.log");

  ensureDir(runRoot);
  ensureDir(sessionRoot);
  ensureDir(screenshotsRoot);

  if (!fs.existsSync(metadataPath)) {
    throw new Error(`Apple metadata.json not found: ${metadataPath}`);
  }
  if (!fs.existsSync(packagePath)) {
    throw new Error(`Apple package file not found: ${packagePath}`);
  }

  const metadata = readJson(metadataPath);
  const packageData = readJson(packagePath);
  const playwright = tryLoadPlaywright();
  const edgePath = detectEdgePath();
  const files = collectFiles(platformRoot, packageData);

  const result = buildBaseResult({
    mode,
    metadata,
    packageData,
    platformRoot,
    resultPath,
    sessionRoot,
    screenshotPath,
    edgePath,
    playwrightLoaded: playwright,
    files
  });

  if (mode === "prepare") {
    result.state = packageData?.package_ready ? "prepared" : "blocked";
    result.next_step = result.playwright_available
      ? "Use -Mode draft or -Mode assist to open the Apple Books publishing portal."
      : "Install engine/automation dependencies with npm install before browser-assisted Apple runs.";
    result.notes = [
      "Apple prepare mode validates the package and Apple portal entry wiring.",
      "Official Apple flow uses the publishing portal to upload EPUB, cover art, sample, and metadata.",
      "Pricing and territory still need to be set later in iTunes Connect."
    ];
    writeJson(resultPath, result);
    writeLog(logPath, `Apple prepare completed: ${result.state}`);
    return;
  }

  if (!playwright) {
    result.state = "blocked";
    result.next_step = "Install automation dependencies with npm install before Apple draft/assist runs.";
    result.notes = [
      "playwright-core is not installed.",
      "Run npm install inside engine/automation and retry."
    ];
    writeJson(resultPath, result);
    writeLog(logPath, "Apple browser automation blocked because playwright-core is unavailable.");
    return;
  }

  if (!edgePath) {
    result.state = "blocked";
    result.next_step = "Install Microsoft Edge or set SAGEWRITE_BROWSER_PATH to a Chromium-based browser executable.";
    result.notes = [
      "Apple browser automation requires a local browser executable.",
      "No Edge path was detected on this machine."
    ];
    writeJson(resultPath, result);
    writeLog(logPath, "Apple browser automation blocked because no Edge executable was found.");
    return;
  }

  let context = null;
  let keepBrowserOpen = false;
  try {
    context = await playwright.chromium.launchPersistentContext(sessionRoot, {
      executablePath: edgePath,
      headless: false,
      viewport: null,
      args: ["--start-maximized"]
    });

    const existingPages = context.pages();
    const page = existingPages[0] || await context.newPage();
    result.executed_browser = true;

    await page.goto(result.target_urls.portal, {
      waitUntil: "domcontentloaded",
      timeout: 120000
    });
    await capturePage(page, screenshotPath);
    writeLog(logPath, "Opened Apple Books publishing portal.");

    const entryState = await waitForAppleEntry(page, logPath, screenshotPath);
    if (!entryState.detected) {
      result.state = "portal_timeout";
      result.next_step = "Open the screenshot and session log to see what blocked Apple portal detection.";
      result.notes = [
        "Could not detect the Apple Books portal entry state within the timeout."
      ];
      writeJson(resultPath, result);
      return;
    }

    if (entryState.requiresLogin) {
      const clicked = await clickFirstVisibleLocator([
        page.getByRole("button", { name: /sign in to itunes connect/i }),
        page.getByRole("link", { name: /sign in to itunes connect/i }),
        page.getByText(/sign in to itunes connect/i)
      ], logPath, "sign-in-to-itunes-connect");

      if (clicked) {
        await page.waitForTimeout(2000);
        await capturePage(page, screenshotPath);
      }

      const loginState = await waitForAuthenticatedPortal(page, logPath, screenshotPath);
      if (!loginState.authenticated) {
        result.state = "awaiting_login";
        result.next_step = "Finish Apple ID sign-in and any verification steps, then rerun with -ReuseSession.";
        result.notes = [
          "The Apple portal session was created and can be reused.",
          "Apple login and verification still require manual completion."
        ];
        writeJson(resultPath, result);
        keepBrowserOpen = true;
        return;
      }
    }

    const actions = await advanceToSubmissionStart(page, logPath, screenshotPath);
    const surface = await detectSubmissionSurface(page, logPath, screenshotPath);

    result.actions = actions;
    if (surface.detected) {
      result.state = mode === "assist" ? "assist_ready" : "draft_ready";
      result.next_step = mode === "assist"
        ? "Continue filling the Apple submission form, upload assets, and pause before final upload."
        : "Use the open portal session to complete the new-book draft in Apple Books.";
      result.notes = [
        "Apple portal entry and new-book flow were opened successfully.",
        "Metadata mapping is only partially automated in this phase; finish the remaining fields manually."
      ];
    } else {
      result.state = "portal_ready";
      result.next_step = "Use the open Apple session or rerun with -ReuseSession to continue from the portal home.";
      result.notes = [
        "The Apple Books portal opened successfully.",
        "The new-book form was not conclusively detected after the initial clicks."
      ];
    }

    writeJson(resultPath, result);
    writeLog(logPath, `Apple browser automation finished with state: ${result.state}`);
    keepBrowserOpen = ["assist_ready", "draft_ready", "portal_ready"].includes(result.state);
  } finally {
    if (context && keepBrowserOpen) {
      writeLog(logPath, "Keeping Apple browser session open for manual review. Close the browser when you are done.");
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
      try {
        await context.close();
      } catch {}
    }
  }
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
