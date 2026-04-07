"use strict";

const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const { spawn } = require("node:child_process");
const { randomUUID } = require("node:crypto");
const { URL } = require("node:url");

const PORT = Number(process.env.PORT || 3210);
const ENGINE_ROOT = path.resolve(__dirname, "..");
const CLAW_ROOT = path.resolve(ENGINE_ROOT, "..", "..");
const PUBLIC_DIR = path.join(__dirname, "public");

const jobs = new Map();

function getWorkspacePaths(bookName) {
  const workspacePath = path.join(CLAW_ROOT, `workspace-${bookName}`);
  const bookRoot = path.join(workspacePath, "sagewrite", "book");
  const logRoot = path.join(bookRoot, "logs");
  const outputRoot = path.join(bookRoot, "04_output");
  const webRunRoot = path.join(logRoot, "webui-runs");
  const webRunIndexPath = path.join(logRoot, "webui_runs.jsonl");

  return {
    workspacePath,
    bookRoot,
    logRoot,
    outputRoot,
    webRunRoot,
    webRunIndexPath
  };
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function formatLocalTimestamp(date = new Date()) {
  const pad = (value) => String(value).padStart(2, "0");
  return [
    date.getFullYear(),
    pad(date.getMonth() + 1),
    pad(date.getDate())
  ].join("-") + " " + [
    pad(date.getHours()),
    pad(date.getMinutes()),
    pad(date.getSeconds())
  ].join(":");
}

function formatFileStamp(date = new Date()) {
  return formatLocalTimestamp(date).replace(/[: ]/g, "-");
}

function appendJsonLine(filePath, payload) {
  ensureDir(path.dirname(filePath));
  fs.appendFileSync(filePath, `${JSON.stringify(payload)}\n`, "utf8");
}

function readJsonFile(filePath) {
  const raw = fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, "");
  return JSON.parse(raw);
}

function readJsonLines(filePath) {
  if (!fs.existsSync(filePath)) {
    return [];
  }

  return fs.readFileSync(filePath, "utf8")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      try {
        return JSON.parse(line);
      } catch {
        return null;
      }
    })
    .filter(Boolean);
}

function parseFrontMatterMarkdown(filePath) {
  if (!fs.existsSync(filePath)) {
    return null;
  }

  const content = fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, "");
  const match = content.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!match) {
    return null;
  }

  const data = {};
  match[1]
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .forEach((line) => {
      const colonIndex = line.indexOf(":");
      if (colonIndex <= 0) {
        return;
      }
      const key = line.slice(0, colonIndex).trim();
      const value = line.slice(colonIndex + 1).trim();
      data[key] = value;
    });

  return data;
}

function getChapterFiles(chapterRoot) {
  if (!fs.existsSync(chapterRoot)) {
    return [];
  }

  return fs.readdirSync(chapterRoot)
    .filter((name) => /^\d+\.md$/i.test(name))
    .sort((a, b) => {
      const aNumber = Number.parseInt(a, 10);
      const bNumber = Number.parseInt(b, 10);
      return aNumber - bNumber;
    });
}

function getChapterMetadata(chapterRoot) {
  return getChapterFiles(chapterRoot).map((fileName) => {
    const filePath = path.join(chapterRoot, fileName);
    const frontMatter = parseFrontMatterMarkdown(filePath) || {};
    return {
      fileName,
      chapterIndex: Number(frontMatter.chapter_index || Number.parseInt(fileName, 10) || 0),
      title: frontMatter.title || fileName
    };
  });
}

function deriveSummary(output, fallbackMessage) {
  const lines = output
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  return lines.at(-1) || fallbackMessage;
}

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store"
  });
  res.end(JSON.stringify(payload));
}

function sendText(res, statusCode, text, type = "text/plain; charset=utf-8") {
  res.writeHead(statusCode, {
    "Content-Type": type,
    "Cache-Control": "no-store"
  });
  res.end(text);
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    let raw = "";
    req.on("data", (chunk) => {
      raw += chunk;
      if (raw.length > 1_000_000) {
        reject(new Error("Request body too large."));
      }
    });
    req.on("end", () => {
      if (!raw.trim()) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(raw));
      } catch {
        reject(new Error("Invalid JSON body."));
      }
    });
    req.on("error", reject);
  });
}

function listWorkspaces() {
  if (!fs.existsSync(CLAW_ROOT)) {
    return [];
  }

  return fs.readdirSync(CLAW_ROOT, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && entry.name.startsWith("workspace-"))
    .map((entry) => {
      const bookName = entry.name.replace(/^workspace-/, "");
      const bookRoot = path.join(CLAW_ROOT, entry.name, "sagewrite", "book");
      const objectivePath = path.join(bookRoot, "00_brief", "objective.md");
      const tocPath = path.join(bookRoot, "01_outline", "toc.md");
      const toc2Path = path.join(bookRoot, "01_outline", "toc2.md");
      const chapterRoot = path.join(bookRoot, "02_chapters");
      const outputRoot = path.join(bookRoot, "04_output");
      const logRoot = path.join(bookRoot, "logs");
      const statusPath = path.join(logRoot, "status.json");
      const runLogPath = path.join(logRoot, "run_history.jsonl");
      const webRunIndexPath = path.join(logRoot, "webui_runs.jsonl");
      const editReportJsonPath = path.join(logRoot, "edit_report.json");
      const tocContent = fs.existsSync(tocPath)
        ? fs.readFileSync(tocPath, "utf8")
        : "";
      const chapterFiles = getChapterMetadata(chapterRoot);
      const chapterCount = chapterFiles.length;
      const outputs = fs.existsSync(outputRoot)
        ? fs.readdirSync(outputRoot).filter((name) => name.endsWith(".docx") && !name.startsWith("~$"))
        : [];
      let status = null;
      let recentRuns = [];
      let webRuns = [];
      let editReport = null;
      const objectiveData = parseFrontMatterMarkdown(objectivePath) || null;

      if (fs.existsSync(statusPath)) {
        try {
          status = readJsonFile(statusPath);
        } catch {
          status = {
            last_error: { message: "status.json unreadable" }
          };
        }
      }

      if (fs.existsSync(runLogPath)) {
        recentRuns = readJsonLines(runLogPath);
      }

      if (fs.existsSync(webRunIndexPath)) {
        webRuns = readJsonLines(webRunIndexPath);
      }

      if (fs.existsSync(editReportJsonPath)) {
        try {
          editReport = readJsonFile(editReportJsonPath);
        } catch {
          editReport = {
            error: "edit_report.json unreadable"
          };
        }
      }

      const mergedRuns = [...recentRuns, ...webRuns]
        .sort((a, b) => String(a.timestamp || "").localeCompare(String(b.timestamp || "")))
        .slice(-8);

      return {
        bookName,
        workspacePath: path.join(CLAW_ROOT, entry.name),
        hasObjective: fs.existsSync(objectivePath),
        objectiveData,
        hasToc: fs.existsSync(tocPath),
        hasExpandedToc: fs.existsSync(toc2Path),
        tocContent,
        chapterFiles,
        chapterCount,
        outputFiles: outputs,
        status,
        recentRuns: mergedRuns,
        editReport
      };
    })
    .sort((a, b) => a.bookName.localeCompare(b.bookName, "zh-Hans-CN"));
}

function serveStatic(reqPath, res) {
  const target = reqPath === "/" ? "/index.html" : reqPath;
  const filePath = path.normalize(path.join(PUBLIC_DIR, target));

  if (!filePath.startsWith(PUBLIC_DIR)) {
    sendText(res, 403, "Forbidden");
    return;
  }

  if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    sendText(res, 404, "Not found");
    return;
  }

  const ext = path.extname(filePath).toLowerCase();
  const types = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8"
  };

  sendText(res, 200, fs.readFileSync(filePath), types[ext] || "application/octet-stream");
}

function createJob(meta) {
  const id = randomUUID();
  const job = {
    id,
    status: "running",
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    meta,
    output: "",
    archived: false
  };
  jobs.set(id, job);
  return job;
}

function appendJobOutput(job, chunk) {
  job.output += chunk;
  job.updatedAt = new Date().toISOString();
}

function finishJob(job, exitCode) {
  job.status = exitCode === 0 ? "success" : "failed";
  job.exitCode = exitCode;
  job.updatedAt = new Date().toISOString();
  archiveJobOutput(job);
}

function failJob(job, error) {
  job.status = "failed";
  job.exitCode = -1;
  job.updatedAt = new Date().toISOString();
  job.output += `\n[webui-error] ${error.message}\n`;
  archiveJobOutput(job);
}

function archiveJobOutput(job) {
  if (job.archived) {
    return;
  }

  const bookName = job.meta?.bookName;
  if (!bookName) {
    job.archived = true;
    return;
  }

  try {
    const paths = getWorkspacePaths(bookName);
    ensureDir(paths.webRunRoot);
    const timestamp = formatLocalTimestamp();
    const fileName = `${formatFileStamp()}-${job.meta.route}-${job.id}.log`;
    const outputPath = path.join(paths.webRunRoot, fileName);
    fs.writeFileSync(outputPath, job.output || "", "utf8");

    const entry = {
      source: "webui",
      timestamp,
      step: job.meta.route,
      state: job.status,
      message: deriveSummary(job.output || "", `Web UI ${job.meta.route} ${job.status}.`),
      data: {
        exitCode: job.exitCode,
        outputFileName: fileName,
        outputPath
      }
    };

    appendJsonLine(paths.webRunIndexPath, entry);
    job.meta.outputFileName = fileName;
    job.meta.outputPath = outputPath;
    job.meta.archivedAt = timestamp;
    job.archived = true;
  } catch (error) {
    job.output += `\n[webui-archive-error] ${error.message}\n`;
    job.archived = true;
  }
}

function validateBookName(bookName) {
  if (!bookName || typeof bookName !== "string") {
    throw new Error("BookName is required.");
  }
  if (!/^[A-Za-z0-9_-]+$/.test(bookName)) {
    throw new Error("BookName only supports letters, numbers, underscores, and hyphens.");
  }
}

function validateOutputFileName(fileName) {
  if (!fileName || typeof fileName !== "string") {
    throw new Error("fileName is required.");
  }
  if (fileName !== path.basename(fileName)) {
    throw new Error("Invalid fileName.");
  }
  if (!/\.docx$/i.test(fileName)) {
    throw new Error("Only .docx output files can be opened.");
  }
}

function openFileWithDefaultApp(filePath) {
  const child = spawn("powershell.exe", [
    "-NoProfile",
    "-Command",
    "Start-Process -LiteralPath $args[0]",
    filePath
  ], {
    detached: true,
    stdio: "ignore"
  });

  child.unref();
}

function openFolder(folderPath) {
  const child = spawn("explorer.exe", [folderPath], {
    detached: true,
    stdio: "ignore"
  });

  child.unref();
}

function revealFileInExplorer(filePath) {
  const child = spawn("explorer.exe", ["/select,", filePath], {
    detached: true,
    stdio: "ignore"
  });

  child.unref();
}

function pushArg(args, flag, value) {
  if (value === undefined || value === null || value === "") {
    return;
  }
  args.push(flag, String(value));
}

function runScript(scriptName, params, meta) {
  const scriptPath = path.join(ENGINE_ROOT, scriptName);
  if (!fs.existsSync(scriptPath)) {
    throw new Error(`Script not found: ${scriptName}`);
  }

  const job = createJob(meta);
  const args = [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    scriptPath
  ];

  params.forEach((item) => {
    if (item.type === "switch") {
      if (item.enabled) {
        args.push(item.flag);
      }
      return;
    }
    pushArg(args, item.flag, item.value);
  });

  const child = spawn("powershell.exe", args, {
    cwd: ENGINE_ROOT,
    env: process.env
  });

  child.stdout.on("data", (chunk) => appendJobOutput(job, chunk.toString("utf8")));
  child.stderr.on("data", (chunk) => appendJobOutput(job, chunk.toString("utf8")));
  child.on("error", (error) => failJob(job, error));
  child.on("close", (code) => finishJob(job, code ?? -1));

  return job;
}

async function handleRun(route, body, res) {
  try {
    const bookName = body.bookName;
    validateBookName(bookName);

    let job;

    switch (route) {
      case "intake":
        [
          "title",
          "audience",
          "type",
          "coreThesis",
          "scope",
          "style"
        ].forEach((key) => {
          if (!body[key]) {
            throw new Error(`Missing field: ${key}`);
          }
        });
        job = runScript("01-intake.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Title", value: body.title },
          { flag: "-Audience", value: body.audience },
          { flag: "-Type", value: body.type },
          { flag: "-CoreThesis", value: body.coreThesis },
          { flag: "-Scope", value: body.scope },
          { flag: "-Style", value: body.style }
        ], { route, bookName });
        break;
      case "structure":
        job = runScript("02-structure.ps1", [
          { flag: "-BookName", value: bookName }
        ], { route, bookName });
        break;
      case "expand":
        if (body.mode === "chapter") {
          if (!body.chapter) {
            throw new Error("Chapter is required.");
          }
        }
        if (body.mode === "range") {
          if (!body.startChapter || !body.endChapter) {
            throw new Error("StartChapter and EndChapter are required.");
          }
        }
        job = runScript("02b-expand.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Chapter", value: body.mode === "chapter" ? body.chapter : undefined },
          { flag: "-StartChapter", value: body.mode === "range" ? body.startChapter : undefined },
          { flag: "-EndChapter", value: body.mode === "range" ? body.endChapter : undefined },
          { flag: "-MinSubsections", value: body.minSubsections || 3 },
          { flag: "-MaxSubsections", value: body.maxSubsections || 5 },
          { flag: "-Model", value: body.model || "gpt-4o-mini" },
          { flag: "-All", type: "switch", enabled: body.mode === "all" }
        ], { route, bookName });
        break;
      case "write":
        if (body.mode === "chapter" && !body.chapter) {
          throw new Error("Chapter is required.");
        }
        if (body.mode === "range" && (!body.startChapter || !body.endChapter)) {
          throw new Error("StartChapter and EndChapter are required.");
        }
        if (body.additionalInstructions && body.mode !== "chapter") {
          throw new Error("Additional instructions are only supported in single chapter mode.");
        }
        job = runScript("03-write.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Chapter", value: body.mode === "chapter" ? body.chapter : undefined },
          { flag: "-StartChapter", value: body.mode === "range" ? body.startChapter : undefined },
          { flag: "-EndChapter", value: body.mode === "range" ? body.endChapter : undefined },
          { flag: "-MaxTokens", value: body.maxTokens || 6000 },
          { flag: "-AdditionalInstructions", value: body.additionalInstructions || undefined },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], { route, bookName });
        break;
      case "edit":
        job = runScript("04-edit.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Strict", type: "switch", enabled: Boolean(body.strict) }
        ], { route, bookName });
        break;
      case "build":
        job = runScript("05-build.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-AutoNumber", type: "switch", enabled: Boolean(body.autoNumber) }
        ], { route, bookName });
        break;
      default:
        sendJson(res, 404, { error: "Unknown route." });
        return;
    }

    sendJson(res, 202, { jobId: job.id, status: job.status });
  } catch (error) {
    sendJson(res, 400, { error: error.message });
  }
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);

  if (req.method === "GET" && url.pathname === "/api/status") {
    sendJson(res, 200, {
      engineRoot: ENGINE_ROOT,
      clawRoot: CLAW_ROOT,
      hasOpenAIKey: Boolean(process.env.OPENAI_API_KEY),
      workspaces: listWorkspaces()
    });
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/open-output") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const fileName = body.fileName;

      validateBookName(bookName);
      validateOutputFileName(fileName);

      const paths = getWorkspacePaths(bookName);
      const outputPath = path.join(paths.outputRoot, fileName);

      if (!outputPath.startsWith(paths.outputRoot)) {
        sendJson(res, 400, { error: "Invalid output file path." });
        return;
      }

      if (!fs.existsSync(outputPath)) {
        sendJson(res, 404, { error: "Output document not found." });
        return;
      }

      openFileWithDefaultApp(outputPath);
      sendJson(res, 200, {
        opened: true,
        bookName,
        fileName
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/open-output-folder") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;

      validateBookName(bookName);

      const paths = getWorkspacePaths(bookName);
      if (!fs.existsSync(paths.outputRoot)) {
        sendJson(res, 404, { error: "Output folder not found." });
        return;
      }

      openFolder(paths.outputRoot);
      sendJson(res, 200, {
        opened: true,
        bookName
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/reveal-output") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const fileName = body.fileName;

      validateBookName(bookName);
      validateOutputFileName(fileName);

      const paths = getWorkspacePaths(bookName);
      const outputPath = path.join(paths.outputRoot, fileName);

      if (!outputPath.startsWith(paths.outputRoot)) {
        sendJson(res, 400, { error: "Invalid output file path." });
        return;
      }

      if (!fs.existsSync(outputPath)) {
        sendJson(res, 404, { error: "Output document not found." });
        return;
      }

      revealFileInExplorer(outputPath);
      sendJson(res, 200, {
        opened: true,
        bookName,
        fileName
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname.startsWith("/api/jobs/")) {
    const jobId = url.pathname.split("/").pop();
    const job = jobs.get(jobId);
    if (!job) {
      sendJson(res, 404, { error: "Job not found." });
      return;
    }
    sendJson(res, 200, job);
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/toc") {
    const bookName = url.searchParams.get("bookName");

    if (!bookName) {
      sendJson(res, 400, { error: "bookName is required." });
      return;
    }

    try {
      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);
      const tocPath = path.join(paths.bookRoot, "01_outline", "toc.md");

      if (!fs.existsSync(tocPath)) {
        sendJson(res, 404, { error: "toc.md not found." });
        return;
      }

      sendJson(res, 200, {
        bookName,
        tocContent: fs.readFileSync(tocPath, "utf8")
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/toc") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const tocContent = typeof body.tocContent === "string" ? body.tocContent : null;

      if (!bookName) {
        sendJson(res, 400, { error: "bookName is required." });
        return;
      }

      if (tocContent === null) {
        sendJson(res, 400, { error: "tocContent is required." });
        return;
      }

      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);
      const outlineRoot = path.join(paths.bookRoot, "01_outline");
      const tocPath = path.join(outlineRoot, "toc.md");

      ensureDir(outlineRoot);
      fs.writeFileSync(tocPath, tocContent, "utf8");

      sendJson(res, 200, {
        bookName,
        saved: true,
        tocContent
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/chapters") {
    const bookName = url.searchParams.get("bookName");

    if (!bookName) {
      sendJson(res, 400, { error: "bookName is required." });
      return;
    }

    try {
      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);
      const chapterRoot = path.join(paths.bookRoot, "02_chapters");
      sendJson(res, 200, {
        bookName,
        chapters: getChapterMetadata(chapterRoot)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/chapter") {
    const bookName = url.searchParams.get("bookName");
    const fileName = url.searchParams.get("fileName");

    if (!bookName || !fileName) {
      sendJson(res, 400, { error: "bookName and fileName are required." });
      return;
    }

    try {
      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);
      const chapterRoot = path.join(paths.bookRoot, "02_chapters");
      const safeFileName = path.basename(fileName);
      const targetPath = path.join(chapterRoot, safeFileName);

      if (!targetPath.startsWith(chapterRoot)) {
        sendJson(res, 403, { error: "Forbidden." });
        return;
      }

      if (!fs.existsSync(targetPath)) {
        sendJson(res, 404, { error: "Chapter file not found." });
        return;
      }

      sendJson(res, 200, {
        bookName,
        fileName: safeFileName,
        content: fs.readFileSync(targetPath, "utf8")
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/chapter") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const fileName = body.fileName;
      const content = typeof body.content === "string" ? body.content : null;

      if (!bookName || !fileName) {
        sendJson(res, 400, { error: "bookName and fileName are required." });
        return;
      }

      if (content === null) {
        sendJson(res, 400, { error: "content is required." });
        return;
      }

      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);
      const chapterRoot = path.join(paths.bookRoot, "02_chapters");
      const safeFileName = path.basename(fileName);
      const targetPath = path.join(chapterRoot, safeFileName);

      if (!targetPath.startsWith(chapterRoot)) {
        sendJson(res, 403, { error: "Forbidden." });
        return;
      }

      ensureDir(chapterRoot);
      fs.writeFileSync(targetPath, content, "utf8");

      sendJson(res, 200, {
        bookName,
        fileName: safeFileName,
        saved: true,
        content
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/run-output") {
    const bookName = url.searchParams.get("bookName");
    const fileName = url.searchParams.get("fileName");

    if (!bookName || !fileName) {
      sendJson(res, 400, { error: "bookName and fileName are required." });
      return;
    }

    try {
      validateBookName(bookName);
      const safeFileName = path.basename(fileName);
      const paths = getWorkspacePaths(bookName);
      const targetPath = path.join(paths.webRunRoot, safeFileName);

      if (!targetPath.startsWith(paths.webRunRoot)) {
        sendJson(res, 403, { error: "Forbidden." });
        return;
      }

      if (!fs.existsSync(targetPath)) {
        sendJson(res, 404, { error: "Run output not found." });
        return;
      }

      sendJson(res, 200, {
        bookName,
        fileName: safeFileName,
        content: fs.readFileSync(targetPath, "utf8")
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/edit-report") {
    const bookName = url.searchParams.get("bookName");

    if (!bookName) {
      sendJson(res, 400, { error: "bookName is required." });
      return;
    }

    try {
      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);
      const textPath = path.join(paths.logRoot, "edit_report.txt");
      const jsonPath = path.join(paths.logRoot, "edit_report.json");

      if (!fs.existsSync(textPath)) {
        sendJson(res, 404, { error: "edit_report.txt not found." });
        return;
      }

      let json = null;
      if (fs.existsSync(jsonPath)) {
        try {
          json = readJsonFile(jsonPath);
        } catch {
          json = null;
        }
      }

      sendJson(res, 200, {
        bookName,
        reportText: fs.readFileSync(textPath, "utf8"),
        reportJson: json
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname.startsWith("/api/run/")) {
    const route = url.pathname.split("/").pop();
    try {
      const body = await readJsonBody(req);
      await handleRun(route, body, res);
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET") {
    serveStatic(url.pathname, res);
    return;
  }

  sendJson(res, 405, { error: "Method not allowed." });
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`SageWrite Web UI running at http://127.0.0.1:${PORT}`);
});
