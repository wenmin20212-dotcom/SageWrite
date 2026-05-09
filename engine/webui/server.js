"use strict";

const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const { spawn, spawnSync } = require("node:child_process");
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
  const coverRoot = resolveCoverRoot(bookRoot, "ebook");
  const coverBriefRoot = path.join(coverRoot, "brief");
  const coverDraftRoot = path.join(coverRoot, "drafts");
  const coverReviewRoot = path.join(coverRoot, "reviews");
  const coverLayoutRoot = path.join(coverRoot, "layout");
  const coverMockupRoot = path.join(coverRoot, "mockup");
  const coverFinalRoot = path.join(coverRoot, "final");
  const coverCopyJsonPath = path.join(coverBriefRoot, "cover_copy.json");
  const coverCopyMdPath = path.join(coverBriefRoot, "cover_copy.md");
  const coverAssistantJsonPath = path.join(coverBriefRoot, "cover_assistant_last.json");
  const coverAssistantMdPath = path.join(coverBriefRoot, "cover_assistant_last.md");
  const frontmatterBaseRoot = path.join(bookRoot, "00_frontmatter");
  const frontmatterRoot = path.join(frontmatterBaseRoot, "ebook");
  const frontmatterManifestPath = path.join(frontmatterRoot, "frontmatter_manifest.json");
  const coverPagePath = path.join(frontmatterRoot, "cover_page.md");
  const titlePagePath = path.join(frontmatterRoot, "title_page.md");
  const copyrightPagePath = path.join(frontmatterRoot, "copyright_page.md");
  const webRunRoot = path.join(logRoot, "webui-runs");
  const webRunIndexPath = path.join(logRoot, "webui_runs.jsonl");

  return {
    workspacePath,
    bookRoot,
    logRoot,
    outputRoot,
    coverRoot,
    coverBriefRoot,
    coverDraftRoot,
    coverReviewRoot,
    coverLayoutRoot,
    coverMockupRoot,
    coverFinalRoot,
    coverCopyJsonPath,
    coverCopyMdPath,
    coverAssistantJsonPath,
    coverAssistantMdPath,
    frontmatterBaseRoot,
    frontmatterRoot,
    frontmatterManifestPath,
    coverPagePath,
    titlePagePath,
    copyrightPagePath,
    webRunRoot,
    webRunIndexPath
  };
}

function hasCoverArtifactsAt(root) {
  if (!fs.existsSync(root)) {
    return false;
  }

  const checks = [
    path.join(root, "brief", "cover_brief.json"),
    path.join(root, "brief", "cover_strategy.json"),
    path.join(root, "brief", "cover_copy.json"),
    path.join(root, "drafts"),
    path.join(root, "layout"),
    path.join(root, "mockup"),
    path.join(root, "final")
  ];

  return checks.some((item) => fs.existsSync(item));
}

function resolveCoverRoot(bookRoot, edition = "ebook") {
  const baseRoot = path.join(bookRoot, "07_cover");
  const editionRoot = path.join(baseRoot, edition);

  if (hasCoverArtifactsAt(editionRoot)) {
    return editionRoot;
  }

  if (edition === "ebook" && hasCoverArtifactsAt(baseRoot)) {
    return baseRoot;
  }

  return editionRoot;
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

function formatCompactFileStamp(date = new Date()) {
  const pad = (value) => String(value).padStart(2, "0");
  return [
    date.getFullYear(),
    pad(date.getMonth() + 1),
    pad(date.getDate()),
    pad(date.getHours()),
    pad(date.getMinutes()),
    pad(date.getSeconds())
  ].join("");
}

function getUniqueFileName(dirPath, preferredFileName, date = new Date()) {
  const safeFileName = path.basename(String(preferredFileName || "file"));
  const preferredPath = path.resolve(dirPath, safeFileName);
  const rootResolved = path.resolve(dirPath);
  if (!preferredPath.startsWith(rootResolved + path.sep)) {
    throw new Error("Invalid target file name.");
  }
  if (!fs.existsSync(preferredPath)) {
    return safeFileName;
  }
  const ext = path.extname(safeFileName);
  const stem = path.basename(safeFileName, ext);
  return `${stem}-${formatCompactFileStamp(date)}${ext}`;
}

function formatKdpFixReportWithHeader(reportText, { createdAt, bookName, source = {} } = {}) {
  const cleanOneLine = (value) => String(value || "").replace(/[\r\n]+/g, " ").trim();
  const sourceType = cleanOneLine(source.type || "");
  const sourceDirectory = cleanOneLine(source.directory || "");
  const sourceFileName = cleanOneLine(source.fileName || "");
  const sourceRelativePath = cleanOneLine(source.relativePath || "");
  const originalFileName = cleanOneLine(source.originalFileName || "");
  const header = [
    `# KDP 封面修改意见报告（生成时间：${createdAt}）`,
    "",
    `- BookName：${cleanOneLine(bookName) || "-"}`,
    `- 针对文件类型：${sourceType || "-"}`,
    `- 源文件目录：${sourceDirectory || "-"}`,
    `- 源文件名：${sourceFileName || "-"}`,
    `- 源文件路径：${sourceRelativePath || "-"}`,
    ...(originalFileName && originalFileName !== sourceFileName ? [`- 原始上传文件名：${originalFileName}`] : []),
    ""
  ];
  const body = String(reportText || "")
    .replace(/^# KDP 封面修改意见报告(?:（生成时间：\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}）)?\s*/u, "")
    .replace(/\n---\n生成时间：\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\s*$/u, "")
    .trimStart()
    .replace(/^(?:- (?:BookName|针对文件类型|源文件目录|源文件名|源文件路径|原始上传文件名)：[^\n]*\n)+\s*/u, "");
  return `${header.join("\n")}${body}`.trimEnd() + "\n";
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

function listFilesByExtensions(dirPath, extensions) {
  if (!fs.existsSync(dirPath)) {
    return [];
  }

  const normalized = extensions.map((ext) => ext.toLowerCase());
  return fs.readdirSync(dirPath)
    .filter((name) => {
      const ext = path.extname(name).toLowerCase();
      return normalized.includes(ext);
    })
    .sort((a, b) => a.localeCompare(b, "zh-Hans-CN"));
}

function listOutputDocuments(outputRoot) {
  if (!fs.existsSync(outputRoot)) {
    return [];
  }

  const results = [];
  const stack = [outputRoot];
  while (stack.length) {
    const current = stack.pop();
    const entries = fs.readdirSync(current, { withFileTypes: true });
    entries.forEach((entry) => {
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        if (entry.name.toLowerCase() === "back") {
          return;
        }
        stack.push(fullPath);
        return;
      }

      const ext = path.extname(entry.name).toLowerCase();
      if (entry.name.startsWith("~$")) {
        return;
      }
      if (![".docx", ".epub", ".pdf"].includes(ext)) {
        return;
      }

      results.push(path.relative(outputRoot, fullPath));
    });
  }

  return results.sort((a, b) => a.localeCompare(b, "zh-Hans-CN"));
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

function getCoverArtifacts(bookRoot) {
  const coverRoot = resolveCoverRoot(bookRoot, "ebook");
  const briefRoot = path.join(coverRoot, "brief");
  const draftRoot = path.join(coverRoot, "drafts");
  const reviewRoot = path.join(coverRoot, "reviews");
  const layoutRoot = path.join(coverRoot, "layout");
  const mockupRoot = path.join(coverRoot, "mockup");
  const finalRoot = path.join(coverRoot, "final");

  const reviewPath = path.join(reviewRoot, "cover_review.json");
  const reportPath = path.join(finalRoot, "cover_report.md");

  let review = null;
  if (fs.existsSync(reviewPath)) {
    try {
      review = readJsonFile(reviewPath);
    } catch {
      review = null;
    }
  }

  return {
    hasBrief: fs.existsSync(path.join(briefRoot, "cover_brief.json")),
    hasStrategy: fs.existsSync(path.join(briefRoot, "cover_strategy.json")),
    draftFiles: listFilesByExtensions(draftRoot, [".png", ".jpg", ".jpeg", ".webp"]),
    layoutFiles: listFilesByExtensions(layoutRoot, [".png", ".jpg", ".jpeg", ".webp"]),
    mockupFiles: listFilesByExtensions(mockupRoot, [".png", ".jpg", ".jpeg", ".webp"]),
    finalFiles: listFilesByExtensions(finalRoot, [".png", ".jpg", ".jpeg", ".webp", ".pdf"]),
    kdpAcceptance: getKdpAcceptanceState(bookRoot),
    next: getNextCoverArtifacts(bookRoot),
    selectedReviewFiles: Array.isArray(review?.selected_files) ? review.selected_files : [],
    topCandidate: review?.summary?.top_candidate || "",
    reportText: fs.existsSync(reportPath) ? fs.readFileSync(reportPath, "utf8") : ""
  };
}

function getKdpAcceptanceRoot(bookRoot) {
  return path.join(bookRoot, "07_cover", "kdp_acceptance");
}

function getKdpCurrentSourcePath(root) {
  return path.join(root, "kdp_current_source.json");
}

function buildKdpCurrentSource({ type, directory = "07_cover/kdp_acceptance", fileName, relativePath, originalFileName = "" }) {
  const cleanRelativePath = String(relativePath || fileName || "").replace(/\\/g, "/").replace(/^\/+/, "");
  const cleanFileName = path.basename(cleanRelativePath || String(fileName || ""));
  const cleanDirName = path.posix.dirname(cleanRelativePath);
  const displayDirectory = cleanDirName && cleanDirName !== "."
    ? `${directory}/${cleanDirName}`
    : directory;
  return {
    type: String(type || path.extname(cleanFileName).replace(".", "") || "").toUpperCase(),
    origin: "KDP acceptance directory",
    directory: displayDirectory,
    fileName: cleanFileName,
    relativePath: cleanRelativePath ? `07_cover/kdp_acceptance/${cleanRelativePath}` : "",
    acceptanceRelativePath: cleanRelativePath,
    originalFileName: String(originalFileName || "")
  };
}

function writeKdpCurrentSource(root, source) {
  ensureDir(root);
  const next = {
    ...source,
    updatedAt: formatLocalTimestamp()
  };
  writeJsonFile(getKdpCurrentSourcePath(root), next);
  return next;
}

function readKdpCurrentSource(root) {
  return readJsonFileSafe(getKdpCurrentSourcePath(root));
}

function getKdpEffectiveCurrentSource(root) {
  const saved = readKdpCurrentSource(root);
  if (saved) {
    return saved;
  }
  const workbench = getKdpFixWorkbenchState(root);
  if (workbench?.sourceFileName && fs.existsSync(path.join(getKdpFixWorkbenchRoot(root), "source", workbench.sourceFileName))) {
    return writeKdpCurrentSource(root, buildKdpCurrentSource({
      type: "PNG",
      fileName: `fix_workbench/source/${workbench.sourceFileName}`,
      relativePath: `fix_workbench/source/${workbench.sourceFileName}`
    }));
  }
  const pngFiles = listFilesByExtensions(root, [".png"]);
  if (pngFiles.length) {
    const newest = pngFiles
      .map((fileName) => {
        const filePath = path.join(root, fileName);
        return { fileName, mtime: fs.statSync(filePath).mtimeMs };
      })
      .sort((a, b) => b.mtime - a.mtime)[0];
    if (newest) {
      return writeKdpCurrentSource(root, buildKdpCurrentSource({
        type: "PNG",
        fileName: newest.fileName,
        relativePath: newest.fileName
      }));
    }
  }
  return null;
}

function getKdpLatestLlmTextRegionsState(root) {
  const visionRoot = path.join(root, "llm_text_regions");
  const latestPath = path.join(visionRoot, "latest_llm_text_regions.json");
  const latest = readJsonFileSafe(latestPath);
  if (!latest) {
    return {
      hasLatest: false,
      latest: null
    };
  }
  const latestSlim = {
    bookName: latest.bookName || "",
    createdAt: latest.createdAt || "",
    model: latest.model || "",
    image: latest.image || null,
    modelImage: latest.modelImage || null,
    coordinateScale: latest.coordinateScale || { x: 1, y: 1 },
    regions: Array.isArray(latest.regions) ? latest.regions : [],
    usage: latest.usage || null,
    responseId: latest.responseId || "",
    responseStatus: latest.responseStatus || "",
    saved: {
      resultFileName: path.basename(latestPath),
      imageFileName: latest.image?.fileName || "",
      latestFileName: "latest_llm_text_regions.json",
      resultRelativePath: "07_cover/kdp_acceptance/llm_text_regions/latest_llm_text_regions.json",
      imageRelativePath: latest.image?.fileName ? `07_cover/kdp_acceptance/llm_text_regions/${latest.image.fileName}` : "",
      latestRelativePath: "07_cover/kdp_acceptance/llm_text_regions/latest_llm_text_regions.json",
      resultPath: latestPath,
      imagePath: latest.image?.path || "",
      latestPath
    }
  };
  return {
    hasLatest: true,
    latest: latestSlim
  };
}

function getKdpLatestFixReportState(root) {
  const reportRoot = path.join(root, "fix_reports");
  const latestJsonPath = path.join(reportRoot, "latest_kdp_fix_report.json");
  const latestTextPath = path.join(reportRoot, "latest_kdp_fix_report.md");
  const latest = readJsonFileSafe(latestJsonPath);
  const reportText = readTextIfExists(latestTextPath);
  if (!latest && !reportText) {
    return {
      hasLatest: false,
      latest: null
    };
  }
  return {
    hasLatest: true,
    latest: {
      bookName: latest?.bookName || "",
      createdAt: latest?.createdAt || "",
      reportText: reportText || latest?.reportText || "",
      spec: latest?.spec || null,
      textRegionCount: latest?.textRegionCount || 0,
      saved: {
        resultFileName: path.basename(latestJsonPath),
        textFileName: path.basename(latestTextPath),
        resultPath: latestJsonPath,
        textPath: latestTextPath,
        latestPath: latestJsonPath,
        backupDir: path.join(reportRoot, "back")
      }
    }
  };
}

function getKdpFixWorkbenchRoot(root) {
  return path.join(root, "fix_workbench");
}

function getKdpFixWorkbenchState(root) {
  const workRoot = getKdpFixWorkbenchRoot(root);
  const sourceRoot = path.join(workRoot, "source");
  const outputRoot = path.join(workRoot, "output");
  const cropRoot = path.join(workRoot, "crops");
  const fillRoot = path.join(workRoot, "fills");
  const compositeRoot = path.join(workRoot, "composites");
  const pdfRoot = path.join(workRoot, "pdfs");
  const promptRoot = path.join(workRoot, "prompts");
  const statePath = path.join(workRoot, "workbench_state.json");
  const savedState = readJsonFileSafe(statePath) || {};
  return {
    hasState: Boolean(savedState && Object.keys(savedState).length),
    ...savedState,
    sourceFiles: listFilesByExtensions(sourceRoot, [".png", ".jpg", ".jpeg", ".webp"]),
    outputFiles: listFilesByExtensions(outputRoot, [".png", ".jpg", ".jpeg", ".webp"]),
    cropFiles: listFilesByExtensions(cropRoot, [".png", ".jpg", ".jpeg", ".webp"]),
    fillFiles: listFilesByExtensions(fillRoot, [".png", ".jpg", ".jpeg", ".webp"]),
    compositeFiles: listFilesByExtensions(compositeRoot, [".png", ".jpg", ".jpeg", ".webp"]),
    pdfFiles: listFilesByExtensions(pdfRoot, [".pdf"]),
    promptFiles: listFilesByExtensions(promptRoot, [".txt", ".md"]),
    roots: {
      workRoot,
      sourceRoot,
      outputRoot,
      cropRoot,
      fillRoot,
      compositeRoot,
      pdfRoot,
      promptRoot,
      statePath
    }
  };
}

function getKdpAcceptanceState(bookRoot) {
  const root = getKdpAcceptanceRoot(bookRoot);
  const reportPath = path.join(root, "kdp_acceptance_report.json");
  const reportTextPath = path.join(root, "kdp_acceptance_report.md");
  const report = readJsonFileSafe(reportPath);

  return {
    hasReport: Boolean(report),
    report,
    reportText: readTextIfExists(reportTextPath),
    currentSource: getKdpEffectiveCurrentSource(root),
    pdfFiles: listFilesByExtensions(root, [".pdf"]),
    llmTextRegions: getKdpLatestLlmTextRegionsState(root),
    fixReport: getKdpLatestFixReportState(root),
    fixWorkbench: getKdpFixWorkbenchState(root)
  };
}

function inchesToMm(value) {
  return Number((value * 25.4).toFixed(2));
}

function inchesToPoints(value) {
  return value * 72;
}

function normalizeNumber(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function getPaperbackSpineMultiplier(paperType) {
  switch (paperType) {
    case "bw-cream":
      return 0.0025;
    case "premium-color":
      return 0.002347;
    case "standard-color":
    case "bw-white":
    default:
      return 0.002252;
  }
}

function getPaperTypeLabel(paperType) {
  switch (paperType) {
    case "bw-cream":
      return "Black & white, cream paper";
    case "premium-color":
      return "Premium color paper";
    case "standard-color":
      return "Standard color paper";
    case "bw-white":
    default:
      return "Black & white, white paper";
  }
}

function buildKdpPaperbackCoverSpec(options = {}) {
  const trimWidthIn = normalizeNumber(options.trimWidthIn, 6);
  const trimHeightIn = normalizeNumber(options.trimHeightIn, 9);
  const bleedIn = normalizeNumber(options.bleedIn, 0.125);
  const pageCount = Math.max(1, Math.round(normalizeNumber(options.pageCount, 120)));
  const paperType = String(options.paperType || "bw-white");
  const multiplier = getPaperbackSpineMultiplier(paperType);
  const spineWidthIn = normalizeNumber(options.spineWidthIn, pageCount * multiplier);
  const coverWidthIn = bleedIn + trimWidthIn + spineWidthIn + trimWidthIn + bleedIn;
  const coverHeightIn = bleedIn + trimHeightIn + bleedIn;

  return {
    format: "paperback",
    trimWidthIn: Number(trimWidthIn.toFixed(3)),
    trimHeightIn: Number(trimHeightIn.toFixed(3)),
    bleedIn: Number(bleedIn.toFixed(3)),
    bleedMm: inchesToMm(bleedIn),
    pageCount,
    paperType,
    paperTypeLabel: getPaperTypeLabel(paperType),
    spineMultiplierIn: multiplier,
    spineWidthIn: Number(spineWidthIn.toFixed(3)),
    spineWidthMm: inchesToMm(spineWidthIn),
    expectedWidthIn: Number(coverWidthIn.toFixed(3)),
    expectedHeightIn: Number(coverHeightIn.toFixed(3)),
    expectedWidthPt: Number(inchesToPoints(coverWidthIn).toFixed(3)),
    expectedHeightPt: Number(inchesToPoints(coverHeightIn).toFixed(3)),
    expectedWidthMm: inchesToMm(coverWidthIn),
    expectedHeightMm: inchesToMm(coverHeightIn),
    spineTextAllowed: pageCount >= 79,
    formula: "Cover Width = Bleed + Back Cover Width + Spine Width + Front Cover Width + Bleed; Cover Height = Bleed + Trim Height + Bleed"
  };
}

function roundNumber(value, digits = 3) {
  return Number(Number(value || 0).toFixed(digits));
}

function buildKdpCoordinateMap(spec, dpi = 300) {
  const bleed = spec.bleedIn;
  const trimWidth = spec.trimWidthIn;
  const trimHeight = spec.trimHeightIn;
  const spine = spec.spineWidthIn;
  const fullWidth = spec.expectedWidthIn;
  const fullHeight = spec.expectedHeightIn;
  const safeInset = 0.125;
  const spineSafeInset = 0.0625;
  const barcodeWidth = 2;
  const barcodeHeight = 1.2;
  const barcodeInset = 0.25;
  const barcodeX = bleed + trimWidth - barcodeInset - barcodeWidth;
  const barcodeY = bleed + trimHeight - barcodeInset - barcodeHeight;
  const toPx = (value) => Math.round(value * dpi);
  const toMmValue = (value) => inchesToMm(value);
  const rect = (name, xIn, yIn, widthIn, heightIn, description) => ({
    name,
    description,
    inches: {
      x: roundNumber(xIn),
      y: roundNumber(yIn),
      width: roundNumber(widthIn),
      height: roundNumber(heightIn),
      right: roundNumber(xIn + widthIn),
      bottom: roundNumber(yIn + heightIn)
    },
    mm: {
      x: toMmValue(xIn),
      y: toMmValue(yIn),
      width: toMmValue(widthIn),
      height: toMmValue(heightIn),
      right: toMmValue(xIn + widthIn),
      bottom: toMmValue(yIn + heightIn)
    },
    px: {
      x: toPx(xIn),
      y: toPx(yIn),
      width: toPx(widthIn),
      height: toPx(heightIn),
      right: toPx(xIn + widthIn),
      bottom: toPx(yIn + heightIn)
    }
  });

  return {
    origin: "top-left of submitted PDF page",
    dpi,
    fullCover: rect("PDF full cover", 0, 0, fullWidth, fullHeight, "Submitted PDF page including bleed."),
    bleed: {
      leftIn: bleed,
      rightIn: bleed,
      topIn: bleed,
      bottomIn: bleed,
      leftPx: toPx(bleed),
      rightPx: toPx(bleed),
      topPx: toPx(bleed),
      bottomPx: toPx(bleed)
    },
    trimBox: rect("White trim box", bleed, bleed, (trimWidth * 2) + spine, trimHeight, "White dotted trim line / cut size after bleed is removed."),
    backCover: rect("Back cover trim", bleed, bleed, trimWidth, trimHeight, "Back cover final trim area."),
    spine: rect("Spine trim", bleed + trimWidth, bleed, spine, trimHeight, "Spine area between white spine-edge lines."),
    frontCover: rect("Front cover trim", bleed + trimWidth + spine, bleed, trimWidth, trimHeight, "Front cover final trim area."),
    backSafe: rect("Back cover red safe area", bleed + safeInset, bleed + safeInset, trimWidth - (safeInset * 2), trimHeight - (safeInset * 2), "Back cover text/logo safe area."),
    frontSafe: rect("Front cover red safe area", bleed + trimWidth + spine + safeInset, bleed + safeInset, trimWidth - (safeInset * 2), trimHeight - (safeInset * 2), "Front cover text/logo safe area."),
    spineSafe: rect("Spine red safe area", bleed + trimWidth + spineSafeInset, bleed + safeInset, Math.max(0, spine - (spineSafeInset * 2)), trimHeight - (safeInset * 2), "Spine text safe area."),
    barcodeBox: rect("KDP barcode box", barcodeX, barcodeY, barcodeWidth, barcodeHeight, "KDP automatic barcode reserve on the lower-right back cover: 2 x 1.2 in, 0.25 in from spine and bottom trim."),
    guideLines: {
      white: {
        trimLeftXIn: roundNumber(bleed),
        trimRightXIn: roundNumber(fullWidth - bleed),
        trimTopYIn: roundNumber(bleed),
        trimBottomYIn: roundNumber(fullHeight - bleed),
        spineLeftXIn: roundNumber(bleed + trimWidth),
        spineRightXIn: roundNumber(bleed + trimWidth + spine),
        trimLeftXPx: toPx(bleed),
        trimRightXPx: toPx(fullWidth - bleed),
        trimTopYPx: toPx(bleed),
        trimBottomYPx: toPx(fullHeight - bleed),
        spineLeftXPx: toPx(bleed + trimWidth),
        spineRightXPx: toPx(bleed + trimWidth + spine)
      },
      red: {
        safeLeftXIn: roundNumber(bleed + safeInset),
        safeRightXIn: roundNumber(fullWidth - bleed - safeInset),
        safeTopYIn: roundNumber(bleed + safeInset),
        safeBottomYIn: roundNumber(fullHeight - bleed - safeInset),
        spineSafeLeftXIn: roundNumber(bleed + trimWidth + spineSafeInset),
        spineSafeRightXIn: roundNumber(bleed + trimWidth + spine - spineSafeInset),
        safeLeftXPx: toPx(bleed + safeInset),
        safeRightXPx: toPx(fullWidth - bleed - safeInset),
        safeTopYPx: toPx(bleed + safeInset),
        safeBottomYPx: toPx(fullHeight - bleed - safeInset),
        spineSafeLeftXPx: toPx(bleed + trimWidth + spineSafeInset),
        spineSafeRightXPx: toPx(bleed + trimWidth + spine - spineSafeInset)
      }
    }
  };
}

function parsePdfBoxNumbers(match) {
  if (!match) {
    return null;
  }
  const values = match
    .slice(1, 5)
    .map((item) => Number.parseFloat(item));
  if (values.some((value) => !Number.isFinite(value))) {
    return null;
  }
  return values;
}

function extractPdfImageDpiCandidates(text, pdfWidthIn, pdfHeightIn) {
  const candidates = [];
  const imageRegex = /<<[\s\S]{0,2500}?\/Subtype\s*\/Image[\s\S]{0,2500}?>>/g;
  const matches = text.match(imageRegex) || [];

  matches.forEach((block) => {
    const width = Number.parseFloat(block.match(/\/Width\s+(\d+(?:\.\d+)?)/)?.[1] || "");
    const height = Number.parseFloat(block.match(/\/Height\s+(\d+(?:\.\d+)?)/)?.[1] || "");
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
      return;
    }

    candidates.push({
      pixelWidth: Math.round(width),
      pixelHeight: Math.round(height),
      ifFullPageDpiX: Number((width / pdfWidthIn).toFixed(1)),
      ifFullPageDpiY: Number((height / pdfHeightIn).toFixed(1)),
      ifFullPageMinDpi: Number((Math.min(width / pdfWidthIn, height / pdfHeightIn)).toFixed(1))
    });
  });

  return candidates.sort((a, b) => (b.pixelWidth * b.pixelHeight) - (a.pixelWidth * a.pixelHeight));
}

function parsePdfInfo(filePath) {
  const buffer = fs.readFileSync(filePath);
  const text = buffer.toString("latin1");
  const version = text.match(/%PDF-(\d+(?:\.\d+)?)/)?.[1] || "";
  const pageMatches = text.match(/\/Type\s*\/Page\b(?!s)/g) || [];
  const mediaBox = parsePdfBoxNumbers(text.match(/\/MediaBox\s*\[\s*(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s*\]/));
  const cropBox = parsePdfBoxNumbers(text.match(/\/CropBox\s*\[\s*(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s*\]/));
  const box = mediaBox || cropBox;
  if (!box) {
    throw new Error("Could not read PDF MediaBox or CropBox.");
  }

  const widthPt = Math.abs(box[2] - box[0]);
  const heightPt = Math.abs(box[3] - box[1]);
  const widthIn = widthPt / 72;
  const heightIn = heightPt / 72;
  const pageCount = pageMatches.length || null;
  const imageDpiCandidates = extractPdfImageDpiCandidates(text, widthIn, heightIn);

  return {
    version,
    pageCount,
    encrypted: /\/Encrypt\b/.test(text),
    hasAcroForm: /\/AcroForm\b/.test(text),
    hasCropBox: Boolean(cropBox),
    boxType: mediaBox ? "MediaBox" : "CropBox",
    widthPt: Number(widthPt.toFixed(3)),
    heightPt: Number(heightPt.toFixed(3)),
    widthIn: Number(widthIn.toFixed(3)),
    heightIn: Number(heightIn.toFixed(3)),
    widthMm: inchesToMm(widthIn),
    heightMm: inchesToMm(heightIn),
    imageDpiCandidates,
    largestImage: imageDpiCandidates[0] || null,
    fileSizeBytes: buffer.length
  };
}

function makeKdpCheck(status, title, detail) {
  return { status, title, detail };
}

function buildKdpAcceptanceReport({ bookName, pdfFileName, pdfPath, pdfInfo, spec }) {
  const toleranceIn = 0.01;
  const widthDelta = Number((pdfInfo.widthIn - spec.expectedWidthIn).toFixed(3));
  const heightDelta = Number((pdfInfo.heightIn - spec.expectedHeightIn).toFixed(3));
  const spineSafeWidthIn = Math.max(0, spec.spineWidthIn - 0.125);
  const requiredPixelWidth = Math.ceil(spec.expectedWidthIn * 300);
  const requiredPixelHeight = Math.ceil(spec.expectedHeightIn * 300);
  const coordinateMap = buildKdpCoordinateMap(spec, 300);
  const checks = [];

  checks.push(makeKdpCheck(
    "pass",
    "PDF file accepted for inspection",
    `${pdfFileName} (${Math.round(pdfInfo.fileSizeBytes / 1024)} KB)`
  ));

  if (pdfInfo.encrypted) {
    checks.push(makeKdpCheck("fail", "PDF is encrypted", "KDP print files should be upload-ready without password protection."));
  } else {
    checks.push(makeKdpCheck("pass", "PDF is not encrypted", "No /Encrypt marker was found."));
  }

  if (pdfInfo.pageCount === 1) {
    checks.push(makeKdpCheck("pass", "Cover PDF is one page", "A wraparound paperback cover should be submitted as one continuous cover PDF."));
  } else if (pdfInfo.pageCount) {
    checks.push(makeKdpCheck("fail", "Cover PDF is not one page", `Detected ${pdfInfo.pageCount} page objects.`));
  } else {
    checks.push(makeKdpCheck("warn", "Page count could not be confirmed", "The PDF dimensions were readable, but page object counting was inconclusive."));
  }

  if (Math.abs(widthDelta) <= toleranceIn && Math.abs(heightDelta) <= toleranceIn) {
    checks.push(makeKdpCheck(
      "pass",
      "Full cover size matches KDP formula",
      `PDF ${pdfInfo.widthIn} x ${pdfInfo.heightIn} in; expected ${spec.expectedWidthIn} x ${spec.expectedHeightIn} in.`
    ));
  } else {
    checks.push(makeKdpCheck(
      "fail",
      "Full cover size does not match KDP formula",
      `PDF ${pdfInfo.widthIn} x ${pdfInfo.heightIn} in; expected ${spec.expectedWidthIn} x ${spec.expectedHeightIn} in; delta ${widthDelta} x ${heightDelta} in.`
    ));
  }

  if (Math.abs(spec.bleedIn - 0.125) <= 0.001) {
    checks.push(makeKdpCheck("pass", "Bleed setting is KDP standard", "0.125 in / 3.2 mm bleed is required for covers."));
  } else {
    checks.push(makeKdpCheck("warn", "Bleed setting is not the usual KDP value", `Current bleed is ${spec.bleedIn} in. KDP cover guidance uses 0.125 in.`));
  }

  const largestImage = pdfInfo.largestImage;
  if (largestImage) {
    if (largestImage.ifFullPageMinDpi >= 300) {
      checks.push(makeKdpCheck(
        "pass",
        "Largest embedded image meets 300 DPI if used full-page",
        `Largest image is ${largestImage.pixelWidth} x ${largestImage.pixelHeight} px; full-cover requirement is about ${requiredPixelWidth} x ${requiredPixelHeight} px.`
      ));
    } else {
      checks.push(makeKdpCheck(
        "fail",
        "Largest embedded image may be below 300 DPI",
        `Largest image is ${largestImage.pixelWidth} x ${largestImage.pixelHeight} px, about ${largestImage.ifFullPageDpiX} x ${largestImage.ifFullPageDpiY} DPI if it spans the full cover. Full-cover target is at least ${requiredPixelWidth} x ${requiredPixelHeight} px.`
      ));
    }
  } else {
    checks.push(makeKdpCheck(
      "review",
      "300 DPI image resolution could not be verified",
      `KDP expects cover/manuscript images to be at least 300 DPI. For this cover size, a full-cover raster image should be at least ${requiredPixelWidth} x ${requiredPixelHeight} px. No embedded raster image dimensions were detected, so inspect the source/export settings.`
    ));
  }

  if (spec.spineTextAllowed) {
    checks.push(makeKdpCheck("info", "Spine text allowed by page count", `${spec.pageCount} pages is at least 79 pages; spine safe text width is about ${spineSafeWidthIn.toFixed(3)} in / ${inchesToMm(spineSafeWidthIn)} mm.`));
  } else {
    checks.push(makeKdpCheck("warn", "Spine text risk", "KDP only prints spine text on books with 79 pages or more."));
  }

  checks.push(makeKdpCheck(
    "review",
    "Spine text visual safety must be checked",
    "The file can pass size checks while still failing visually. Spine title, author, logo, and publisher marks must sit fully between the red spine safety lines and must not touch the white spine-edge/trim lines."
  ));
  checks.push(makeKdpCheck(
    "review",
    "Front/back text safe-zone review required",
    "All important text, logos, and barcode content must stay inside the red safe margin. Background art may extend to the PDF edge/bleed area."
  ));
  checks.push(makeKdpCheck(
    "manual",
    "Other manual visual checks still needed",
    "Confirm no white border, no crop marks, flattened layers, embedded fonts or rasterized text quality issues, readable text, and correct barcode area."
  ));

  const hasFail = checks.some((item) => item.status === "fail");
  const hasWarn = checks.some((item) => item.status === "warn");
  const hasReview = checks.some((item) => item.status === "review" || item.status === "manual");
  const technicalVerdict = hasFail ? "fail" : hasWarn ? "review" : "pass";
  const verdict = hasFail ? "fail" : hasWarn || hasReview ? "review" : "pass";

  return {
    generatedAt: formatLocalTimestamp(),
    bookName,
    pdfFileName,
    pdfPath,
    verdict,
    technicalVerdict,
    visualReviewRequired: hasReview,
    requiredResolution: {
      dpi: 300,
      fullCoverPixelWidth: requiredPixelWidth,
      fullCoverPixelHeight: requiredPixelHeight
    },
    coordinateMap,
    spec,
    pdf: pdfInfo,
    deltas: {
      widthIn: widthDelta,
      heightIn: heightDelta,
      toleranceIn
    },
    checks,
    sources: [
      {
        label: "Amazon KDP Paperback Submission Guidelines",
        url: "https://kdp.amazon.com/en_US/help/topic/G201857950"
      },
      {
        label: "Amazon KDP Fix Paperback and Hardcover Formatting Issues",
        url: "https://kdp.amazon.com/en_US/help/topic/G201834260"
      }
    ]
  };
}

function buildKdpAcceptanceMarkdown(report) {
  const statusLabel = {
    pass: "PASS",
    fail: "FAIL",
    warn: "WARN",
    review: "REVIEW",
    info: "INFO",
    manual: "MANUAL"
  };
  const lines = [];
  lines.push("# KDP Acceptance Report");
  lines.push("");
  lines.push(`- BookName: ${report.bookName}`);
  lines.push(`- PDF: ${report.pdfFileName}`);
  lines.push(`- Verdict: ${statusLabel[report.verdict] || report.verdict}`);
  lines.push(`- Technical size verdict: ${statusLabel[report.technicalVerdict] || report.technicalVerdict || "unknown"}`);
  lines.push(`- Visual review required: ${report.visualReviewRequired ? "yes" : "no"}`);
  lines.push(`- Generated: ${report.generatedAt}`);
  lines.push("");
  lines.push("## Expected Cover Size");
  lines.push("");
  lines.push(`- Trim: ${report.spec.trimWidthIn} x ${report.spec.trimHeightIn} in`);
  lines.push(`- Page count: ${report.spec.pageCount}`);
  lines.push(`- Paper: ${report.spec.paperTypeLabel}`);
  lines.push(`- Spine: ${report.spec.spineWidthIn} in / ${report.spec.spineWidthMm} mm`);
  lines.push(`- Bleed: ${report.spec.bleedIn} in / ${report.spec.bleedMm} mm`);
  lines.push(`- Full cover: ${report.spec.expectedWidthIn} x ${report.spec.expectedHeightIn} in`);
  lines.push(`- Full cover: ${report.spec.expectedWidthMm} x ${report.spec.expectedHeightMm} mm`);
  lines.push("");
  lines.push("## Uploaded PDF");
  lines.push("");
  lines.push(`- Page box: ${report.pdf.boxType}`);
  lines.push(`- Page count: ${report.pdf.pageCount || "unknown"}`);
  lines.push(`- Size: ${report.pdf.widthIn} x ${report.pdf.heightIn} in`);
  lines.push(`- Size: ${report.pdf.widthMm} x ${report.pdf.heightMm} mm`);
  lines.push(`- Delta: ${report.deltas.widthIn} x ${report.deltas.heightIn} in`);
  lines.push(`- Required raster baseline: ${report.requiredResolution.fullCoverPixelWidth} x ${report.requiredResolution.fullCoverPixelHeight} px at ${report.requiredResolution.dpi} DPI`);
  if (report.pdf.largestImage) {
    lines.push(`- Largest embedded image: ${report.pdf.largestImage.pixelWidth} x ${report.pdf.largestImage.pixelHeight} px`);
    lines.push(`- Largest image full-page effective DPI: ${report.pdf.largestImage.ifFullPageDpiX} x ${report.pdf.largestImage.ifFullPageDpiY}`);
  } else {
    lines.push("- Largest embedded image: not detected");
  }
  lines.push("");
  lines.push("## PDF Coordinate Map");
  lines.push("");
  lines.push(`- Origin: ${report.coordinateMap.origin}`);
  lines.push(`- Coordinate DPI: ${report.coordinateMap.dpi}`);
  [
    report.coordinateMap.fullCover,
    report.coordinateMap.trimBox,
    report.coordinateMap.backCover,
    report.coordinateMap.spine,
    report.coordinateMap.frontCover,
    report.coordinateMap.backSafe,
    report.coordinateMap.spineSafe,
    report.coordinateMap.frontSafe
  ].forEach((item) => {
    lines.push(`- ${item.name}: ${item.inches.width} x ${item.inches.height} in; x=${item.inches.x}, y=${item.inches.y}; px x=${item.px.x}, y=${item.px.y}, w=${item.px.width}, h=${item.px.height}`);
  });
  lines.push("");
  lines.push("## Checks");
  lines.push("");
  report.checks.forEach((check) => {
    lines.push(`- [${statusLabel[check.status] || check.status}] ${check.title}: ${check.detail}`);
  });
  lines.push("");
  lines.push("## KDP Sources");
  report.sources.forEach((source) => {
    lines.push(`- ${source.label}: ${source.url}`);
  });
  return `${lines.join("\r\n")}\r\n`;
}

function extractResponseText(response) {
  if (typeof response?.output_text === "string") {
    return response.output_text;
  }
  const parts = [];
  (response?.output || []).forEach((item) => {
    (item?.content || []).forEach((content) => {
      if (typeof content?.text === "string") {
        parts.push(content.text);
      }
    });
  });
  return parts.join("\n").trim();
}

function parseJsonFromModelText(text) {
  const raw = String(text || "").trim();
  if (!raw) {
    throw new Error("Model returned empty text.");
  }
  try {
    return JSON.parse(raw);
  } catch {
    const match = raw.match(/```(?:json)?\s*([\s\S]*?)```/) || raw.match(/(\{[\s\S]*\})/);
    if (!match) {
      throw new Error("Model did not return JSON.");
    }
    return JSON.parse(match[1]);
  }
}

function normalizeVisionRegion(region, index, imageWidth, imageHeight, coordinateScale = { x: 1, y: 1 }) {
  const rawX = Number(region.x ?? region.left ?? 0);
  const rawY = Number(region.y ?? region.top ?? 0);
  const rawWidth = Number(region.width ?? region.w ?? 0);
  const rawHeight = Number(region.height ?? region.h ?? 0);
  const rawRight = Number(region.right ?? (rawX + rawWidth));
  const rawBottom = Number(region.bottom ?? (rawY + rawHeight));
  const x = Math.max(0, Math.round(rawX * coordinateScale.x));
  const y = Math.max(0, Math.round(rawY * coordinateScale.y));
  const width = Math.max(0, Math.round(rawWidth * coordinateScale.x));
  const height = Math.max(0, Math.round(rawHeight * coordinateScale.y));
  const scaledRight = rawRight * coordinateScale.x;
  const scaledBottom = rawBottom * coordinateScale.y;
  const finalRight = Math.min(imageWidth, Math.round(Number.isFinite(scaledRight) ? scaledRight : (x + width)));
  const finalBottom = Math.min(imageHeight, Math.round(Number.isFinite(scaledBottom) ? scaledBottom : (y + height)));
  const normalizedWidth = Math.max(0, finalRight - x || width);
  const normalizedHeight = Math.max(0, finalBottom - y || height);

  return {
    id: String(region.id || `llm-${index + 1}`),
    zone: "unclassified",
    text: String(region.text || "").trim(),
    confidence: Number(Number(region.confidence ?? 0.75).toFixed(2)),
    orientation: String(region.orientation || "unknown"),
    x,
    y,
    width: normalizedWidth,
    height: normalizedHeight,
    right: Math.min(imageWidth, x + normalizedWidth),
    bottom: Math.min(imageHeight, y + normalizedHeight),
    source: "llm_vision",
    notes: String(region.notes || ""),
    raw: {
      x: rawX,
      y: rawY,
      width: rawWidth,
      height: rawHeight,
      right: rawRight,
      bottom: rawBottom
    },
    coordinateScale: {
      x: coordinateScale.x,
      y: coordinateScale.y
    }
  };
}

function getNextCoverArtifacts(bookRoot, edition = "ebook") {
  const nextRoot = path.join(bookRoot, "07_cover", "next", edition);
  const nextPrintRoot = path.join(bookRoot, "07_cover", "next", "print");
  const baseRoot = path.join(nextRoot, "base");
  const promptRoot = path.join(nextRoot, "prompts");
  const importRoot = path.join(nextRoot, "imports");
  const reviewRoot = path.join(nextRoot, "reviews");
  const layoutRoot = path.join(nextRoot, "layout");
  const printRoot = path.join(nextPrintRoot, "print_spread");
  const mockupRoot = path.join(nextRoot, "mockup");
  const finalRoot = path.join(nextRoot, "final");
  const finalReportPath = path.join(finalRoot, "next_cover_report.md");
  const promptReportPath = path.join(promptRoot, "midjourney_prompt_report.md");
  const imageEditReportPath = path.join(layoutRoot, "ai_image_edit_report.md");
  const reportParts = [promptReportPath, imageEditReportPath, finalReportPath]
    .filter((item) => fs.existsSync(item))
    .map((item) => fs.readFileSync(item, "utf8"));

  return {
    edition,
    hasBaseBrief: fs.existsSync(path.join(baseRoot, "base_brief.json")),
    hasPrompts: fs.existsSync(path.join(promptRoot, "base_prompts.json")) ||
      fs.existsSync(path.join(promptRoot, "midjourney_prompt.txt")),
    hasReview: fs.existsSync(path.join(reviewRoot, "base_review.json")),
    importFiles: listFilesByExtensions(importRoot, [".png", ".jpg", ".jpeg", ".webp"]),
    layoutFiles: listFilesByExtensions(layoutRoot, [".png", ".jpg", ".jpeg", ".webp"]),
    printSpreadFiles: listFilesByExtensions(printRoot, [".png", ".jpg", ".jpeg", ".webp", ".pdf"]),
    mockupFiles: listFilesByExtensions(mockupRoot, [".png", ".jpg", ".jpeg", ".webp"]),
    finalFiles: listFilesByExtensions(finalRoot, [".png", ".jpg", ".jpeg", ".webp", ".pdf"]),
    reportText: reportParts.join("\r\n\r\n---\r\n\r\n")
  };
}

function getLatestFileByExtensions(dirPath, extensions) {
  if (!fs.existsSync(dirPath)) {
    return "";
  }

  const normalized = extensions.map((ext) => ext.toLowerCase());
  const files = fs.readdirSync(dirPath, { withFileTypes: true })
    .filter((entry) => entry.isFile() && normalized.includes(path.extname(entry.name).toLowerCase()))
    .map((entry) => {
      const fullPath = path.join(dirPath, entry.name);
      return { name: entry.name, mtime: fs.statSync(fullPath).mtimeMs };
    })
    .sort((a, b) => b.mtime - a.mtime);

  return files[0]?.name || "";
}

function getCoverWorkbenchState(bookRoot, edition = "ebook") {
  const nextRoot = path.join(bookRoot, "07_cover", "next", edition);
  const promptRoot = path.join(nextRoot, "prompts");
  const importRoot = path.join(nextRoot, "imports");
  const layoutRoot = path.join(nextRoot, "layout");
  const oldCoverRoot = resolveCoverRoot(bookRoot, "ebook");
  const oldBriefRoot = path.join(oldCoverRoot, "brief");
  const statePath = path.join(nextRoot, "workbench_state.json");
  const promptPath = path.join(promptRoot, "midjourney_prompt.txt");
  const legacyPromptPath = path.join(oldBriefRoot, "cover_midjourney_prompt.txt");
  const assistantJsonPath = path.join(oldBriefRoot, "cover_assistant_last.json");
  const assistantMdPath = path.join(oldBriefRoot, "cover_assistant_last.md");
  const imageEditReportPath = path.join(layoutRoot, "ai_image_edit_report.json");
  const savedState = readJsonFileSafe(statePath) || {};
  const imageEditReport = readJsonFileSafe(imageEditReportPath) || {};
  const importFiles = listFilesByExtensions(importRoot, [".png", ".jpg", ".jpeg", ".webp"]);

  const latestImport = savedState.latest_import_file ||
    getLatestFileByExtensions(importRoot, [".png", ".jpg", ".jpeg", ".webp"]);
  const selectedImport = importFiles.includes(savedState.selected_import_file)
    ? savedState.selected_import_file
    : latestImport;
  const latestEdited = savedState.latest_edited_file ||
    path.basename(String(imageEditReport.output_image || "")) ||
    getLatestFileByExtensions(layoutRoot, [".png", ".jpg", ".jpeg", ".webp"]);

  return {
    edition,
    prompt: readTextIfExists(promptPath) || readTextIfExists(legacyPromptPath),
    assistantRequest: savedState.assistant_request || "",
    assistantResponse: readTextIfExists(assistantMdPath),
    assistantResult: readJsonFileSafe(assistantJsonPath),
    editText: savedState.edit_text || imageEditReport.cover_text?.raw || "",
    publisher: savedState.publisher || imageEditReport.cover_text?.publisher || "",
    imageModel: savedState.image_model || imageEditReport.image_model || "gpt-image-1.5",
    importFiles,
    selectedImportFile: selectedImport,
    latestImportFile: latestImport,
    latestEditedFile: latestEdited,
    statePath,
    imageEditReport
  };
}

function getFrontmatterPayload(paths) {
  const readText = (filePath) => (fs.existsSync(filePath) ? fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, "") : "");
  let manifest = null;
  if (fs.existsSync(paths.frontmatterManifestPath)) {
    try {
      manifest = readJsonFile(paths.frontmatterManifestPath);
    } catch {
      manifest = null;
    }
  }

  return {
    manifest,
    coverPage: readText(paths.coverPagePath),
    titlePage: readText(paths.titlePagePath),
    copyrightPage: readText(paths.copyrightPagePath)
  };
}

function listDirectories(dirPath) {
  if (!fs.existsSync(dirPath)) {
    return [];
  }

  return fs.readdirSync(dirPath, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort((a, b) => a.localeCompare(b, "zh-Hans-CN"));
}

function listDirectFiles(dirPath) {
  if (!fs.existsSync(dirPath)) {
    return [];
  }

  return fs.readdirSync(dirPath, { withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => entry.name)
    .sort((a, b) => a.localeCompare(b, "zh-Hans-CN"));
}

function readTextIfExists(filePath) {
  if (!fs.existsSync(filePath)) {
    return "";
  }
  return fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, "");
}

function readJsonFileSafe(filePath) {
  if (!fs.existsSync(filePath)) {
    return null;
  }

  try {
    return readJsonFile(filePath);
  } catch {
    return null;
  }
}

function getStringValue(value) {
  if (value === undefined || value === null) {
    return "";
  }
  return String(value).trim();
}

function getStringArray(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .map((item) => getStringValue(item))
    .filter(Boolean);
}

function uniqueStrings(values) {
  return [...new Set(values.map((item) => getStringValue(item)).filter(Boolean))];
}

function joinClause(values, limit = 6) {
  return uniqueStrings(values).slice(0, limit).join(", ");
}

function buildCoverMidjourneyPrompt(paths, overrides = {}) {
  const briefPath = path.join(paths.coverBriefRoot, "cover_brief.json");
  const strategyPath = path.join(paths.coverBriefRoot, "cover_strategy.json");
  const brief = readJsonFileSafe(briefPath) || {};
  const strategy = readJsonFileSafe(strategyPath) || {};
  const copy = readJsonFileSafe(paths.coverCopyJsonPath) || {};

  const title =
    getStringValue(overrides.title) ||
    getStringValue(brief.cover_text?.title) ||
    getStringValue(strategy.cover_text?.title);
  const subtitle =
    getStringValue(overrides.subtitle) ||
    getStringValue(copy.selected?.subtitle) ||
    getStringValue(brief.cover_text?.subtitle) ||
    getStringValue(strategy.cover_text?.subtitle);
  const author =
    getStringValue(overrides.author) ||
    getStringValue(brief.cover_text?.author) ||
    getStringValue(strategy.cover_text?.author);

  const metadata = brief.metadata || {};
  const positioning = brief.positioning || {};
  const primary = strategy.primary_strategy || {};
  const promptPackage = strategy.generation_plan?.prompt_package || {};
  const routePrompts = Array.isArray(promptPackage.route_prompts) ? promptPackage.route_prompts : [];
  const routePrompt =
    routePrompts.find((item) => getStringValue(item.route_id) === getStringValue(primary.route_id)) ||
    routePrompts[0] ||
    null;

  const visualDirection = joinClause([
    ...getStringArray(primary.main_visual),
    ...getStringArray(brief.design_directions?.[0]?.visual_keywords)
  ], 8);
  const colorDirection = joinClause([
    ...getStringArray(primary.color_direction),
    ...getStringArray(brief.design_directions?.[0]?.palette)
  ], 6);
  const moodDirection = joinClause([
    ...getStringArray(positioning.reader_impression),
    ...getStringArray(brief.design_directions?.[0]?.mood_keywords)
  ], 8);
  const topKeywords = joinClause(getStringArray(metadata.top_keywords), 8);
  const negativePrompt = joinClause([
    ...getStringArray(promptPackage.negative_prompt),
    ...getStringArray(positioning.avoid),
    "text",
    "typography",
    "letters",
    "subtitle",
    "author name",
    "watermark",
    "logo"
  ], 16);

  const clauses = [
    "book cover base image for a serious nonfiction book, image-only background, no typography on the image",
    title ? `inspired by the book title "${title}"` : "",
    subtitle ? `subtitle context: ${subtitle}` : "",
    author ? `author context: ${author}` : "",
    getStringValue(metadata.book_type) ? `book type: ${getStringValue(metadata.book_type)}` : "",
    getStringValue(metadata.audience) ? `target audience: ${getStringValue(metadata.audience)}` : "",
    getStringValue(metadata.core_thesis) ? `core thesis: ${getStringValue(metadata.core_thesis)}` : "",
    getStringValue(metadata.scope) ? `scope: ${getStringValue(metadata.scope)}` : "",
    getStringValue(metadata.style) ? `style tone: ${getStringValue(metadata.style)}` : "",
    visualDirection ? `visual direction: ${visualDirection}` : "",
    getStringValue(primary.composition) ? `composition: ${getStringValue(primary.composition)}` : "",
    colorDirection ? `color palette: ${colorDirection}` : "",
    moodDirection ? `mood: ${moodDirection}` : "",
    topKeywords ? `keywords: ${topKeywords}` : "",
    getStringValue(primary.route_label) ? `route: ${getStringValue(primary.route_label)}` : "",
    getStringValue(routePrompt?.prompt_draft) ? `draft prompt seed: ${getStringValue(routePrompt.prompt_draft)}` : "",
    "premium publishing quality, clean focal hierarchy, clear subject silhouette, high detail, modern structured knowledge aesthetic, elegant lighting, high contrast, thumbnail-friendly",
    negativePrompt ? `--no ${negativePrompt}` : "",
    "--ar 2:3 --stylize 150 --v 7"
  ];

  return clauses.filter(Boolean).join(", ");
}

function getPublishLanguageRoot(bookRoot, languageCode) {
  return path.join(bookRoot, "09_publish", languageCode);
}

function getLocalizedAmazonDescriptionSourcePath(bookRoot, languageCode = "zh") {
  const normalized = String(languageCode || "zh").trim().toLowerCase();
  if (normalized === "zh") {
    return path.join(bookRoot, "00_brief", "amazon_description.md");
  }
  return path.join(bookRoot, "03_translation", normalized, "00_brief", "amazon_description.md");
}

function extractMarkdownBody(content) {
  const raw = String(content || "").replace(/^\uFEFF/, "").replace(/\r/g, "");
  const match = raw.match(/^---\n[\s\S]*?\n---\n?/);
  if (match) {
    return raw.slice(match[0].length).trim();
  }
  return raw.trim();
}

function getOutputLanguages(bookRoot) {
  const outputRoot = path.join(bookRoot, "04_output");
  if (!fs.existsSync(outputRoot)) {
    return [];
  }

  const languages = [];
  const directOutputFiles = fs.readdirSync(outputRoot, { withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => entry.name)
    .filter((name) => !name.startsWith("~$"))
    .filter((name) => /\.(docx|epub|pdf)$/i.test(name));

  if (directOutputFiles.length) {
    languages.push("zh");
  }

  fs.readdirSync(outputRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && entry.name !== "back")
    .map((entry) => entry.name.trim().toLowerCase())
    .filter(Boolean)
    .sort((a, b) => a.localeCompare(b, "zh-Hans-CN"))
    .forEach((language) => {
      if (!languages.includes(language)) {
        languages.push(language);
      }
    });

  return languages;
}

function getPublishArtifacts(bookRoot, languageCode = "zh") {
  const publishBaseRoot = path.join(bookRoot, "09_publish");
  const publishRoot = getPublishLanguageRoot(bookRoot, languageCode);
  const availableLanguages = listDirectories(publishBaseRoot);
  const sourceLanguages = getOutputLanguages(bookRoot);
  const manifestPath = path.join(publishRoot, "publish_manifest.json");
  const metadataJsonPath = path.join(publishRoot, "publish_metadata.json");
  const metadataMdPath = path.join(publishRoot, "publish_metadata.md");
  const reportPath = path.join(publishRoot, "publish_report.md");
  const amazonDescriptionSourcePath = getLocalizedAmazonDescriptionSourcePath(bookRoot, languageCode);
  const amazonDescriptionSourceMarkdown = readTextIfExists(amazonDescriptionSourcePath);
  const amazonDescriptionSourceText = extractMarkdownBody(amazonDescriptionSourceMarkdown);

  const platformConfig = {
    amazon: {
      packageFile: "amazon_kdp_package.json",
      checklistFile: "amazon_submission_checklist.md",
      descriptionFile: "amazon_description.txt",
      keywordsFile: "amazon_keywords.txt"
    },
    apple: {
      packageFile: "apple_books_package.json",
      checklistFile: "apple_submission_checklist.md",
      descriptionFile: "apple_store_description.txt",
      keywordsFile: "apple_keywords.txt"
    },
    google: {
      packageFile: "google_play_books_package.json",
      checklistFile: "google_submission_checklist.md",
      descriptionFile: "google_store_description.txt",
      keywordsFile: "google_keywords.txt"
    }
  };

  const platforms = Object.fromEntries(
    Object.entries(platformConfig).map(([platformName, config]) => {
      const platformRoot = path.join(publishRoot, platformName);
      return [platformName, {
        exists: fs.existsSync(platformRoot),
        folder: fs.existsSync(platformRoot) ? path.relative(bookRoot, platformRoot) : "",
        files: listDirectFiles(platformRoot),
        packageJson: readJsonFileSafe(path.join(platformRoot, config.packageFile)),
        checklistText: readTextIfExists(path.join(platformRoot, config.checklistFile)),
        descriptionText: readTextIfExists(path.join(platformRoot, config.descriptionFile)),
        descriptionHtml: platformName === "amazon"
          ? readTextIfExists(path.join(platformRoot, "amazon_description.html"))
          : "",
        descriptionSourceMarkdown: platformName === "amazon" ? amazonDescriptionSourceMarkdown : "",
        descriptionSourceText: platformName === "amazon" ? amazonDescriptionSourceText : "",
        descriptionSourcePath: platformName === "amazon" && fs.existsSync(amazonDescriptionSourcePath)
          ? path.relative(bookRoot, amazonDescriptionSourcePath)
          : "",
        keywordsText: readTextIfExists(path.join(platformRoot, config.keywordsFile))
      }];
    })
  );

  return {
    exists: fs.existsSync(publishRoot),
    language: languageCode,
    availableLanguages,
    sourceLanguages,
    root: fs.existsSync(publishRoot) ? path.relative(bookRoot, publishRoot) : "",
    rootFiles: listDirectFiles(publishRoot),
    manifest: readJsonFileSafe(manifestPath),
    metadataJson: readJsonFileSafe(metadataJsonPath),
    metadataMarkdown: readTextIfExists(metadataMdPath),
    reportText: readTextIfExists(reportPath),
    platforms
  };
}

function writeJsonFile(filePath, payload) {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
}

function sanitizeText(value) {
  return String(value || "").trim();
}

function escapeHtmlText(value) {
  return String(value || "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function convertPlainTextToAmazonHtml(text) {
  const normalized = String(text || "").replace(/\r/g, "").trim();
  if (!normalized) {
    return "";
  }

  const paragraphs = normalized
    .split(/\n{2,}/)
    .map((part) => part.split(/\n+/).map((line) => line.trim()).filter(Boolean))
    .filter((lines) => lines.length);

  return paragraphs.map((lines) => {
    const isBulletBlock = lines.every((line) => /^[-*•]\s+/.test(line));
    if (isBulletBlock) {
      const items = lines
        .map((line) => line.replace(/^[-*•]\s+/, "").trim())
        .filter(Boolean)
        .map((line) => `  <li>${escapeHtmlText(line)}</li>`)
        .join("\n");
      return `<ul>\n${items}\n</ul>`;
    }

    return `<p>${escapeHtmlText(lines.join(" "))}</p>`;
  }).join("\n\n");
}

function sanitizeList(input) {
  const items = Array.isArray(input)
    ? input
    : String(input || "").split(/\r?\n|,/);

  return [...new Set(items
    .map((item) => String(item || "").trim())
    .filter(Boolean))];
}

function splitPersonName(fullName) {
  const parts = String(fullName || "").trim().split(/\s+/).filter(Boolean);
  if (!parts.length) {
    return { firstName: "", lastName: "" };
  }
  if (parts.length === 1) {
    return { firstName: parts[0], lastName: "" };
  }
  return {
    firstName: parts.slice(0, -1).join(" "),
    lastName: parts.slice(-1).join("")
  };
}

function buildKoboAccountBasicInfoMarkdown({
  bookName,
  language,
  metadata,
  objectiveData
}) {
  const author = String(metadata?.author || objectiveData?.author || "").trim();
  const publisher = String(metadata?.publisher || author || "").trim();
  const title = String(metadata?.title || objectiveData?.title || "").trim();
  const parsedName = splitPersonName(author);
  const generatedAt = new Date().toISOString();

  const lines = [
    "# Kobo Account Basic Info",
    "",
    "这份文件用于辅助创建 Kobo Writing Life / Kobo Author 账号时，先整理需要人工填写的基本信息。",
    "",
    "## Source",
    `- BookName: ${bookName || ""}`,
    `- Language: ${language || ""}`,
    `- Title: ${title || ""}`,
    `- Author: ${author || ""}`,
    `- Publisher: ${publisher || ""}`,
    `- Generated At: ${generatedAt}`,
    "",
    "## Kobo Portal",
    "- Entry: https://www.kobo.com/writinglife",
    "",
    "## Your Primary Contact",
    `- First Name: ${parsedName.firstName || ""}`,
    `- Last Name: ${parsedName.lastName || ""}`,
    `- Publisher Name: ${publisher || ""}`,
    "- Email Address: ",
    "",
    "## Your Location",
    "- Country: ",
    "- Street Address: ",
    "- Street Address 2: ",
    "- Province/State: ",
    "- City: ",
    "- Postal / Zip Code: ",
    "",
    "## Your Email Preferences",
    "- Receive Kobo-related emails: [ ] Yes  [ ] No",
    "",
    "## Manual Check",
    "- Confirm the contact name used for the Kobo account.",
    "- Confirm the publisher name shown publicly on Kobo.",
    "- Confirm the signup email address.",
    "- Confirm the billing / tax / postal information before提交.",
    "",
    "## Notes",
    "- 这份 MD 会先预填系统里已经有的作者 / 出版方信息。",
    "- 邮箱、地址、国家、邮编等仍需要你人工确认与填写。",
    ""
  ];

  return lines.join("\r\n");
}

function buildAmazonDescriptionSourceMarkdown({ metadata = {}, language = "zh", descriptionText = "" }) {
  const lines = [
    "---",
    "file_role: amazon_description",
    "layer: marketing",
    `title: ${getStringValue(metadata.title)}`,
    `subtitle: ${getStringValue(metadata.subtitle)}`,
    `author: ${getStringValue(metadata.author)}`,
    `language: ${String(language || "zh").trim() || "zh"}`,
    `updated_at: ${formatLocalTimestamp()}`,
    "---",
    "",
    String(descriptionText || "").trim()
  ];
  return `${lines.join("\r\n").trim()}\r\n`;
}

function buildPublishMetadataMarkdown(metadata) {
  const lines = [];
  lines.push("# Publish Metadata");
  lines.push("");
  lines.push(`- Title: ${metadata.title || ""}`);
  lines.push(`- Subtitle: ${metadata.subtitle || ""}`);
  lines.push(`- Author: ${metadata.author || ""}`);
  lines.push(`- Language: ${metadata.language || ""}`);
  lines.push(`- Publication Date: ${metadata.publication_date || ""}`);
  lines.push(`- Publisher: ${metadata.publisher || ""}`);
  lines.push(`- Imprint: ${metadata.imprint || ""}`);
  lines.push(`- Edition Type: ${metadata.edition_type || ""}`);
  lines.push("");
  lines.push("## Rights");
  lines.push("");
  lines.push(metadata.rights || "");
  lines.push("");
  lines.push(`- Copyright Holder: ${metadata.copyright_holder || ""}`);
  lines.push(`- Territory: ${metadata.territory || ""}`);
  lines.push(`- Distribution Rights: ${metadata.distribution_rights || ""}`);
  lines.push("");
  lines.push("## Marketing");
  lines.push("");
  lines.push(`- Tagline: ${metadata.marketing_tagline || ""}`);
  lines.push(`- Cover Hook: ${metadata.cover_hook || ""}`);
  lines.push(`- OBI Copy: ${metadata.obi_copy || ""}`);
  lines.push(`- Spine Text: ${metadata.spine_text || ""}`);
  lines.push("");
  lines.push("## Short Description");
  lines.push("");
  lines.push(metadata.short_description || "");
  lines.push("");
  lines.push("## Long Description");
  lines.push("");
  lines.push(metadata.long_description || "");
  lines.push("");
  lines.push("## Back Cover Blurb");
  lines.push("");
  lines.push(metadata.back_cover_blurb || "");
  lines.push("");
  lines.push("## Author Bio");
  lines.push("");
  lines.push(metadata.author_bio || "");
  lines.push("");
  lines.push("## Keywords");
  lines.push("");
  (metadata.keywords || []).forEach((item) => lines.push(`- ${item}`));
  lines.push("");
  lines.push("## Categories");
  lines.push("");
  (metadata.categories || []).forEach((item) => lines.push(`- ${item}`));
  lines.push("");
  lines.push("## Formats");
  lines.push("");
  (metadata.formats || []).forEach((item) => lines.push(`- ${item}`));
  return lines.join("\r\n");
}

function buildPublishReportMarkdown(metadata, manifest) {
  const lines = [];
  const platforms = Array.isArray(manifest?.platforms) ? manifest.platforms : [];

  lines.push("# Publish Report");
  lines.push("");
  lines.push(`- Generated at: ${formatLocalTimestamp()}`);
  lines.push(`- BookName: ${metadata.book_name || ""}`);
  lines.push(`- Language: ${metadata.language || ""}`);
  lines.push(`- Ready: ${manifest?.ready ? "Yes" : "No"}`);
  lines.push("");
  lines.push("## Book");
  lines.push("");
  lines.push(`- Title: ${metadata.title || ""}`);
  lines.push(`- Subtitle: ${metadata.subtitle || ""}`);
  lines.push(`- Author: ${metadata.author || ""}`);
  lines.push(`- Type: ${metadata.book_type || ""}`);
  lines.push(`- Publisher: ${metadata.publisher || ""}`);
  lines.push(`- Imprint: ${metadata.imprint || ""}`);
  lines.push(`- Rights: ${metadata.rights || ""}`);
  lines.push(`- Edition type: ${metadata.edition_type || ""}`);
  lines.push("");
  lines.push("## Discovery");
  lines.push("");
  lines.push(`- Keywords: ${(metadata.keywords || []).join(", ")}`);
  lines.push(`- Categories: ${(metadata.categories || []).join(", ")}`);
  lines.push(`- Formats: ${(metadata.formats || []).join(", ")}`);
  lines.push("");
  lines.push("## Platforms");
  lines.push("");

  if (!platforms.length) {
    lines.push("- None");
  } else {
    platforms.forEach((platform) => {
      lines.push(`### ${platform.name || ""}`);
      lines.push(`- Folder: ${platform.folder || ""}`);
      lines.push(`- Metadata: ${platform.metadata || ""}`);
      lines.push(`- EPUB: ${platform.copied_files?.epub || ""}`);
      lines.push(`- PDF: ${platform.copied_files?.pdf || ""}`);
      lines.push(`- DOCX: ${platform.copied_files?.docx || ""}`);
      lines.push(`- Cover: ${platform.copied_files?.cover || ""}`);
      lines.push("");
    });
  }

  return lines.join("\r\n");
}

function parsePublishMetadataMarkdown(markdown, existing = {}) {
  const raw = String(markdown || "").replace(/^\uFEFF/, "");
  const lines = raw.split(/\r?\n/);
  const rootFields = {};
  const rightsFields = {};
  const marketingFields = {};
  const selectedPlatformCategories = {
    amazon: existing.platform_selected_categories?.amazon || existing.discovery?.platform_selected_categories?.amazon || "",
    apple: existing.platform_selected_categories?.apple || existing.discovery?.platform_selected_categories?.apple || "",
    google: existing.platform_selected_categories?.google || existing.discovery?.platform_selected_categories?.google || ""
  };
  const recommendedCategories = JSON.parse(JSON.stringify(existing.platform_recommended_categories || existing.discovery?.platform_recommended_categories || {}));
  const rightsParagraph = [];
  const shortDescription = [];
  const longDescription = [];
  const backCoverBlurb = [];
  const authorBio = [];
  const keywords = [];
  const categories = [];
  const formats = [];
  let currentSection = "root";
  let currentPlatform = "";

  const getPlatformKey = (value) => {
    const normalized = String(value || "").trim().toLowerCase();
    if (normalized.includes("amazon")) return "amazon";
    if (normalized.includes("apple")) return "apple";
    if (normalized.includes("google")) return "google";
    return "";
  };

  const normalizeFieldKey = (key) => {
    const rawKey = String(key || "").trim().toLowerCase();
    const map = {
      "书名": "title",
      "title": "title",
      "副标题": "subtitle",
      "subtitle": "subtitle",
      "作者": "author",
      "author": "author",
      "语言": "language",
      "language": "language",
      "出版方": "publisher",
      "publisher": "publisher",
      "品牌": "imprint",
      "imprint": "imprint",
      "版本类型": "edition type",
      "edition type": "edition type",
      "发布日期": "publication date",
      "publication date": "publication date",
      "版权持有人": "copyright holder",
      "copyright holder": "copyright holder",
      "发行地区": "territory",
      "territory": "territory",
      "发行权利": "distribution rights",
      "distribution rights": "distribution rights",
      "宣传语": "tagline",
      "tagline": "tagline",
      "封面短句": "cover hook",
      "cover hook": "cover hook",
      "腰封文案": "obi copy",
      "obi copy": "obi copy",
      "书脊文案": "spine text",
      "spine text": "spine text",
      "默认分类": "selected default",
      "selected default": "selected default"
    };
    return map[rawKey] || rawKey;
  };

  const normalizeSectionHeading = (heading) => {
    const rawHeading = String(heading || "").trim().toLowerCase();
    const map = {
      "版权": "rights",
      "rights": "rights",
      "营销文案": "marketing",
      "marketing": "marketing",
      "短简介": "short_description",
      "short description": "short_description",
      "长简介": "long_description",
      "long description": "long_description",
      "封底摘要": "back_cover_blurb",
      "back cover blurb": "back_cover_blurb",
      "作者简介": "author_bio",
      "author bio": "author_bio",
      "关键词": "keywords",
      "keywords": "keywords",
      "分类": "categories",
      "categories": "categories",
      "平台推荐分类": "platform_recommended_categories",
      "platform recommended categories": "platform_recommended_categories",
      "格式": "formats",
      "formats": "formats"
    };
    return map[rawHeading] || rawHeading;
  };

  const parseFieldLine = (line) => {
    const match = String(line || "").trim().match(/^- ([^:]+):\s*(.*)$/);
    if (!match) {
      return null;
    }
    return { key: normalizeFieldKey(match[1].trim()), value: match[2].trim() };
  };

  const extractBulletSection = (sectionTitle) => {
    const targetHeading = `## ${String(sectionTitle || "").trim().toLowerCase()}`;
    let collecting = false;
    const results = [];

    for (const entry of lines) {
      const trimmedEntry = String(entry || "").trim();
      const normalizedHeading = trimmedEntry.toLowerCase();

      if (normalizedHeading === targetHeading) {
        collecting = true;
        continue;
      }

      if (collecting && /^##\s+/i.test(trimmedEntry)) {
        break;
      }

      if (collecting && trimmedEntry.startsWith("- ")) {
        results.push(trimmedEntry.replace(/^- /, "").trim());
      }
    }

    return results.filter(Boolean);
  };

  const pushParagraphLine = (bucket, line) => {
    const value = String(line || "").trimEnd();
    if (!bucket.length && !value.trim()) {
      return;
    }
    bucket.push(value);
  };

  for (const line of lines) {
    const trimmed = String(line || "").trim();

    if (/^###\s+/.test(trimmed)) {
      currentSection = "platform_recommended_categories";
      currentPlatform = getPlatformKey(trimmed.replace(/^###\s+/, ""));
      if (currentPlatform && !Array.isArray(recommendedCategories[currentPlatform])) {
        recommendedCategories[currentPlatform] = [];
      }
      continue;
    }

    if (/^##\s+/.test(trimmed)) {
      currentPlatform = "";
      const heading = normalizeSectionHeading(trimmed.replace(/^##\s+/, "").trim());
      if (heading === "rights") currentSection = "rights";
      else if (heading === "marketing") currentSection = "marketing";
      else if (heading === "short_description") currentSection = "short_description";
      else if (heading === "long_description") currentSection = "long_description";
      else if (heading === "back_cover_blurb") currentSection = "back_cover_blurb";
      else if (heading === "author_bio") currentSection = "author_bio";
      else if (heading === "keywords") currentSection = "keywords";
      else if (heading === "categories") currentSection = "categories";
      else if (heading === "platform_recommended_categories") currentSection = "platform_recommended_categories";
      else if (heading === "formats") currentSection = "formats";
      else currentSection = "other";
      continue;
    }

    if (/^#\s+/.test(trimmed)) {
      currentSection = "root";
      currentPlatform = "";
      continue;
    }

    if (currentSection === "root") {
      const field = parseFieldLine(trimmed);
      if (field) rootFields[field.key] = field.value;
      continue;
    }

    if (currentSection === "rights") {
      const field = parseFieldLine(trimmed);
      if (field) rightsFields[field.key] = field.value;
      else pushParagraphLine(rightsParagraph, line);
      continue;
    }

    if (currentSection === "marketing") {
      const field = parseFieldLine(trimmed);
      if (field) marketingFields[field.key] = field.value;
      continue;
    }

    if (currentSection === "short_description") {
      pushParagraphLine(shortDescription, line);
      continue;
    }

    if (currentSection === "long_description") {
      pushParagraphLine(longDescription, line);
      continue;
    }

    if (currentSection === "back_cover_blurb") {
      pushParagraphLine(backCoverBlurb, line);
      continue;
    }

    if (currentSection === "author_bio") {
      pushParagraphLine(authorBio, line);
      continue;
    }

    if (currentSection === "keywords" && trimmed.startsWith("- ")) {
      keywords.push(trimmed.replace(/^- /, "").trim());
      continue;
    }

    if (currentSection === "categories" && trimmed.startsWith("- ")) {
      categories.push(trimmed.replace(/^- /, "").trim());
      continue;
    }

    if (currentSection === "formats" && trimmed.startsWith("- ")) {
      formats.push(trimmed.replace(/^- /, "").trim());
      continue;
    }

    if (currentSection === "platform_recommended_categories" && currentPlatform) {
      const selectedMatch = trimmed.match(/^- Selected default:\s*(.*)$/i);
      if (selectedMatch) {
        selectedPlatformCategories[currentPlatform] = selectedMatch[1].trim();
        continue;
      }

      const recMatch = trimmed.match(/^- \[(.*?)\]\s+(.*?)\s+-\s+(.*)$/);
      if (recMatch) {
        recommendedCategories[currentPlatform] = recommendedCategories[currentPlatform] || [];
        recommendedCategories[currentPlatform].push({
          priority: recMatch[1].trim(),
          path: recMatch[2].trim(),
          note: recMatch[3].trim()
        });
      }
    }
  }

  const cleanBlock = (bucket, fallback = "") => {
    const text = bucket.join("\n").replace(/^\s+|\s+$/g, "");
    return text || fallback || "";
  };

  const languageMatch = String(rootFields.language || "").match(/^([a-z]{2,5})\s*(?:\((.*?)\))?$/i);

  return {
    title: sanitizeText(rootFields.title || existing.title),
    subtitle: sanitizeText(rootFields.subtitle || existing.subtitle),
    author: sanitizeText(rootFields.author || existing.author),
    language: sanitizeText((languageMatch?.[1] || existing.language || "").toLowerCase()),
    language_name: sanitizeText(languageMatch?.[2] || existing.language_name),
    publisher: sanitizeText(rootFields.publisher || existing.publisher),
    imprint: sanitizeText(rootFields.imprint || existing.imprint),
    edition_type: sanitizeText(rootFields["edition type"] || existing.edition_type),
    publication_date: sanitizeText(rootFields["publication date"] || existing.publication_date),
    rights: sanitizeText(cleanBlock(rightsParagraph, existing.rights)),
    copyright_holder: sanitizeText(rightsFields["copyright holder"] || existing.copyright_holder),
    territory: sanitizeText(rightsFields.territory || existing.territory),
    distribution_rights: sanitizeText(rightsFields["distribution rights"] || existing.distribution_rights),
    marketing_tagline: sanitizeText(marketingFields.tagline || existing.marketing_tagline),
    cover_hook: sanitizeText(marketingFields["cover hook"] || existing.cover_hook),
    obi_copy: sanitizeText(marketingFields["obi copy"] || existing.obi_copy),
    spine_text: sanitizeText(marketingFields["spine text"] || existing.spine_text),
    short_description: sanitizeText(cleanBlock(shortDescription, existing.short_description)),
    long_description: sanitizeText(cleanBlock(longDescription, existing.long_description)),
    back_cover_blurb: sanitizeText(cleanBlock(backCoverBlurb, existing.back_cover_blurb)),
    author_bio: sanitizeText(cleanBlock(authorBio, existing.author_bio)),
    keywords: sanitizeList(keywords.length ? keywords : (extractBulletSection("Keywords").length ? extractBulletSection("Keywords") : (existing.keywords || existing.discovery?.keywords))),
    categories: sanitizeList(categories.length ? categories : (extractBulletSection("Categories").length ? extractBulletSection("Categories") : (existing.categories || existing.discovery?.categories))),
    formats: sanitizeList(formats.length ? formats : (extractBulletSection("Formats").length ? extractBulletSection("Formats") : existing.formats)),
    platform_selected_categories: {
      amazon: sanitizeText(selectedPlatformCategories.amazon),
      apple: sanitizeText(selectedPlatformCategories.apple),
      google: sanitizeText(selectedPlatformCategories.google)
    },
    platform_recommended_categories: recommendedCategories
  };
}

function extractMarkdownBulletSection(markdown, sectionTitle) {
  const lines = String(markdown || "").replace(/^\uFEFF/, "").split(/\r?\n/);
  const targetHeading = `## ${String(sectionTitle || "").trim().toLowerCase()}`;
  let collecting = false;
  const results = [];

  for (const line of lines) {
    const trimmed = String(line || "").trim();
    const normalized = trimmed.toLowerCase();

    if (normalized === targetHeading) {
      collecting = true;
      continue;
    }

    if (collecting && /^##\s+/i.test(trimmed)) {
      break;
    }

    if (collecting && trimmed.startsWith("- ")) {
      results.push(trimmed.replace(/^- /, "").trim());
    }
  }

  return results.filter(Boolean);
}

function buildPlatformMetadataFromPublish(metadata, platformName) {
  return {
    platform: platformName,
    book_name: metadata.book_name || "",
    language: metadata.language || "",
    language_name: metadata.language_name || "",
    title: metadata.title || "",
    subtitle: metadata.subtitle || "",
    author: metadata.author || "",
    audience: metadata.audience || "",
    type: metadata.book_type || "",
    style: metadata.style || "",
    publisher: metadata.publisher || "",
    imprint: metadata.imprint || "",
    publication_date: metadata.publication_date || "",
    rights: metadata.rights || "",
    copyright_holder: metadata.copyright_holder || "",
    copyright_year: String(metadata.copyright_year || ""),
    territory: metadata.territory || "",
    distribution_rights: metadata.distribution_rights || "",
    edition_type: metadata.edition_type || "",
    short_description: metadata.short_description || "",
    long_description: metadata.long_description || "",
    marketing_tagline: metadata.marketing_tagline || "",
    cover_hook: metadata.cover_hook || "",
    back_cover_blurb: metadata.back_cover_blurb || "",
    obi_copy: metadata.obi_copy || "",
    author_bio: metadata.author_bio || "",
    spine_text: metadata.spine_text || "",
    keywords: Array.isArray(metadata.keywords) ? metadata.keywords : [],
    categories: Array.isArray(metadata.categories) ? metadata.categories : [],
    platform_recommended_categories: metadata.platform_recommended_categories || {},
    platform_selected_categories: metadata.platform_selected_categories || {},
    formats: Array.isArray(metadata.formats) ? metadata.formats : [],
    identification: metadata.identification || {},
    marketing: metadata.marketing || {},
    rights_metadata: metadata.rights_metadata || {},
    discovery: metadata.discovery || {},
    distribution: metadata.distribution || {},
    source_files: {
      epub: metadata.source_files?.epub || "",
      pdf: metadata.source_files?.pdf || "",
      docx: metadata.source_files?.docx || "",
      cover: metadata.source_files?.cover || ""
    }
  };
}

function runEngineScriptSync(scriptName, args = []) {
  const scriptPath = path.join(ENGINE_ROOT, scriptName);
  const psArgs = [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    scriptPath,
    ...args
  ];

  const result = spawnSync("powershell.exe", psArgs, {
    cwd: ENGINE_ROOT,
    env: process.env,
    encoding: "utf8"
  });

  if ((result.status ?? -1) !== 0) {
    const message = [result.stderr, result.stdout]
      .filter(Boolean)
      .join("\n")
      .trim() || `${scriptName} failed.`;
    throw new Error(message);
  }

  return result;
}

function syncPublishMetadataFiles(bookRoot, languageCode, nextMetadata) {
  const publishRoot = getPublishLanguageRoot(bookRoot, languageCode);
  const metadataJsonPath = path.join(publishRoot, "publish_metadata.json");
  const metadataMdPath = path.join(publishRoot, "publish_metadata.md");
  const manifestPath = path.join(publishRoot, "publish_manifest.json");
  const reportPath = path.join(publishRoot, "publish_report.md");

  writeJsonFile(metadataJsonPath, nextMetadata);
  fs.writeFileSync(metadataMdPath, buildPublishMetadataMarkdown(nextMetadata), "utf8");

  const manifest = readJsonFileSafe(manifestPath);
  fs.writeFileSync(reportPath, buildPublishReportMarkdown(nextMetadata, manifest), "utf8");

  const platformScripts = {
    amazon: "09c-amazon.ps1",
    apple: "09d-apple.ps1",
    google: "09e-google.ps1"
  };

  Object.entries(platformScripts).forEach(([platformName, scriptName]) => {
    const platformRoot = path.join(publishRoot, platformName);
    if (!fs.existsSync(platformRoot)) {
      return;
    }

    const platformMetadataPath = path.join(platformRoot, "metadata.json");
    writeJsonFile(platformMetadataPath, buildPlatformMetadataFromPublish(nextMetadata, platformName));
    runEngineScriptSync(scriptName, [
      "-BookName", nextMetadata.book_name || "",
      "-Language", languageCode,
      "-Force"
    ]);
  });
}

function buildCoverCopyMarkdown(copyData) {
  const selected = copyData?.selected || {};
  const candidates = copyData?.candidates || {};
  const editorNotes = Array.isArray(copyData?.editor_notes) ? copyData.editor_notes : [];

  const lines = [];
  lines.push("# Cover Copy");
  lines.push("");
  lines.push("## Selected");
  lines.push("");
  lines.push(`- Subtitle: ${selected.subtitle || ""}`);
  lines.push(`- Back cover hook: ${selected.back_cover_hook || ""}`);
  lines.push(`- Obi copy: ${selected.obi_copy || ""}`);
  lines.push(`- Marketing tagline: ${selected.marketing_tagline || ""}`);
  lines.push(`- Spine text: ${selected.spine_text || ""}`);
  lines.push("");
  lines.push("## Back Cover Blurb");
  lines.push("");
  lines.push(selected.back_cover_blurb || "");
  lines.push("");
  lines.push("## Author Bio");
  lines.push("");
  lines.push(selected.author_bio || "");
  lines.push("");
  lines.push("## Candidate Pools");
  lines.push("");

  [
    ["Subtitle", candidates.subtitle || []],
    ["Back Cover Hook", candidates.back_cover_hook || []],
    ["Obi Copy", candidates.obi_copy || []],
    ["Marketing Tagline", candidates.marketing_tagline || []]
  ].forEach(([title, items]) => {
    lines.push(`### ${title}`);
    if (Array.isArray(items) && items.length) {
      items.forEach((item) => lines.push(`- ${item}`));
    } else {
      lines.push("- ");
    }
    lines.push("");
  });

  lines.push("## Editor Notes");
  if (editorNotes.length) {
    editorNotes.forEach((item) => lines.push(`- ${item}`));
  } else {
    lines.push("- ");
  }

  return lines.join("\r\n");
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

function readJsonBody(req, maxBytes = 5_000_000) {
  return new Promise((resolve, reject) => {
    let raw = "";
    let size = 0;
    req.on("data", (chunk) => {
      size += chunk.length;
      raw += chunk;
      if (size > maxBytes) {
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
      const publishRoot = path.join(bookRoot, "09_publish");
      const logRoot = path.join(bookRoot, "logs");
      const statusPath = path.join(logRoot, "status.json");
      const runLogPath = path.join(logRoot, "run_history.jsonl");
      const webRunIndexPath = path.join(logRoot, "webui_runs.jsonl");
      const editReportJsonPath = path.join(logRoot, "edit_report.json");
      const coverArtifacts = getCoverArtifacts(bookRoot);
      const tocContent = fs.existsSync(tocPath)
        ? fs.readFileSync(tocPath, "utf8")
        : "";
      const chapterFiles = getChapterMetadata(chapterRoot);
      const chapterCount = chapterFiles.length;
      const outputs = listOutputDocuments(outputRoot);
      const outputLanguages = getOutputLanguages(bookRoot);
      const publishLanguages = listDirectories(publishRoot);
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
        outputLanguages,
        publishLanguages,
        coverArtifacts,
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
    ".json": "application/json; charset=utf-8",
    ".svg": "image/svg+xml; charset=utf-8"
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
  Object.defineProperty(job, "child", {
    value: null,
    writable: true,
    enumerable: false,
    configurable: true
  });
  jobs.set(id, job);
  return job;
}

function appendJobOutput(job, chunk) {
  job.output += chunk;
  job.updatedAt = new Date().toISOString();
}

function appendJobLifecycleLine(job, message) {
  appendJobOutput(job, `[webui] ${message}\n`);
}

function finishJob(job, exitCode) {
  if (job.status === "cancelled") {
    job.child = null;
    job.childPid = null;
    return;
  }
  job.status = exitCode === 0 ? "success" : "failed";
  job.exitCode = exitCode;
  job.updatedAt = new Date().toISOString();
  job.child = null;
  job.childPid = null;
  appendJobLifecycleLine(job, `Run finished. Job ID: ${job.id}. Status: ${job.status}. Exit code: ${job.exitCode}.`);
  archiveJobOutput(job);
}

function failJob(job, error) {
  if (job.status === "cancelled") {
    job.child = null;
    job.childPid = null;
    return;
  }
  job.status = "failed";
  job.exitCode = -1;
  job.updatedAt = new Date().toISOString();
  job.output += `\n[webui-error] ${error.message}\n`;
  job.child = null;
  job.childPid = null;
  appendJobLifecycleLine(job, `Run finished. Job ID: ${job.id}. Status: failed. Exit code: -1.`);
  archiveJobOutput(job);
}

function cancelJob(job) {
  if (!job) {
    throw new Error("Job not found.");
  }
  if (job.status !== "running") {
    return job;
  }
  if (!job.childPid) {
    throw new Error("No running process found for this job.");
  }

  const result = spawnSync("taskkill.exe", ["/PID", String(job.childPid), "/T", "/F"], {
    encoding: "utf8",
    windowsHide: true
  });

  if (result.stdout) {
    appendJobOutput(job, result.stdout);
  }
  if (result.stderr) {
    appendJobOutput(job, result.stderr);
  }
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error((result.stderr || result.stdout || "Failed to stop current job.").trim());
  }

  appendJobLifecycleLine(job, `Run cancelled. Job ID: ${job.id}.`);
  job.status = "cancelled";
  job.exitCode = -999;
  job.updatedAt = new Date().toISOString();
  job.child = null;
  job.childPid = null;
  archiveJobOutput(job);
  return job;
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
  const normalized = path.normalize(fileName);
  if (path.isAbsolute(normalized) || normalized.startsWith("..") || normalized.includes("..\\")) {
    throw new Error("Invalid fileName.");
  }
  if (!/\.(docx|epub|pdf)$/i.test(fileName)) {
    throw new Error("Only .docx, .epub, or .pdf output files are supported.");
  }
}

function resolveOutputDocumentPath(paths, fileName) {
  validateOutputFileName(fileName);
  const outputPath = path.resolve(paths.outputRoot, fileName);
  const outputRootResolved = path.resolve(paths.outputRoot);
  if (!outputPath.startsWith(outputRootResolved)) {
    throw new Error("Invalid output file path.");
  }
  return outputPath;
}

function validateAssetFileName(fileName) {
  if (!fileName || typeof fileName !== "string") {
    throw new Error("fileName is required.");
  }
  if (fileName !== path.basename(fileName)) {
    throw new Error("Invalid fileName.");
  }
  if (!/\.(png|jpg|jpeg|webp|pdf)$/i.test(fileName)) {
    throw new Error("Unsupported asset file type.");
  }
}

function sanitizeImportedImageFileName(fileName, fallbackExt) {
  const ext = path.extname(String(fileName || "")).toLowerCase() || fallbackExt;
  if (![".png", ".jpg", ".jpeg", ".webp"].includes(ext)) {
    throw new Error("Unsupported image file type.");
  }

  const stem = path.basename(String(fileName || "external-base-image"), path.extname(String(fileName || "")))
    .replace(/[^\w.-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 72) || "external-base-image";
  return `${stem}${ext}`;
}

function sanitizeKdpFixImageFileName(fileName) {
  const ext = path.extname(String(fileName || "")).toLowerCase() || ".png";
  if (![".png", ".jpg", ".jpeg", ".webp"].includes(ext)) {
    throw new Error("Unsupported KDP fix image type.");
  }
  const stem = path.basename(String(fileName || "kdp-fix-image"), path.extname(String(fileName || "")))
    .replace(/[^\w.-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80) || "kdp-fix-image";
  return `${stem}${ext}`;
}

function sanitizeKdpFixPdfFileName(fileName) {
  const ext = path.extname(String(fileName || "")).toLowerCase() || ".pdf";
  if (ext !== ".pdf") {
    throw new Error("Unsupported KDP fix PDF type.");
  }
  const stem = path.basename(String(fileName || "kdp-fix-pdf"), path.extname(String(fileName || "")))
    .replace(/[^\w.-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 90) || "kdp-fix-pdf";
  return `${stem}.pdf`;
}

function resolveKdpAcceptanceFilePath(bookName, relativePath, allowedExtensions = [".pdf", ".png"]) {
  validateBookName(bookName);
  const paths = getWorkspacePaths(bookName);
  const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
  const cleanRelative = String(relativePath || "")
    .replace(/^[/\\]+/, "")
    .replace(/\\/g, "/");
  if (!cleanRelative || cleanRelative.includes("..") || path.isAbsolute(cleanRelative)) {
    throw new Error("Invalid KDP acceptance file path.");
  }
  const ext = path.extname(cleanRelative).toLowerCase();
  if (!allowedExtensions.includes(ext)) {
    throw new Error("Unsupported KDP acceptance file type.");
  }
  const rootResolved = path.resolve(acceptanceRoot);
  const targetPath = path.resolve(acceptanceRoot, cleanRelative);
  if (!targetPath.startsWith(rootResolved + path.sep) && targetPath !== rootResolved) {
    throw new Error("KDP acceptance file is outside the acceptance directory.");
  }
  if (!fs.existsSync(targetPath) || !fs.statSync(targetPath).isFile()) {
    throw new Error("KDP acceptance file not found.");
  }
  return {
    paths,
    acceptanceRoot,
    targetPath,
    relativePath: cleanRelative,
    ext
  };
}

function getImageMimeTypeByPath(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  return {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp"
  }[ext] || "application/octet-stream";
}

function getPngDimensions(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length < 24 || buffer.slice(0, 8).toString("hex") !== "89504e470d0a1a0a") {
    throw new Error("PNG data is invalid.");
  }
  return {
    width: buffer.readUInt32BE(16),
    height: buffer.readUInt32BE(20)
  };
}

function sanitizeImportedPdfFileName(fileName) {
  const ext = path.extname(String(fileName || "")).toLowerCase() || ".pdf";
  if (ext !== ".pdf") {
    throw new Error("Only PDF files can be submitted to the KDP acceptance tool.");
  }

  const stem = path.basename(String(fileName || "cover-upload"), path.extname(String(fileName || "")))
    .replace(/[^\w.-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 72) || "cover-upload";
  return `${stem}.pdf`;
}

function validateLanguageCode(languageCode) {
  if (!languageCode || typeof languageCode !== "string") {
    throw new Error("language is required.");
  }
  if (!/^[A-Za-z0-9_-]+$/.test(languageCode)) {
    throw new Error("Invalid language.");
  }
}

function validatePublishPlatform(platform) {
  if (!platform) {
    return;
  }
  if (!["amazon", "apple", "google", "kobo"].includes(platform)) {
    throw new Error("Invalid publish platform.");
  }
}

function validatePublishFileName(fileName) {
  if (!fileName || typeof fileName !== "string") {
    throw new Error("fileName is required.");
  }
  if (fileName !== path.basename(fileName)) {
    throw new Error("Invalid fileName.");
  }
  if (!/\.(json|md|txt|png|jpg|jpeg|webp|pdf|epub|docx)$/i.test(fileName)) {
    throw new Error("Unsupported publish file type.");
  }
}

function validateAbsoluteFolderPath(folderPath) {
  if (!folderPath || typeof folderPath !== "string") {
    throw new Error("folderPath is required.");
  }

  const resolved = path.resolve(folderPath);
  if (!path.isAbsolute(resolved)) {
    throw new Error("folderPath must be an absolute path.");
  }
  if (!fs.existsSync(resolved)) {
    throw new Error("folderPath does not exist.");
  }
  if (!fs.statSync(resolved).isDirectory()) {
    throw new Error("folderPath must point to a directory.");
  }

  return resolved;
}

function resolveCoverSectionRoot(paths, section) {
  const nextRoot = path.join(paths.bookRoot, "07_cover", "next", "ebook");
  const nextPrintRoot = path.join(paths.bookRoot, "07_cover", "next", "print");
  switch (section) {
    case "drafts":
      return paths.coverDraftRoot;
    case "layout":
      return paths.coverLayoutRoot;
    case "mockup":
      return paths.coverMockupRoot;
    case "final":
      return paths.coverFinalRoot;
    case "kdp-acceptance":
      return getKdpAcceptanceRoot(paths.bookRoot);
    case "next-imports":
      return path.join(nextRoot, "imports");
    case "next-layout":
      return path.join(nextRoot, "layout");
    case "next-print-spread":
      return path.join(nextPrintRoot, "print_spread");
    case "next-mockup":
      return path.join(nextRoot, "mockup");
    case "next-final":
      return path.join(nextRoot, "final");
    default:
      throw new Error("Invalid cover section.");
  }
}

function resolvePublishSectionRoot(paths, languageCode, platform) {
  validateLanguageCode(languageCode);
  validatePublishPlatform(platform);

  const publishRoot = getPublishLanguageRoot(paths.bookRoot, languageCode);
  return platform ? path.join(publishRoot, platform) : publishRoot;
}

function openFileWithDefaultApp(filePath) {
  const launcherPath = path.join(__dirname, "open-target.vbs");
  if (!fs.existsSync(launcherPath)) {
    throw new Error("Open target launcher not found.");
  }

  const child = spawn("wscript.exe", [
    launcherPath,
    filePath
  ], {
    detached: true,
    stdio: "ignore",
    windowsHide: false
  });

  child.unref();
}

function openFolder(folderPath) {
  const launcherPath = path.join(__dirname, "open-target.vbs");
  if (!fs.existsSync(launcherPath)) {
    throw new Error("Open target launcher not found.");
  }

  const child = spawn("wscript.exe", [
    launcherPath,
    folderPath
  ], {
    detached: true,
    stdio: "ignore",
    windowsHide: false
  });

  child.unref();
}

function revealFileInExplorer(filePath) {
  openFileWithDefaultApp(filePath);
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

  appendJobLifecycleLine(job, `Run started. Job ID: ${job.id}. Route: ${meta?.route || ""}. Script: ${scriptName}.`);

  const child = spawn("powershell.exe", args, {
    cwd: ENGINE_ROOT,
    env: process.env
  });

  job.child = child;
  job.childPid = child.pid;

  child.stdout.on("data", (chunk) => appendJobOutput(job, chunk.toString("utf8")));
  child.stderr.on("data", (chunk) => appendJobOutput(job, chunk.toString("utf8")));
  child.on("error", (error) => failJob(job, error));
  child.on("close", (code) => finishJob(job, code ?? -1));

  return job;
}

function runPowerShellJson(scriptName, params = []) {
  const scriptPath = path.join(ENGINE_ROOT, scriptName);
  if (!fs.existsSync(scriptPath)) {
    throw new Error(`Script not found: ${scriptName}`);
  }
  const args = [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    scriptPath
  ];
  params.forEach((item) => {
    if (item.type === "switch") {
      if (item.enabled) args.push(item.flag);
      return;
    }
    pushArg(args, item.flag, item.value);
  });
  const result = spawnSync("powershell.exe", args, {
    cwd: ENGINE_ROOT,
    env: process.env,
    encoding: "utf8",
    maxBuffer: 20 * 1024 * 1024
  });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error((result.stderr || result.stdout || `${scriptName} failed.`).trim());
  }
  const text = String(result.stdout || "").trim();
  if (!text) {
    return null;
  }
  return JSON.parse(text);
}

function runDetachedScript(scriptName, params, meta, message = "") {
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
    env: process.env,
    detached: true,
    stdio: "ignore"
  });

  child.unref();
  appendJobOutput(job, `${message || `${scriptName} started in detached mode.`}\n`);
  finishJob(job, 0);
  return job;
}

function toPowerShellSingleQuoted(value) {
  return `'${String(value ?? "").replace(/'/g, "''")}'`;
}

function launchScriptInNewConsole(scriptName, params, meta, message = "") {
  const scriptPath = path.join(ENGINE_ROOT, scriptName);
  if (!fs.existsSync(scriptPath)) {
    throw new Error(`Script not found: ${scriptName}`);
  }

  const job = createJob(meta);
  const launcherPath = path.join(__dirname, "launch-powershell-file.vbs");
  if (!fs.existsSync(launcherPath)) {
    throw new Error("PowerShell launcher not found.");
  }

  const launchRoot = path.join(__dirname, "launchers");
  ensureDir(launchRoot);

  const wrapperPath = path.join(launchRoot, `${Date.now()}-${randomUUID()}.ps1`);
  const commandParts = [`& ${toPowerShellSingleQuoted(scriptPath)}`];
  params.forEach((item) => {
    if (item.type === "switch") {
      if (item.enabled) {
        commandParts.push(item.flag);
      }
      return;
    }
    commandParts.push(item.flag);
    commandParts.push(toPowerShellSingleQuoted(item.value));
  });

  const windowTitle = `SageWrite ${scriptName}`;
  const wrapperLines = [
    `$Host.UI.RawUI.WindowTitle = ${toPowerShellSingleQuoted(windowTitle)}`,
    "",
    commandParts.join(" "),
    ""
  ];
  fs.writeFileSync(wrapperPath, wrapperLines.join("\r\n"), "utf8");

  const child = spawn("wscript.exe", [
    launcherPath,
    wrapperPath,
    windowTitle
  ], {
    cwd: __dirname,
    env: process.env,
    detached: true,
    stdio: "ignore",
    windowsHide: false
  });

  child.unref();
  appendJobOutput(job, `${message || `${scriptName} started in a new console window.`}\n`);
  finishJob(job, 0);
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
          { flag: "-Subtitle", value: body.subtitle || undefined },
          { flag: "-Author", value: body.author || undefined },
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
        if (!body.model) {
          throw new Error("Model is required.");
        }
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
          { flag: "-Model", value: body.model || "gpt-5.2" },
          { flag: "-Chapter", value: body.mode === "chapter" ? body.chapter : undefined },
          { flag: "-StartChapter", value: body.mode === "range" ? body.startChapter : undefined },
          { flag: "-EndChapter", value: body.mode === "range" ? body.endChapter : undefined },
          { flag: "-MaxTokens", value: body.maxTokens || 6000 },
          { flag: "-AdditionalInstructions", value: body.additionalInstructions || undefined },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], { route, bookName });
        break;
      case "translate":
        if (!body.language) {
          throw new Error("Language is required.");
        }
        body.model = String(body.model || "").trim() || "gpt-5.2";
        if (body.mode === "chapter" && (body.chapter === undefined || body.chapter === null || body.chapter === "")) {
          throw new Error("Chapter is required.");
        }
        if (body.mode === "range" && (!body.startChapter || !body.endChapter)) {
          throw new Error("StartChapter and EndChapter are required.");
        }
        job = runScript("03t-translate.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Language", value: body.language },
          { flag: "-Model", value: body.model || "gpt-5.2" },
          { flag: "-Chapter", value: body.mode === "chapter" ? body.chapter : undefined },
          { flag: "-StartChapter", value: body.mode === "range" ? body.startChapter : undefined },
          { flag: "-EndChapter", value: body.mode === "range" ? body.endChapter : undefined },
          { flag: "-All", type: "switch", enabled: body.mode === "all" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], { route, bookName });
        break;
      case "refine-translation":
        if (!body.language) {
          throw new Error("Language is required.");
        }
        if (!body.model) {
          throw new Error("Model is required.");
        }
        if (body.mode === "chapter" && !body.chapter) {
          throw new Error("Chapter is required.");
        }
        if (body.mode === "range" && (!body.startChapter || !body.endChapter)) {
          throw new Error("StartChapter and EndChapter are required.");
        }
        job = runScript("03r-refine.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Language", value: body.language },
          { flag: "-Model", value: body.model || "gpt-5.2" },
          { flag: "-Chapter", value: body.mode === "chapter" ? body.chapter : undefined },
          { flag: "-StartChapter", value: body.mode === "range" ? body.startChapter : undefined },
          { flag: "-EndChapter", value: body.mode === "range" ? body.endChapter : undefined },
          { flag: "-All", type: "switch", enabled: body.mode === "all" },
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
          { flag: "-Language", value: body.language || "zh" },
          { flag: "-AutoNumber", type: "switch", enabled: Boolean(body.autoNumber) }
        ], { route, bookName });
        break;
      case "build-simple":
        job = runScript("05a-simple-docx.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Language", value: body.language || "zh" },
          { flag: "-AutoNumber", type: "switch", enabled: Boolean(body.autoNumber) }
        ], { route, bookName });
        break;
      case "build-simple-toc":
        job = runScript("05aa-simple-docx-toc.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Language", value: body.language || "zh" },
          { flag: "-AutoNumber", type: "switch", enabled: Boolean(body.autoNumber) }
        ], { route, bookName });
        break;
      case "build-epub":
        job = runScript("05b-epub.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Language", value: body.language || "zh" },
          { flag: "-AutoNumber", type: "switch", enabled: Boolean(body.autoNumber) }
        ], { route, bookName });
        break;
      case "build-pdf":
        job = runScript("05c-pdf.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Language", value: body.language || "zh" },
          { flag: "-AutoNumber", type: "switch", enabled: Boolean(body.autoNumber) }
        ], { route, bookName });
        break;
      case "build-print-pdf":
        job = runScript("05cc-print-pdf.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Language", value: body.language || "zh" },
          { flag: "-AutoNumber", type: "switch", enabled: Boolean(body.autoNumber) }
        ], { route, bookName });
        break;
      case "cover":
        job = runScript("08-cover.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Title", value: body.title || undefined },
          { flag: "-Subtitle", value: body.subtitle || undefined },
          { flag: "-Author", value: body.author || undefined },
          { flag: "-Variants", value: body.variants || 4 },
          { flag: "-Mode", value: body.mode || "auto" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) },
          { flag: "-SkipLayout", type: "switch", enabled: Boolean(body.skipLayout) },
          { flag: "-SkipMockup", type: "switch", enabled: Boolean(body.skipMockup) }
        ], { route, bookName });
        break;
      case "cover-drafts":
        job = runScript("08-cover-drafts.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Title", value: body.title || undefined },
          { flag: "-Subtitle", value: body.subtitle || undefined },
          { flag: "-Author", value: body.author || undefined },
          { flag: "-Variants", value: body.variants || 4 },
          { flag: "-Mode", value: body.mode || "auto" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], { route, bookName });
        break;
      case "cover-layout":
        job = runScript("08-cover-layout.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Title", value: body.title || undefined },
          { flag: "-Subtitle", value: body.subtitle || undefined },
          { flag: "-Author", value: body.author || undefined },
          { flag: "-Mode", value: body.mode || "auto" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], { route, bookName });
        break;
      case "cover-mockup":
        job = runScript("08-cover-mockup.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Mode", value: body.mode || "auto" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], { route, bookName });
        break;
      case "cover-assist":
        job = runScript("07a-cover-assist.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Request", value: body.request || undefined },
          { flag: "-Title", value: body.title || undefined },
          { flag: "-Subtitle", value: body.subtitle || undefined },
          { flag: "-Author", value: body.author || undefined },
          { flag: "-Model", value: body.model || undefined }
        ], { route, bookName });
        break;
      case "cover-midjourney-prompt-ai":
        job = runScript("08n-midjourney-prompt.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Edition", value: body.nextEdition || body.edition || "ebook" },
          { flag: "-Title", value: body.title || undefined },
          { flag: "-Subtitle", value: body.subtitle || undefined },
          { flag: "-Author", value: body.author || undefined },
          { flag: "-Model", value: body.model || "gpt-5.2" }
        ], { route, bookName });
        break;
      case "cover-next":
        job = runScript("08n-cover.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Edition", value: body.nextEdition || body.edition || "ebook" },
          { flag: "-Title", value: body.title || undefined },
          { flag: "-Subtitle", value: body.subtitle || undefined },
          { flag: "-Author", value: body.author || undefined },
          { flag: "-Variants", value: body.variants || 4 },
          { flag: "-Mode", value: body.mode || "auto" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) },
          { flag: "-SkipMockup", type: "switch", enabled: Boolean(body.skipMockup) },
          { flag: "-SkipPrintSpread", type: "switch", enabled: Boolean(body.skipPrintSpread) }
        ], { route, bookName });
        break;
      case "cover-next-brief":
        job = runScript("08n-base-brief.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Edition", value: body.nextEdition || body.edition || "ebook" },
          { flag: "-Title", value: body.title || undefined },
          { flag: "-Subtitle", value: body.subtitle || undefined },
          { flag: "-Author", value: body.author || undefined },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], { route, bookName });
        break;
      case "cover-next-prompt":
        job = runScript("08n-base-prompt.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Edition", value: body.nextEdition || body.edition || "ebook" },
          { flag: "-Mode", value: body.mode || "auto" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], { route, bookName });
        break;
      case "cover-next-generate":
        job = runScript("08n-base-generate.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Edition", value: body.nextEdition || body.edition || "ebook" },
          { flag: "-Variants", value: body.variants || 4 },
          { flag: "-Mode", value: body.mode || "auto" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], { route, bookName });
        break;
      case "cover-next-review":
        job = runScript("08n-base-review.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Edition", value: body.nextEdition || body.edition || "ebook" },
          { flag: "-Mode", value: body.mode || "auto" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], { route, bookName });
        break;
      case "cover-next-layout":
        job = runScript("08n-title-layout.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Edition", value: body.nextEdition || body.edition || "ebook" },
          { flag: "-Title", value: body.title || undefined },
          { flag: "-Subtitle", value: body.subtitle || undefined },
          { flag: "-Author", value: body.author || undefined },
          { flag: "-Mode", value: body.mode || "auto" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], { route, bookName });
        break;
      case "cover-next-image-edit":
        job = runScript("08n-image-edit.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Edition", value: body.nextEdition || body.edition || "ebook" },
          { flag: "-InputFile", value: body.inputFile || undefined },
          { flag: "-Title", value: body.title || undefined },
          { flag: "-Subtitle", value: body.subtitle || undefined },
          { flag: "-Author", value: body.author || undefined },
          { flag: "-Publisher", value: body.publisher || undefined },
          { flag: "-CoverText", value: body.coverText || undefined },
          { flag: "-ImageModel", value: body.imageModel || "gpt-image-1.5" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], { route, bookName });
        break;
      case "kdp-fix-image-edit":
        job = runScript("kdp-fix-image-edit.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-SourceFile", value: body.sourceFileName || undefined },
          { flag: "-PromptFile", value: body.promptFileName || undefined },
          { flag: "-Prompt", value: body.prompt || undefined },
          { flag: "-ImageModel", value: body.imageModel || "gpt-image-1.5" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], { route, bookName });
        break;
      case "kdp-acceptance-files":
        job = runScript("kdp-acceptance-files.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Action", value: body.action || "List" }
        ], { route, bookName });
        break;
      case "kdp-imagemagick-fix":
        job = runScript("kdp-imagemagick-fix.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-SourceFile", value: body.sourceFileName || undefined },
          { flag: "-InputEditFile", value: body.inputEditFileName || undefined },
          { flag: "-InstructionJson", value: body.instructionJson || undefined },
          { flag: "-InstructionFile", value: body.instructionFileName || undefined },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], { route, bookName });
        break;
      case "cover-next-print":
        job = runScript("08n-cover.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Edition", value: "print" },
          { flag: "-Title", value: body.title || undefined },
          { flag: "-Subtitle", value: body.subtitle || undefined },
          { flag: "-Author", value: body.author || undefined },
          { flag: "-Variants", value: body.variants || 4 },
          { flag: "-Mode", value: body.mode || "auto" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], { route, bookName });
        break;
      case "cover-next-mockup":
        job = runScript("08n-mockup.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Edition", value: body.nextEdition || body.edition || "ebook" },
          { flag: "-Mode", value: body.mode || "auto" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], { route, bookName });
        break;
      case "cover-next-export":
        job = runScript("08n-export.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Edition", value: body.nextEdition || body.edition || "ebook" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], { route, bookName });
        break;
      case "publish":
        job = runScript("09-publish.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Language", value: body.language || "zh" },
          { flag: "-Platform", value: body.platform || "all" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], { route, bookName });
        break;
      case "submit":
        if (!body.platform || body.platform === "all") {
          throw new Error("A specific platform is required for submit.");
        }
        {
          const submitParams = [
          { flag: "-BookName", value: bookName },
          { flag: "-Language", value: body.language || "zh" },
          { flag: "-Platform", value: body.platform },
          { flag: "-Mode", value: body.mode || "assist" },
          { flag: "-AttachChrome", type: "switch", enabled: ["google", "amazon"].includes(body.platform) && Boolean(body.attachChrome) },
          { flag: "-ChromeDebugPort", value: ["google", "amazon"].includes(body.platform) && Boolean(body.attachChrome) ? Number(body.chromeDebugPort || 9222) : undefined },
          { flag: "-ReuseSession", type: "switch", enabled: Boolean(body.reuseSession) },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
          ];

          if (["assist", "details", "content"].includes(body.mode || "assist")) {
            const submitMode = body.mode || "assist";
            const launchMessage = submitMode === "content" && body.platform === "amazon" && Boolean(body.attachChrome)
              ? "Amazon second-page session started in a new PowerShell window. It should attach to the current debugging browser window instead of opening a new login flow."
              : submitMode === "details" && body.platform === "amazon"
                ? "Amazon details-page session started in a new PowerShell window."
                : "Submit assist session started in a new PowerShell window. Browser automation will continue from there.";
            job = launchScriptInNewConsole("09f-submit.ps1", submitParams, { route, bookName }, launchMessage);
          } else {
            job = runScript("09f-submit.ps1", submitParams, { route, bookName });
          }
        }
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
      const paths = getWorkspacePaths(bookName);
      const outputPath = resolveOutputDocumentPath(paths, fileName);

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
      const fileName = body.fileName;

      validateBookName(bookName);

      const paths = getWorkspacePaths(bookName);
      const targetFolder = fileName
        ? path.dirname(resolveOutputDocumentPath(paths, fileName))
        : paths.outputRoot;

      if (!fs.existsSync(targetFolder)) {
        sendJson(res, 404, { error: "Output folder not found." });
        return;
      }

      openFolder(targetFolder);
      sendJson(res, 200, {
        opened: true,
        bookName,
        fileName: fileName || ""
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
      const paths = getWorkspacePaths(bookName);
      const outputPath = resolveOutputDocumentPath(paths, fileName);

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

  if (req.method === "GET" && url.pathname === "/api/publish") {
    const bookName = url.searchParams.get("bookName");
    const language = url.searchParams.get("language") || "zh";

    if (!bookName) {
      sendJson(res, 400, { error: "bookName is required." });
      return;
    }

    try {
      validateBookName(bookName);
      validateLanguageCode(language);
      const paths = getWorkspacePaths(bookName);
      sendJson(res, 200, {
        bookName,
        language,
        publish: getPublishArtifacts(paths.bookRoot, language)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/publish-metadata") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const language = body.language || "zh";

      validateBookName(bookName);
      validateLanguageCode(language);

      const paths = getWorkspacePaths(bookName);
      const publishRoot = getPublishLanguageRoot(paths.bookRoot, language);
      const metadataPath = path.join(publishRoot, "publish_metadata.json");

      if (!fs.existsSync(metadataPath)) {
        sendJson(res, 404, { error: "publish_metadata.json not found." });
        return;
      }

      const existing = readJsonFile(metadataPath);
      let nextMetadata;

      if (typeof body.metadataMarkdown === "string") {
        const parsed = parsePublishMetadataMarkdown(body.metadataMarkdown, existing);
        nextMetadata = {
          ...existing,
          title: parsed.title,
          subtitle: parsed.subtitle,
          author: parsed.author,
          language: parsed.language || existing.language || language,
          language_name: parsed.language_name || existing.language_name,
          publisher: parsed.publisher,
          imprint: parsed.imprint,
          edition_type: parsed.edition_type || existing.edition_type,
          publication_date: parsed.publication_date,
          rights: parsed.rights,
          copyright_holder: parsed.copyright_holder || existing.copyright_holder,
          territory: parsed.territory,
          distribution_rights: parsed.distribution_rights,
          short_description: parsed.short_description,
          long_description: parsed.long_description,
          marketing_tagline: parsed.marketing_tagline,
          cover_hook: parsed.cover_hook,
          back_cover_blurb: parsed.back_cover_blurb,
          obi_copy: parsed.obi_copy,
          author_bio: parsed.author_bio,
          spine_text: parsed.spine_text,
          keywords: parsed.keywords,
          categories: parsed.categories,
          formats: parsed.formats,
          platform_recommended_categories: parsed.platform_recommended_categories,
          platform_selected_categories: parsed.platform_selected_categories
        };
      } else {
        const keywords = sanitizeList(body.keywords);
        const categories = sanitizeList(body.categories);
        const selectedPlatformCategories = body.selectedPlatformCategories && typeof body.selectedPlatformCategories === "object"
          ? body.selectedPlatformCategories
          : (existing.platform_selected_categories || {});

        const title = sanitizeText(body.title || existing.title);
        const subtitle = sanitizeText(body.subtitle || existing.subtitle);
        const author = sanitizeText(body.author || existing.author);
        const publisher = sanitizeText(body.publisher || existing.publisher);
        const imprint = sanitizeText(body.imprint || existing.imprint);
        const publicationDate = sanitizeText(body.publicationDate || existing.publication_date);
        const rights = sanitizeText(body.rights || existing.rights);
        const territory = sanitizeText(body.territory || existing.territory);
        const distributionRights = sanitizeText(body.distributionRights || existing.distribution_rights);
        const shortDescription = sanitizeText(body.shortDescription || existing.short_description);
        const longDescription = sanitizeText(body.longDescription || existing.long_description);
        const marketingTagline = sanitizeText(body.marketingTagline || existing.marketing_tagline);
        const coverHook = sanitizeText(body.coverHook || existing.cover_hook);
        const backCoverBlurb = sanitizeText(body.backCoverBlurb || existing.back_cover_blurb);
        const obiCopy = sanitizeText(body.obiCopy || existing.obi_copy);
        const authorBio = sanitizeText(body.authorBio || existing.author_bio);
        const spineText = sanitizeText(body.spineText || existing.spine_text);

        nextMetadata = {
          ...existing,
          title,
          subtitle,
          author,
          publisher,
          imprint,
          publication_date: publicationDate,
          rights,
          territory,
          distribution_rights: distributionRights,
          short_description: shortDescription,
          long_description: longDescription,
          marketing_tagline: marketingTagline,
          cover_hook: coverHook,
          back_cover_blurb: backCoverBlurb,
          obi_copy: obiCopy,
          author_bio: authorBio,
          spine_text: spineText,
          keywords,
          categories,
          platform_selected_categories: {
            amazon: sanitizeText(selectedPlatformCategories.amazon),
            apple: sanitizeText(selectedPlatformCategories.apple),
            google: sanitizeText(selectedPlatformCategories.google)
          }
        };
      }

      nextMetadata.identification = {
        ...(existing.identification || {}),
        title: nextMetadata.title,
        subtitle: nextMetadata.subtitle,
        author: nextMetadata.author,
        publication_date: nextMetadata.publication_date,
        publisher: nextMetadata.publisher,
        imprint: nextMetadata.imprint
      };

      nextMetadata.marketing = {
        ...(existing.marketing || {}),
        tagline: nextMetadata.marketing_tagline,
        subtitle: nextMetadata.subtitle,
        short_description: nextMetadata.short_description,
        long_description: nextMetadata.long_description,
        cover_hook: nextMetadata.cover_hook,
        back_cover_blurb: nextMetadata.back_cover_blurb,
        obi_copy: nextMetadata.obi_copy,
        author_bio: nextMetadata.author_bio,
        spine_text: nextMetadata.spine_text
      };

      nextMetadata.rights_metadata = {
        ...(existing.rights_metadata || {}),
        rights_statement: nextMetadata.rights,
        territory: nextMetadata.territory,
        distribution_rights: nextMetadata.distribution_rights,
        publisher: nextMetadata.publisher,
        imprint: nextMetadata.imprint
      };

      nextMetadata.discovery = {
        ...(existing.discovery || {}),
        keywords: nextMetadata.keywords || [],
        categories: nextMetadata.categories || [],
        platform_recommended_categories: nextMetadata.platform_recommended_categories || existing.platform_recommended_categories || existing.discovery?.platform_recommended_categories || {},
        platform_selected_categories: {
          amazon: sanitizeText(nextMetadata.platform_selected_categories?.amazon),
          apple: sanitizeText(nextMetadata.platform_selected_categories?.apple),
          google: sanitizeText(nextMetadata.platform_selected_categories?.google)
        }
      };

      if (typeof body.metadataMarkdown === "string") {
        if (!Array.isArray(nextMetadata.keywords) || !nextMetadata.keywords.length) {
          nextMetadata.keywords = sanitizeList(extractMarkdownBulletSection(body.metadataMarkdown, "Keywords"));
          nextMetadata.discovery.keywords = nextMetadata.keywords;
        }
        if (!Array.isArray(nextMetadata.categories) || !nextMetadata.categories.length) {
          nextMetadata.categories = sanitizeList(extractMarkdownBulletSection(body.metadataMarkdown, "Categories"));
          nextMetadata.discovery.categories = nextMetadata.categories;
        }
        if (!Array.isArray(nextMetadata.formats) || !nextMetadata.formats.length) {
          nextMetadata.formats = sanitizeList(extractMarkdownBulletSection(body.metadataMarkdown, "Formats"));
        }
      }

      syncPublishMetadataFiles(paths.bookRoot, language, nextMetadata);

      sendJson(res, 200, {
        saved: true,
        bookName,
        language,
        publish: getPublishArtifacts(paths.bookRoot, language)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/amazon-description") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const language = body.language || "zh";
      const descriptionText = sanitizeText(body.descriptionText);

      validateBookName(bookName);
      validateLanguageCode(language);

      if (!descriptionText) {
        sendJson(res, 400, { error: "Description text is required." });
        return;
      }

      const paths = getWorkspacePaths(bookName);
      const publishRoot = getPublishLanguageRoot(paths.bookRoot, language);
      const amazonRoot = path.join(publishRoot, "amazon");
      const textPath = path.join(amazonRoot, "amazon_description.txt");
      const htmlPath = path.join(amazonRoot, "amazon_description.html");
      const sourceMarkdownPath = getLocalizedAmazonDescriptionSourcePath(paths.bookRoot, language);
      const metadata = readJsonFileSafe(path.join(publishRoot, "publish_metadata.json")) || {};

      ensureDir(amazonRoot);
      ensureDir(path.dirname(sourceMarkdownPath));
      fs.writeFileSync(textPath, `${descriptionText}\n`, "utf8");
      fs.writeFileSync(htmlPath, `${convertPlainTextToAmazonHtml(descriptionText)}\n`, "utf8");
      fs.writeFileSync(
        sourceMarkdownPath,
        buildAmazonDescriptionSourceMarkdown({
          metadata,
          language,
          descriptionText
        }),
        "utf8"
      );

      sendJson(res, 200, {
        saved: true,
        bookName,
        language,
        textFileName: path.basename(textPath),
        textPath: path.relative(paths.bookRoot, textPath),
        textFullPath: textPath,
        htmlFileName: path.basename(htmlPath),
        htmlPath: path.relative(paths.bookRoot, htmlPath),
        htmlFullPath: htmlPath,
        sourceMarkdownFileName: path.basename(sourceMarkdownPath),
        sourceMarkdownPath: path.relative(paths.bookRoot, sourceMarkdownPath),
        sourceMarkdownFullPath: sourceMarkdownPath,
        publish: getPublishArtifacts(paths.bookRoot, language)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/open-publish-folder") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const language = body.language || "zh";
      const platform = body.platform || "";

      validateBookName(bookName);
      validateLanguageCode(language);
      validatePublishPlatform(platform);

      const paths = getWorkspacePaths(bookName);
      const targetFolder = resolvePublishSectionRoot(paths, language, platform || "");

      if (!fs.existsSync(targetFolder)) {
        sendJson(res, 404, { error: "Publish folder not found." });
        return;
      }

      openFolder(targetFolder);
      sendJson(res, 200, {
        opened: true,
        bookName,
        language,
        platform
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/open-folder-test") {
    try {
      const body = await readJsonBody(req);
      const folderPath = validateAbsoluteFolderPath(body.folderPath);
      openFolder(folderPath);
      sendJson(res, 200, { opened: true, folderPath });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/reveal-publish-file") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const language = body.language || "zh";
      const platform = body.platform || "";
      const fileName = body.fileName;

      validateBookName(bookName);
      validateLanguageCode(language);
      validatePublishPlatform(platform);
      validatePublishFileName(fileName);

      const paths = getWorkspacePaths(bookName);
      const targetRoot = resolvePublishSectionRoot(paths, language, platform || "");
      const targetPath = path.join(targetRoot, path.basename(fileName));

      if (!targetPath.startsWith(targetRoot)) {
        sendJson(res, 403, { error: "Forbidden." });
        return;
      }

      if (!fs.existsSync(targetPath)) {
        sendJson(res, 404, { error: "Publish file not found." });
        return;
      }

      revealFileInExplorer(targetPath);
      sendJson(res, 200, {
        opened: true,
        bookName,
        language,
        platform,
        fileName
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/open-publish-file") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const language = body.language || "zh";
      const platform = body.platform || "";
      const fileName = body.fileName;

      validateBookName(bookName);
      validateLanguageCode(language);
      validatePublishPlatform(platform);
      validatePublishFileName(fileName);

      const paths = getWorkspacePaths(bookName);
      const targetRoot = resolvePublishSectionRoot(paths, language, platform || "");
      const targetPath = path.join(targetRoot, path.basename(fileName));

      if (!targetPath.startsWith(targetRoot)) {
        sendJson(res, 403, { error: "Forbidden." });
        return;
      }

      if (!fs.existsSync(targetPath)) {
        sendJson(res, 404, { error: "Publish file not found." });
        return;
      }

      openFileWithDefaultApp(targetPath);
      sendJson(res, 200, {
        opened: true,
        bookName,
        language,
        platform,
        fileName
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/generate-kobo-account-md") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const language = body.language || "zh";

      validateBookName(bookName);
      validateLanguageCode(language);

      const paths = getWorkspacePaths(bookName);
      const publishRoot = getPublishLanguageRoot(paths.bookRoot, language);
      const koboRoot = path.join(publishRoot, "kobo");
      const metadataPath = path.join(publishRoot, "publish_metadata.json");
      const objectivePath = path.join(paths.bookRoot, "00_brief", "objective.md");
      const outputPath = path.join(koboRoot, "kobo_account_basic_info.md");

      ensureDir(publishRoot);
      ensureDir(koboRoot);

      const metadata = readJsonFileSafe(metadataPath) || {};
      const objectiveData = parseFrontMatterMarkdown(objectivePath) || {};
      const markdown = buildKoboAccountBasicInfoMarkdown({
        bookName,
        language,
        metadata,
        objectiveData
      });

      fs.writeFileSync(outputPath, markdown, "utf8");
      openFileWithDefaultApp(outputPath);

      sendJson(res, 200, {
        generated: true,
        bookName,
        language,
        fileName: "kobo_account_basic_info.md",
        relativePath: path.relative(paths.bookRoot, outputPath)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && /^\/api\/jobs\/[^/]+\/cancel$/.test(url.pathname)) {
    const jobId = url.pathname.split("/")[3];
    const job = jobs.get(jobId);
    if (!job) {
      sendJson(res, 404, { error: "Job not found." });
      return;
    }

    try {
      cancelJob(job);
      sendJson(res, 200, { ok: true, job });
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

  if (req.method === "GET" && url.pathname === "/api/cover-files") {
    const bookName = url.searchParams.get("bookName");

    if (!bookName) {
      sendJson(res, 400, { error: "bookName is required." });
      return;
    }

    try {
      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);
      const artifacts = getCoverArtifacts(paths.bookRoot);
      sendJson(res, 200, {
        bookName,
        coverArtifacts: artifacts
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/kdp-acceptance") {
    const bookName = url.searchParams.get("bookName");

    if (!bookName) {
      sendJson(res, 400, { error: "bookName is required." });
      return;
    }

    try {
      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);
      sendJson(res, 200, {
        bookName,
        kdpAcceptance: getKdpAcceptanceState(paths.bookRoot)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/kdp-acceptance-files") {
    const bookName = url.searchParams.get("bookName");
    try {
      validateBookName(bookName);
      const result = runPowerShellJson("kdp-acceptance-files.ps1", [
        { flag: "-BookName", value: bookName },
        { flag: "-Action", value: "List" }
      ]);
      sendJson(res, 200, result || { bookName, files: [] });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/kdp-acceptance-file") {
    const bookName = url.searchParams.get("bookName");
    const fileName = url.searchParams.get("fileName");
    try {
      const resolved = resolveKdpAcceptanceFilePath(bookName, fileName, [".pdf", ".png"]);
      res.writeHead(200, {
        "Content-Type": resolved.ext === ".pdf" ? "application/pdf" : "image/png",
        "Cache-Control": "no-store",
        "Content-Disposition": `inline; filename="${path.basename(resolved.targetPath).replace(/"/g, "")}"`
      });
      res.end(fs.readFileSync(resolved.targetPath));
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/kdp-acceptance-pdf") {
    const bookName = url.searchParams.get("bookName");
    const fileName = url.searchParams.get("fileName");

    if (!bookName || !fileName) {
      sendJson(res, 400, { error: "bookName and fileName are required." });
      return;
    }

    try {
      if (!/\.pdf$/i.test(fileName)) {
        throw new Error("Only PDF files can be previewed here.");
      }
      const resolved = resolveKdpAcceptanceFilePath(bookName, fileName, [".pdf"]);

      res.writeHead(200, {
        "Content-Type": "application/pdf",
        "Cache-Control": "no-store",
        "Content-Disposition": `inline; filename="${path.basename(resolved.targetPath).replace(/"/g, "")}"`
      });
      res.end(fs.readFileSync(resolved.targetPath));
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/kdp-acceptance-existing-file") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const fileName = body.fileName;
      const resolved = resolveKdpAcceptanceFilePath(bookName, fileName, [".pdf", ".png"]);
      if (resolved.ext === ".png") {
        const currentSource = writeKdpCurrentSource(resolved.acceptanceRoot, buildKdpCurrentSource({
          type: "PNG",
          fileName: resolved.relativePath,
          relativePath: resolved.relativePath
        }));
        sendJson(res, 200, {
          bookName,
          fileType: "png",
          fileName: resolved.relativePath,
          currentSource,
          fileUrl: `/api/kdp-acceptance-file?bookName=${encodeURIComponent(bookName)}&fileName=${encodeURIComponent(resolved.relativePath)}`,
          kdpAcceptance: getKdpAcceptanceState(resolved.paths.bookRoot)
        });
        return;
      }

      const spec = buildKdpPaperbackCoverSpec({
        trimWidthIn: body.trimWidthIn,
        trimHeightIn: body.trimHeightIn,
        bleedIn: body.bleedIn,
        pageCount: body.pageCount,
        paperType: body.paperType
      });
      const pdfInfo = parsePdfInfo(resolved.targetPath);
      const report = buildKdpAcceptanceReport({
        bookName,
        pdfFileName: resolved.relativePath,
        pdfPath: resolved.targetPath,
        pdfInfo,
        spec
      });
      const reportPath = path.join(resolved.acceptanceRoot, "kdp_acceptance_report.json");
      const reportTextPath = path.join(resolved.acceptanceRoot, "kdp_acceptance_report.md");
      writeJsonFile(reportPath, report);
      fs.writeFileSync(reportTextPath, buildKdpAcceptanceMarkdown(report), "utf8");
      const currentSource = writeKdpCurrentSource(resolved.acceptanceRoot, buildKdpCurrentSource({
        type: "PDF",
        fileName: resolved.relativePath,
        relativePath: resolved.relativePath
      }));

      sendJson(res, 200, {
        bookName,
        fileType: "pdf",
        fileName: resolved.relativePath,
        currentSource,
        kdpAcceptance: getKdpAcceptanceState(resolved.paths.bookRoot)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/kdp-acceptance") {
    try {
      const body = await readJsonBody(req, 120_000_000);
      const bookName = body.bookName;
      const dataUrl = typeof body.dataUrl === "string" ? body.dataUrl : "";
      const originalName = typeof body.fileName === "string" ? body.fileName : "cover-upload.pdf";

      validateBookName(bookName);
      const match = dataUrl.match(/^data:(application\/pdf|application\/octet-stream);base64,([A-Za-z0-9+/=\r\n]+)$/);
      if (!match) {
        throw new Error("Invalid PDF data.");
      }

      const buffer = Buffer.from(match[2].replace(/\s/g, ""), "base64");
      if (!buffer.length) {
        throw new Error("PDF file is empty.");
      }
      if (buffer.length > 90_000_000) {
        throw new Error("PDF file is too large for the local acceptance preview.");
      }
      if (buffer.slice(0, 5).toString("latin1") !== "%PDF-") {
        throw new Error("Uploaded file does not look like a PDF.");
      }

      const paths = getWorkspacePaths(bookName);
      const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
      ensureDir(acceptanceRoot);

      const safeOriginalName = sanitizeImportedPdfFileName(originalName);
      const fileName = getUniqueFileName(acceptanceRoot, safeOriginalName);
      const targetPath = path.resolve(acceptanceRoot, fileName);
      const rootResolved = path.resolve(acceptanceRoot);
      if (!targetPath.startsWith(rootResolved + path.sep)) {
        throw new Error("Invalid PDF target path.");
      }

      fs.writeFileSync(targetPath, buffer);
      const spec = buildKdpPaperbackCoverSpec({
        trimWidthIn: body.trimWidthIn,
        trimHeightIn: body.trimHeightIn,
        bleedIn: body.bleedIn,
        pageCount: body.pageCount,
        paperType: body.paperType,
        spineWidthIn: body.useCustomSpineWidth ? body.spineWidthIn : undefined
      });
      const pdfInfo = parsePdfInfo(targetPath);
      const report = buildKdpAcceptanceReport({
        bookName,
        pdfFileName: fileName,
        pdfPath: targetPath,
        pdfInfo,
        spec
      });
      const reportPath = path.join(acceptanceRoot, "kdp_acceptance_report.json");
      const reportTextPath = path.join(acceptanceRoot, "kdp_acceptance_report.md");
      writeJsonFile(reportPath, report);
      fs.writeFileSync(reportTextPath, buildKdpAcceptanceMarkdown(report), "utf8");
      writeKdpCurrentSource(acceptanceRoot, buildKdpCurrentSource({
        type: "PDF",
        fileName,
        relativePath: fileName,
        originalFileName: originalName
      }));

      sendJson(res, 200, {
        bookName,
        kdpAcceptance: getKdpAcceptanceState(paths.bookRoot)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/kdp-acceptance-png") {
    try {
      const body = await readJsonBody(req, 120_000_000);
      const bookName = body.bookName;
      const dataUrl = typeof body.dataUrl === "string" ? body.dataUrl : "";
      const originalName = typeof body.fileName === "string" ? body.fileName : "cover-upload.png";

      validateBookName(bookName);
      const match = dataUrl.match(/^data:image\/png;base64,([A-Za-z0-9+/=\r\n]+)$/);
      if (!match) {
        throw new Error("Invalid PNG data.");
      }
      const buffer = Buffer.from(match[1].replace(/\s/g, ""), "base64");
      if (!buffer.length) {
        throw new Error("PNG file is empty.");
      }
      if (buffer.length > 90_000_000) {
        throw new Error("PNG file is too large for the local acceptance preview.");
      }
      if (buffer.slice(0, 8).toString("hex") !== "89504e470d0a1a0a") {
        throw new Error("Uploaded file does not look like a PNG.");
      }

      const paths = getWorkspacePaths(bookName);
      const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
      ensureDir(acceptanceRoot);
      const safeOriginalName = sanitizeImportedImageFileName(originalName, ".png");
      const fileName = getUniqueFileName(acceptanceRoot, safeOriginalName);
      const targetPath = path.resolve(acceptanceRoot, fileName);
      const rootResolved = path.resolve(acceptanceRoot);
      if (!targetPath.startsWith(rootResolved + path.sep)) {
        throw new Error("Invalid PNG target path.");
      }
      fs.writeFileSync(targetPath, buffer);
      const currentSource = writeKdpCurrentSource(acceptanceRoot, buildKdpCurrentSource({
        type: "PNG",
        fileName,
        relativePath: fileName,
        originalFileName: originalName
      }));

      sendJson(res, 200, {
        bookName,
        fileType: "png",
        fileName,
        currentSource,
        fileUrl: `/api/kdp-acceptance-file?bookName=${encodeURIComponent(bookName)}&fileName=${encodeURIComponent(fileName)}`,
        kdpAcceptance: getKdpAcceptanceState(paths.bookRoot)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/kdp-llm-text-regions") {
    try {
      const body = await readJsonBody(req, 80_000_000);
      const bookName = body.bookName;
      const imageDataUrl = typeof body.imageDataUrl === "string" ? body.imageDataUrl : "";
      const sourceRelativePath = typeof body.sourceRelativePath === "string" ? body.sourceRelativePath : "";
      let imageWidth = Math.round(Number(body.imageWidth || 0));
      let imageHeight = Math.round(Number(body.imageHeight || 0));
      const model = typeof body.model === "string" && body.model.trim() ? body.model.trim() : "gpt-5.2";

      validateBookName(bookName);
      if (!process.env.OPENAI_API_KEY) {
        throw new Error("OPENAI_API_KEY not set.");
      }
      const paths = getWorkspacePaths(bookName);
      const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
      const visionRoot = path.join(acceptanceRoot, "llm_text_regions");
      ensureDir(visionRoot);
      const stamp = formatCompactFileStamp();
      let imageBuffer = null;
      let sourcePath = "";
      let imageFileName = "";
      if (sourceRelativePath) {
        const resolved = resolveKdpAcceptanceFilePath(bookName, sourceRelativePath, [".png"]);
        sourcePath = resolved.targetPath;
        imageBuffer = fs.readFileSync(sourcePath);
        const dimensions = getPngDimensions(imageBuffer);
        imageWidth = dimensions.width;
        imageHeight = dimensions.height;
        imageFileName = getUniqueFileName(visionRoot, `llm-${path.basename(resolved.relativePath)}`);
      } else {
        if (!/^data:image\/png;base64,[A-Za-z0-9+/=\r\n]+$/.test(imageDataUrl)) {
          throw new Error("imageDataUrl must be a PNG data URL unless sourceRelativePath is provided.");
        }
        imageBuffer = Buffer.from(imageDataUrl.replace(/^data:image\/png;base64,/, "").replace(/\s/g, ""), "base64");
        const dimensions = getPngDimensions(imageBuffer);
        imageWidth = imageWidth || dimensions.width;
        imageHeight = imageHeight || dimensions.height;
        imageFileName = `kdp-llm-text-${stamp}.png`;
      }
      if (imageWidth < 100 || imageHeight < 100) {
        throw new Error("imageWidth and imageHeight are required.");
      }
      const baseFileName = path.basename(imageFileName, ".png");
      const resultFileName = `${baseFileName}.json`;
      const latestFileName = "latest_llm_text_regions.json";
      const imagePath = path.join(visionRoot, imageFileName);
      const resultPath = path.join(visionRoot, resultFileName);
      const latestPath = path.join(visionRoot, latestFileName);
      fs.writeFileSync(imagePath, imageBuffer);
      const llmImageDataUrl = `data:image/png;base64,${imageBuffer.toString("base64")}`;

      const prompt = [
        "You are inspecting a flattened PNG render of a KDP paperback full-cover PDF.",
        `The PNG size is ${imageWidth} x ${imageHeight} pixels. The coordinate origin is the top-left corner.`,
        "Your only task is to detect visible text regions and return their full pixel bounding boxes.",
        "Do not classify regions as front/back/spine. Do not crop, clamp, or force a text box into any book area. If text crosses a fold, trim, margin, or panel boundary, return the full bounding box that covers the visible text.",
        "Ignore stars, dots, guide lines, light rays, decorative borders, book art, barcode lines, and non-text ornaments.",
        "Return bounding boxes for coherent text blocks, not every tiny speck. Split by natural text blocks: title, subtitle, author, spine title, publisher/logo text, back-cover paragraphs.",
        "Coordinates must be pixel coordinates in the provided PNG, origin at top-left, x/y/width/height integers.",
        "Use notes to state whether the text appears on the front cover, book spine, or back cover when visually clear.",
        "Return JSON only with this schema:",
        '{"image":{"width":number,"height":number},"regions":[{"id":"string","text":"visible text if readable","x":number,"y":number,"width":number,"height":number,"confidence":0-1,"orientation":"horizontal|vertical|rotated|unknown","notes":"front cover|book spine|back cover + short detail"}]}'
      ].join("\n");

      const response = await fetch("https://api.openai.com/v1/responses", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${process.env.OPENAI_API_KEY}`,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          model,
          input: [
            {
              role: "user",
              content: [
                { type: "input_text", text: prompt },
                { type: "input_image", image_url: llmImageDataUrl }
              ]
            }
          ]
        })
      });

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`OpenAI vision request failed (${response.status}): ${errorText.slice(0, 500)}`);
      }

      const responseJson = await response.json();
      const modelText = extractResponseText(responseJson);
      const parsed = parseJsonFromModelText(modelText);
      const modelImageWidth = Math.max(1, Math.round(Number(parsed?.image?.width || imageWidth)));
      const modelImageHeight = Math.max(1, Math.round(Number(parsed?.image?.height || imageHeight)));
      const coordinateScale = {
        x: imageWidth / modelImageWidth,
        y: imageHeight / modelImageHeight
      };
      const regions = (Array.isArray(parsed.regions) ? parsed.regions : [])
        .map((region, index) => normalizeVisionRegion(region, index, imageWidth, imageHeight, coordinateScale))
        .filter((region) => region.width > 0 && region.height > 0);
      const savedResult = {
        bookName,
        createdAt: formatLocalTimestamp(),
        model,
        prompt,
        image: {
          width: imageWidth,
          height: imageHeight,
          fileName: imageFileName,
          path: imagePath,
          bytes: imageBuffer.length,
          sourcePath,
          sourceRelativePath: sourceRelativePath || ""
        },
        modelImage: {
          width: modelImageWidth,
          height: modelImageHeight
        },
        coordinateScale,
        regions,
        parsed,
        rawText: modelText,
        usage: responseJson.usage || null,
        responseId: responseJson.id || "",
        responseCreatedAt: responseJson.created_at || null,
        responseStatus: responseJson.status || "",
        rawResponse: responseJson
      };
      writeJsonFile(resultPath, savedResult);
      writeJsonFile(latestPath, savedResult);
      appendJsonLine(path.join(visionRoot, "llm_text_regions_runs.jsonl"), {
        bookName,
        createdAt: savedResult.createdAt,
        model,
        resultFileName,
        imageFileName,
        image: savedResult.image,
        modelImage: savedResult.modelImage,
        coordinateScale,
        regionCount: regions.length,
        usage: savedResult.usage
      });

      sendJson(res, 200, {
        bookName,
        model,
        image: {
          width: imageWidth,
          height: imageHeight
        },
        modelImage: {
          width: modelImageWidth,
          height: modelImageHeight
        },
        coordinateScale,
        regions,
        rawText: modelText,
        usage: responseJson.usage || null,
        responseId: responseJson.id || "",
        responseStatus: responseJson.status || "",
        createdAt: savedResult.createdAt,
        saved: {
          resultFileName,
          imageFileName,
          latestFileName,
          resultRelativePath: `07_cover/kdp_acceptance/llm_text_regions/${resultFileName}`,
          imageRelativePath: `07_cover/kdp_acceptance/llm_text_regions/${imageFileName}`,
          latestRelativePath: `07_cover/kdp_acceptance/llm_text_regions/${latestFileName}`,
          resultPath,
          imagePath,
          latestPath
        }
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/kdp-fix-report") {
    try {
      const body = await readJsonBody(req, 10_000_000);
      const bookName = body.bookName;
      const reportText = typeof body.reportText === "string" ? body.reportText : "";
      const spec = body.spec && typeof body.spec === "object" ? body.spec : null;
      const source = body.source && typeof body.source === "object" ? body.source : {};
      const textRegionCount = Math.max(0, Math.round(Number(body.textRegionCount || 0)));

      validateBookName(bookName);
      if (!reportText.trim()) {
        throw new Error("reportText is required.");
      }

      const paths = getWorkspacePaths(bookName);
      const reportRoot = path.join(getKdpAcceptanceRoot(paths.bookRoot), "fix_reports");
      const backupRoot = path.join(reportRoot, "back");
      ensureDir(reportRoot);
      ensureDir(backupRoot);

      const createdAtDate = new Date();
      const createdAt = formatLocalTimestamp(createdAtDate);
      const stamp = formatCompactFileStamp(createdAtDate);
      const baseFileName = `kdp-fix-report-${stamp}`;
      const textFileName = `${baseFileName}.md`;
      const resultFileName = `${baseFileName}.json`;
      const textPath = path.join(reportRoot, textFileName);
      const resultPath = path.join(reportRoot, resultFileName);
      const latestTextPath = path.join(reportRoot, "latest_kdp_fix_report.md");
      const latestJsonPath = path.join(reportRoot, "latest_kdp_fix_report.json");
      const backups = [];

      if (fs.existsSync(latestTextPath)) {
        const backupTextName = `latest_kdp_fix_report.back-${stamp}.md`;
        const backupTextPath = path.join(backupRoot, backupTextName);
        fs.copyFileSync(latestTextPath, backupTextPath);
        backups.push({ type: "text", fileName: backupTextName, path: backupTextPath });
      }
      if (fs.existsSync(latestJsonPath)) {
        const backupJsonName = `latest_kdp_fix_report.back-${stamp}.json`;
        const backupJsonPath = path.join(backupRoot, backupJsonName);
        fs.copyFileSync(latestJsonPath, backupJsonPath);
        backups.push({ type: "json", fileName: backupJsonName, path: backupJsonPath });
      }

      const savedReportText = formatKdpFixReportWithHeader(reportText, { createdAt, bookName, source });
      const savedResult = {
        bookName,
        createdAt,
        reportText: savedReportText,
        spec,
        source,
        textRegionCount,
        saved: {
          resultFileName,
          textFileName,
          latestFileName: "latest_kdp_fix_report.json",
          latestTextFileName: "latest_kdp_fix_report.md",
          resultPath,
          textPath,
          latestPath: latestJsonPath,
          latestTextPath,
          backupDir: backupRoot,
          backups
        }
      };

      fs.writeFileSync(textPath, savedReportText, "utf8");
      writeJsonFile(resultPath, savedResult);
      fs.writeFileSync(latestTextPath, savedReportText, "utf8");
      writeJsonFile(latestJsonPath, savedResult);
      appendJsonLine(path.join(reportRoot, "kdp_fix_report_runs.jsonl"), {
        bookName,
        createdAt: savedResult.createdAt,
        resultFileName,
        textFileName,
        source,
        textRegionCount,
        backups: backups.map((backup) => backup.fileName)
      });

      sendJson(res, 200, {
        bookName,
        fixReport: getKdpLatestFixReportState(getKdpAcceptanceRoot(paths.bookRoot)),
        saved: savedResult.saved
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/kdp-fix-workbench/prepare") {
    try {
      const body = await readJsonBody(req, 80_000_000);
      const bookName = body.bookName;
      const imageDataUrl = typeof body.imageDataUrl === "string" ? body.imageDataUrl : "";
      const prompt = typeof body.prompt === "string" ? body.prompt : "";
      const model = typeof body.model === "string" && body.model.trim() ? body.model.trim() : "gpt-image-1.5";
      const imageWidth = Math.round(Number(body.imageWidth || 0));
      const imageHeight = Math.round(Number(body.imageHeight || 0));

      validateBookName(bookName);
      if (!/^data:image\/png;base64,[A-Za-z0-9+/=\r\n]+$/.test(imageDataUrl)) {
        throw new Error("imageDataUrl must be a PNG data URL.");
      }
      if (!prompt.trim()) {
        throw new Error("prompt is required.");
      }
      if (imageWidth < 100 || imageHeight < 100) {
        throw new Error("imageWidth and imageHeight are required.");
      }

      const paths = getWorkspacePaths(bookName);
      const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
      const workRoot = getKdpFixWorkbenchRoot(acceptanceRoot);
      const sourceRoot = path.join(workRoot, "source");
      const promptRoot = path.join(workRoot, "prompts");
      ensureDir(sourceRoot);
      ensureDir(promptRoot);
      const stamp = formatCompactFileStamp();
      const sourceFileName = `kdp-fix-source-${stamp}.png`;
      const promptFileName = `kdp-fix-prompt-${stamp}.txt`;
      const sourcePath = path.join(sourceRoot, sourceFileName);
      const promptPath = path.join(promptRoot, promptFileName);
      const imageBuffer = Buffer.from(imageDataUrl.replace(/^data:image\/png;base64,/, "").replace(/\s/g, ""), "base64");
      fs.writeFileSync(sourcePath, imageBuffer);
      fs.writeFileSync(promptPath, prompt, "utf8");

      const statePath = path.join(workRoot, "workbench_state.json");
      const existing = readJsonFileSafe(statePath) || {};
      const nextState = {
        ...existing,
        updatedAt: formatLocalTimestamp(),
        model,
        sourceFileName,
        sourcePath,
        sourceImage: {
          width: imageWidth,
          height: imageHeight,
          bytes: imageBuffer.length
        },
        promptFileName,
        promptPath,
        prompt
      };
      writeJsonFile(statePath, nextState);
      const currentSource = writeKdpCurrentSource(acceptanceRoot, buildKdpCurrentSource({
        type: "PNG",
        directory: "07_cover/kdp_acceptance",
        fileName: `fix_workbench/source/${sourceFileName}`,
        relativePath: `fix_workbench/source/${sourceFileName}`
      }));
      sendJson(res, 200, {
        bookName,
        prepared: true,
        currentSource,
        fixWorkbench: getKdpFixWorkbenchState(acceptanceRoot)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/kdp-img-black/crop") {
    try {
      const body = await readJsonBody(req, 1_000_000);
      const bookName = body.bookName;
      const sourceFileName = typeof body.sourceFileName === "string" ? body.sourceFileName : "";
      const x = Math.round(Number(body.x));
      const y = Math.round(Number(body.y));
      const width = Math.round(Number(body.width));
      const height = Math.round(Number(body.height));

      validateBookName(bookName);
      if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(width) || !Number.isFinite(height)) {
        throw new Error("x, y, width, and height are required numbers.");
      }
      if (x < 0 || y < 0 || width <= 0 || height <= 0) {
        throw new Error("x/y must be >= 0 and width/height must be > 0.");
      }

      const result = runPowerShellJson("kdp-crop-image-region.ps1", [
        { flag: "-BookName", value: bookName },
        { flag: "-SourceFile", value: sourceFileName || undefined },
        { flag: "-X", value: x },
        { flag: "-Y", value: y },
        { flag: "-Width", value: width },
        { flag: "-Height", value: height },
        { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
      ]);
      const paths = getWorkspacePaths(bookName);
      const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
      sendJson(res, 200, {
        bookName,
        crop: result,
        cropImageUrl: result?.outputFileName
          ? `/api/kdp-fix-image?bookName=${encodeURIComponent(bookName)}&kind=crop&fileName=${encodeURIComponent(result.outputFileName)}&t=${Date.now()}`
          : "",
        fixWorkbench: getKdpFixWorkbenchState(acceptanceRoot)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/kdp-img-black/resize") {
    try {
      const body = await readJsonBody(req, 1_000_000);
      const bookName = body.bookName;
      const inputFileName = typeof body.inputFileName === "string" ? body.inputFileName : "";
      const scalePercent = Number(body.scalePercent);

      validateBookName(bookName);
      if (!Number.isFinite(scalePercent) || scalePercent <= 1 || scalePercent > 400) {
        throw new Error("scalePercent must be > 1 and <= 400.");
      }

      const result = runPowerShellJson("kdp-resize-image-region.ps1", [
        { flag: "-BookName", value: bookName },
        { flag: "-InputFile", value: inputFileName || undefined },
        { flag: "-ScalePercent", value: scalePercent },
        { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
      ]);
      const paths = getWorkspacePaths(bookName);
      const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
      sendJson(res, 200, {
        bookName,
        resize: result,
        crop: result,
        cropImageUrl: result?.outputFileName
          ? `/api/kdp-fix-image?bookName=${encodeURIComponent(bookName)}&kind=crop&fileName=${encodeURIComponent(result.outputFileName)}&t=${Date.now()}`
          : "",
        fixWorkbench: getKdpFixWorkbenchState(acceptanceRoot)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/kdp-img-black/state") {
    try {
      const body = await readJsonBody(req, 1_000_000);
      const bookName = body.bookName;
      const uiState = body.uiState && typeof body.uiState === "object" ? body.uiState : {};
      validateBookName(bookName);

      const cleanNumber = (value, fallback = "") => {
        if (value === "" || value === null || value === undefined) return fallback;
        const number = Math.round(Number(value));
        return Number.isFinite(number) ? number : fallback;
      };
      const cleanColor = (value, fallback = "#07121b") => {
        const text = String(value || "").trim();
        return /^#[0-9a-fA-F]{6}$/.test(text) ? text : fallback;
      };
      const cleanPreset = String(uiState.fill?.preset || "").trim();
      const cleanMode = String(uiState.fill?.mode || "Auto").trim();
      const nextUiState = {
        updatedAt: formatLocalTimestamp(),
        crop: {
          x: cleanNumber(uiState.crop?.x),
          y: cleanNumber(uiState.crop?.y),
          width: cleanNumber(uiState.crop?.width),
          height: cleanNumber(uiState.crop?.height)
        },
        fill: {
          color: cleanColor(uiState.fill?.color),
          preset: /^#[0-9a-fA-F]{6}$/.test(cleanPreset) || cleanPreset === "custom" ? cleanPreset : "#07121b",
          mode: cleanMode === "Solid" ? "Solid" : "Auto"
        },
        composite: {
          x: cleanNumber(uiState.composite?.x),
          y: cleanNumber(uiState.composite?.y)
        },
        resize: {
          scalePercent: cleanNumber(uiState.resize?.scalePercent, 95)
        }
      };

      const paths = getWorkspacePaths(bookName);
      const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
      const workRoot = getKdpFixWorkbenchRoot(acceptanceRoot);
      ensureDir(workRoot);
      const statePath = path.join(workRoot, "workbench_state.json");
      const existing = readJsonFileSafe(statePath) || {};
      writeJsonFile(statePath, {
        ...existing,
        updatedAt: nextUiState.updatedAt,
        imgBlackUi: nextUiState
      });
      sendJson(res, 200, {
        bookName,
        imgBlackUi: nextUiState,
        fixWorkbench: getKdpFixWorkbenchState(acceptanceRoot)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/kdp-img-black/fill") {
    try {
      const body = await readJsonBody(req, 1_000_000);
      const bookName = body.bookName;
      const sourceFileName = typeof body.sourceFileName === "string" ? body.sourceFileName : "";
      const fillColor = typeof body.fillColor === "string" ? body.fillColor : "#07121b";
      const fillMode = body.fillMode === "Solid" ? "Solid" : "Auto";
      const x = Math.round(Number(body.x));
      const y = Math.round(Number(body.y));
      const width = Math.round(Number(body.width));
      const height = Math.round(Number(body.height));

      validateBookName(bookName);
      if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(width) || !Number.isFinite(height)) {
        throw new Error("x, y, width, and height are required numbers.");
      }
      if (x < 0 || y < 0 || width <= 0 || height <= 0) {
        throw new Error("x/y must be >= 0 and width/height must be > 0.");
      }
      if (!/^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(fillColor)) {
        throw new Error("fillColor must be a hex color like #07121b.");
      }

      const result = runPowerShellJson("kdp-fill-image-region.ps1", [
        { flag: "-BookName", value: bookName },
        { flag: "-SourceFile", value: sourceFileName || undefined },
        { flag: "-X", value: x },
        { flag: "-Y", value: y },
        { flag: "-Width", value: width },
        { flag: "-Height", value: height },
        { flag: "-FillColor", value: fillColor },
        { flag: "-FillMode", value: fillMode },
        { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
      ]);
      const paths = getWorkspacePaths(bookName);
      const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
      sendJson(res, 200, {
        bookName,
        fill: result,
        fillImageUrl: result?.outputFileName
          ? `/api/kdp-fix-image?bookName=${encodeURIComponent(bookName)}&kind=fill&fileName=${encodeURIComponent(result.outputFileName)}&t=${Date.now()}`
          : "",
        fixWorkbench: getKdpFixWorkbenchState(acceptanceRoot)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/kdp-img-black/composite") {
    try {
      const body = await readJsonBody(req, 1_000_000);
      const bookName = body.bookName;
      const baseFileName = typeof body.baseFileName === "string" ? body.baseFileName : "";
      const overlayFileName = typeof body.overlayFileName === "string" ? body.overlayFileName : "";
      const x = Math.round(Number(body.x));
      const y = Math.round(Number(body.y));

      validateBookName(bookName);
      if (!Number.isFinite(x) || !Number.isFinite(y)) {
        throw new Error("x and y are required numbers.");
      }
      if (x < 0 || y < 0) {
        throw new Error("x/y must be >= 0.");
      }

      const result = runPowerShellJson("kdp-composite-image-region.ps1", [
        { flag: "-BookName", value: bookName },
        { flag: "-BaseFile", value: baseFileName || undefined },
        { flag: "-OverlayFile", value: overlayFileName || undefined },
        { flag: "-X", value: x },
        { flag: "-Y", value: y },
        { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
      ]);
      const paths = getWorkspacePaths(bookName);
      const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
      sendJson(res, 200, {
        bookName,
        composite: result,
        compositeImageUrl: result?.outputFileName
          ? `/api/kdp-fix-image?bookName=${encodeURIComponent(bookName)}&kind=composite&fileName=${encodeURIComponent(result.outputFileName)}&t=${Date.now()}`
          : "",
        fixWorkbench: getKdpFixWorkbenchState(acceptanceRoot)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/kdp-img-black/png-to-pdf") {
    try {
      const body = await readJsonBody(req, 1_000_000);
      const bookName = body.bookName;
      const inputFileName = typeof body.inputFileName === "string" ? body.inputFileName : "";
      validateBookName(bookName);

      const result = runPowerShellJson("kdp-png-to-pdf.ps1", [
        { flag: "-BookName", value: bookName },
        { flag: "-InputFile", value: inputFileName || undefined },
        { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
      ]);
      const paths = getWorkspacePaths(bookName);
      const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
      sendJson(res, 200, {
        bookName,
        pdf: result,
        pdfUrl: result?.outputFileName
          ? `/api/kdp-fix-pdf?bookName=${encodeURIComponent(bookName)}&fileName=${encodeURIComponent(result.outputFileName)}&t=${Date.now()}`
          : "",
        fixWorkbench: getKdpFixWorkbenchState(acceptanceRoot)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/kdp-fix-pdf") {
    const bookName = url.searchParams.get("bookName");
    const fileName = url.searchParams.get("fileName");
    try {
      validateBookName(bookName);
      const safeFileName = sanitizeKdpFixPdfFileName(fileName);
      const paths = getWorkspacePaths(bookName);
      const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
      const targetRoot = path.join(getKdpFixWorkbenchRoot(acceptanceRoot), "pdfs");
      const targetPath = path.resolve(targetRoot, safeFileName);
      const rootResolved = path.resolve(targetRoot);
      if (!targetPath.startsWith(rootResolved + path.sep)) {
        sendJson(res, 403, { error: "Forbidden." });
        return;
      }
      if (!fs.existsSync(targetPath)) {
        sendJson(res, 404, { error: "KDP fix PDF not found." });
        return;
      }
      res.writeHead(200, {
        "Content-Type": "application/pdf",
        "Cache-Control": "no-store",
        "Content-Disposition": `inline; filename="${path.basename(targetPath).replace(/"/g, "")}"`
      });
      res.end(fs.readFileSync(targetPath));
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/kdp-fix-image") {
    const bookName = url.searchParams.get("bookName");
    const kind = url.searchParams.get("kind");
    const fileName = url.searchParams.get("fileName");
    try {
      validateBookName(bookName);
      if (!["source", "output", "crop", "fill", "composite"].includes(kind || "")) {
        throw new Error("kind must be source, output, crop, fill, or composite.");
      }
      const safeFileName = sanitizeKdpFixImageFileName(fileName);
      const paths = getWorkspacePaths(bookName);
      const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
      const kindFolder = kind === "crop" ? "crops" : kind === "fill" ? "fills" : kind === "composite" ? "composites" : kind;
      const targetRoot = path.join(getKdpFixWorkbenchRoot(acceptanceRoot), kindFolder);
      const targetPath = path.resolve(targetRoot, safeFileName);
      const rootResolved = path.resolve(targetRoot);
      if (!targetPath.startsWith(rootResolved + path.sep)) {
        sendJson(res, 403, { error: "Forbidden." });
        return;
      }
      if (!fs.existsSync(targetPath)) {
        sendJson(res, 404, { error: "KDP fix image not found." });
        return;
      }
      res.writeHead(200, {
        "Content-Type": getImageMimeTypeByPath(targetPath),
        "Cache-Control": "no-store"
      });
      res.end(fs.readFileSync(targetPath));
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/cover-copy") {
    const bookName = url.searchParams.get("bookName");

    if (!bookName) {
      sendJson(res, 400, { error: "bookName is required." });
      return;
    }

    try {
      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);

      if (!fs.existsSync(paths.coverCopyJsonPath)) {
        sendJson(res, 404, { error: "cover_copy.json not found." });
        return;
      }

      const copyJson = readJsonFile(paths.coverCopyJsonPath);
      const copyMarkdown = fs.existsSync(paths.coverCopyMdPath)
        ? fs.readFileSync(paths.coverCopyMdPath, "utf8")
        : buildCoverCopyMarkdown(copyJson);

      sendJson(res, 200, {
        bookName,
        copyJson,
        copyMarkdown
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/cover-midjourney-prompt") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      validateBookName(bookName);

      const paths = getWorkspacePaths(bookName);
      const prompt = buildCoverMidjourneyPrompt(paths, {
        title: body.title,
        subtitle: body.subtitle,
        author: body.author
      });

      sendJson(res, 200, { bookName, prompt });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/cover-midjourney-prompt-result") {
    const bookName = url.searchParams.get("bookName");
    const edition = url.searchParams.get("edition") || "ebook";

    if (!bookName) {
      sendJson(res, 400, { error: "bookName is required." });
      return;
    }

    try {
      validateBookName(bookName);
      if (!["ebook", "print"].includes(edition)) {
        throw new Error("Invalid edition.");
      }

      const paths = getWorkspacePaths(bookName);
      const promptRoot = path.join(paths.bookRoot, "07_cover", "next", edition, "prompts");
      const promptPath = path.join(promptRoot, "midjourney_prompt.txt");
      const reportJsonPath = path.join(promptRoot, "midjourney_prompt_report.json");
      const reportMdPath = path.join(promptRoot, "midjourney_prompt_report.md");

      if (!fs.existsSync(promptPath)) {
        sendJson(res, 404, { error: "midjourney_prompt.txt not found." });
        return;
      }

      sendJson(res, 200, {
        bookName,
        edition,
        prompt: fs.readFileSync(promptPath, "utf8").replace(/^\uFEFF/, ""),
        reportText: readTextIfExists(reportMdPath),
        reportJson: readJsonFileSafe(reportJsonPath),
        paths: {
          prompt: promptPath,
          report: reportMdPath,
          reportJson: reportJsonPath
        }
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/cover-workbench-state") {
    const bookName = url.searchParams.get("bookName");
    const edition = url.searchParams.get("edition") || "ebook";

    if (!bookName) {
      sendJson(res, 400, { error: "bookName is required." });
      return;
    }

    try {
      validateBookName(bookName);
      if (!["ebook", "print"].includes(edition)) {
        throw new Error("Invalid edition.");
      }
      const paths = getWorkspacePaths(bookName);
      sendJson(res, 200, {
        bookName,
        workbench: getCoverWorkbenchState(paths.bookRoot, edition)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/cover-workbench-state") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const edition = body.nextEdition || body.edition || "ebook";
      validateBookName(bookName);
      if (!["ebook", "print"].includes(edition)) {
        throw new Error("Invalid edition.");
      }

      const paths = getWorkspacePaths(bookName);
      const nextRoot = path.join(paths.bookRoot, "07_cover", "next", edition);
      const importRoot = path.join(nextRoot, "imports");
      const statePath = path.join(nextRoot, "workbench_state.json");
      const existingState = readJsonFileSafe(statePath) || {};
      const nextState = {
        ...existingState,
        updated_at: formatLocalTimestamp()
      };

      if (typeof body.selectedImportFile === "string" && body.selectedImportFile.trim()) {
        const selectedImportFile = path.basename(body.selectedImportFile.trim());
        validateAssetFileName(selectedImportFile);
        if (!/\.(png|jpg|jpeg|webp)$/i.test(selectedImportFile)) {
          throw new Error("Selected import must be an image file.");
        }
        const selectedPath = path.join(importRoot, selectedImportFile);
        if (!selectedPath.startsWith(importRoot) || !fs.existsSync(selectedPath)) {
          throw new Error("Selected import image not found.");
        }
        nextState.selected_import_file = selectedImportFile;
        nextState.latest_import_file = selectedImportFile;
        nextState.latest_import_path = selectedPath;
      }

      ["editText", "publisher", "imageModel"].forEach((key) => {
        if (typeof body[key] === "string") {
          const stateKey = key === "editText" ? "edit_text" : key === "imageModel" ? "image_model" : key;
          nextState[stateKey] = body[key];
        }
      });

      writeJsonFile(statePath, nextState);
      sendJson(res, 200, {
        bookName,
        workbench: getCoverWorkbenchState(paths.bookRoot, edition)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/cover-midjourney-prompt/save") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const edition = body.nextEdition || body.edition || "ebook";
      const prompt = typeof body.prompt === "string" ? body.prompt : "";
      validateBookName(bookName);
      if (!["ebook", "print"].includes(edition)) {
        throw new Error("Invalid edition.");
      }
      if (!prompt.trim()) {
        throw new Error("Prompt is empty.");
      }

      const paths = getWorkspacePaths(bookName);
      ensureDir(paths.coverBriefRoot);
      const promptPath = path.join(paths.coverBriefRoot, "cover_midjourney_prompt.txt");
      const nextPromptPath = path.join(paths.bookRoot, "07_cover", "next", edition, "prompts", "midjourney_prompt.txt");
      ensureDir(path.dirname(nextPromptPath));
      fs.writeFileSync(promptPath, prompt, "utf8");
      fs.writeFileSync(nextPromptPath, prompt, "utf8");
      const statePath = path.join(paths.bookRoot, "07_cover", "next", edition, "workbench_state.json");
      const existingState = readJsonFileSafe(statePath) || {};
      writeJsonFile(statePath, {
        ...existingState,
        updated_at: formatLocalTimestamp(),
        midjourney_prompt_file: nextPromptPath
      });

      sendJson(res, 200, {
        bookName,
        edition,
        fileName: "cover_midjourney_prompt.txt",
        path: promptPath,
        nextPath: nextPromptPath,
        prompt
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/cover-base-image/import") {
    try {
      const body = await readJsonBody(req, 40_000_000);
      const bookName = body.bookName;
      const edition = body.nextEdition || body.edition || "ebook";
      const dataUrl = typeof body.dataUrl === "string" ? body.dataUrl : "";
      const originalName = typeof body.fileName === "string" ? body.fileName : "";

      validateBookName(bookName);
      if (!["ebook", "print"].includes(edition)) {
        throw new Error("Invalid edition.");
      }

      const match = dataUrl.match(/^data:(image\/png|image\/jpeg|image\/webp);base64,([A-Za-z0-9+/=\r\n]+)$/);
      if (!match) {
        throw new Error("Invalid image data.");
      }

      const mimeType = match[1];
      const fallbackExt = {
        "image/png": ".png",
        "image/jpeg": ".jpg",
        "image/webp": ".webp"
      }[mimeType];
      const safeOriginalName = sanitizeImportedImageFileName(originalName, fallbackExt);
      const stamp = formatFileStamp();
      const buffer = Buffer.from(match[2].replace(/\s/g, ""), "base64");
      if (!buffer.length) {
        throw new Error("Image file is empty.");
      }
      if (buffer.length > 30_000_000) {
        throw new Error("Image file is too large.");
      }

      const paths = getWorkspacePaths(bookName);
      const importRoot = path.join(paths.bookRoot, "07_cover", "next", edition, "imports");
      ensureDir(importRoot);
      let fileName = `imported-base-${stamp}-${safeOriginalName}`;
      let targetPath = path.resolve(importRoot, fileName);
      let suffix = 2;
      while (fs.existsSync(targetPath)) {
        const ext = path.extname(fileName);
        const stem = path.basename(fileName, ext);
        fileName = `${stem}-${suffix}${ext}`;
        targetPath = path.resolve(importRoot, fileName);
        suffix += 1;
      }
      if (!targetPath.startsWith(path.resolve(importRoot) + path.sep)) {
        throw new Error("Invalid image target path.");
      }

      fs.writeFileSync(targetPath, buffer);
      const statePath = path.join(paths.bookRoot, "07_cover", "next", edition, "workbench_state.json");
      const existingState = readJsonFileSafe(statePath) || {};
      writeJsonFile(statePath, {
        ...existingState,
        updated_at: formatLocalTimestamp(),
        latest_import_file: fileName,
        selected_import_file: fileName,
        latest_import_path: targetPath
      });
      sendJson(res, 200, {
        bookName,
        edition,
        fileName,
        mimeType,
        size: buffer.length,
        path: targetPath,
        section: "next-imports"
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/cover-assistant-result") {
    const bookName = url.searchParams.get("bookName");

    if (!bookName) {
      sendJson(res, 400, { error: "bookName is required." });
      return;
    }

    try {
      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);

      if (!fs.existsSync(paths.coverAssistantJsonPath)) {
        sendJson(res, 404, { error: "cover_assistant_last.json not found." });
        return;
      }

      const assistantResult = readJsonFile(paths.coverAssistantJsonPath);
      const responseMarkdown = fs.existsSync(paths.coverAssistantMdPath)
        ? fs.readFileSync(paths.coverAssistantMdPath, "utf8")
        : getStringValue(assistantResult.response);

      sendJson(res, 200, {
        bookName,
        assistantResult,
        responseMarkdown
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/cover-copy") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const selected = body.selected || {};
      const candidates = body.candidates || {};
      const editorNotes = Array.isArray(body.editorNotes) ? body.editorNotes : [];

      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);

      if (!fs.existsSync(paths.coverCopyJsonPath)) {
        sendJson(res, 404, { error: "cover_copy.json not found." });
        return;
      }

      const existing = readJsonFile(paths.coverCopyJsonPath);
      const nextData = {
        ...existing,
        selected: {
          ...(existing.selected || {}),
          subtitle: String(selected.subtitle || ""),
          back_cover_hook: String(selected.back_cover_hook || ""),
          obi_copy: String(selected.obi_copy || ""),
          marketing_tagline: String(selected.marketing_tagline || ""),
          back_cover_blurb: String(selected.back_cover_blurb || ""),
          author_bio: String(selected.author_bio || ""),
          spine_text: String(selected.spine_text || "")
        },
        candidates: {
          ...(existing.candidates || {}),
          subtitle: Array.isArray(candidates.subtitle) ? candidates.subtitle : (existing.candidates?.subtitle || []),
          back_cover_hook: Array.isArray(candidates.back_cover_hook) ? candidates.back_cover_hook : (existing.candidates?.back_cover_hook || []),
          obi_copy: Array.isArray(candidates.obi_copy) ? candidates.obi_copy : (existing.candidates?.obi_copy || []),
          marketing_tagline: Array.isArray(candidates.marketing_tagline) ? candidates.marketing_tagline : (existing.candidates?.marketing_tagline || [])
        },
        editor_notes: editorNotes.map((item) => String(item || "")).filter(Boolean)
      };

      fs.writeFileSync(paths.coverCopyJsonPath, `${JSON.stringify(nextData, null, 2)}\n`, "utf8");
      fs.writeFileSync(paths.coverCopyMdPath, buildCoverCopyMarkdown(nextData), "utf8");

      sendJson(res, 200, {
        bookName,
        saved: true,
        copyJson: nextData,
        copyMarkdown: buildCoverCopyMarkdown(nextData)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/frontmatter") {
    const bookName = url.searchParams.get("bookName");

    if (!bookName) {
      sendJson(res, 400, { error: "bookName is required." });
      return;
    }

    try {
      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);
      sendJson(res, 200, {
        bookName,
        frontmatter: getFrontmatterPayload(paths)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/frontmatter") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const coverPage = typeof body.coverPage === "string" ? body.coverPage : null;
      const titlePage = typeof body.titlePage === "string" ? body.titlePage : null;
      const copyrightPage = typeof body.copyrightPage === "string" ? body.copyrightPage : null;

      if (!bookName) {
        sendJson(res, 400, { error: "bookName is required." });
        return;
      }

      if (coverPage === null || titlePage === null || copyrightPage === null) {
        sendJson(res, 400, { error: "coverPage, titlePage, and copyrightPage are required." });
        return;
      }

      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);

      ensureDir(paths.frontmatterBaseRoot);
      ensureDir(paths.frontmatterRoot);

      fs.writeFileSync(paths.coverPagePath, coverPage, "utf8");
      fs.writeFileSync(paths.titlePagePath, titlePage, "utf8");
      fs.writeFileSync(paths.copyrightPagePath, copyrightPage, "utf8");

      let manifest = null;
      if (fs.existsSync(paths.frontmatterManifestPath)) {
        try {
          manifest = readJsonFile(paths.frontmatterManifestPath);
        } catch {
          manifest = null;
        }
      }

      const nextManifest = {
        ...(manifest || {}),
        generated_at: formatLocalTimestamp(),
        book_name: bookName,
        edition: "ebook",
        files: [
          { role: "cover_page", file: "cover_page.md", path: paths.coverPagePath },
          { role: "title_page", file: "title_page.md", path: paths.titlePagePath },
          { role: "copyright_page", file: "copyright_page.md", path: paths.copyrightPagePath }
        ]
      };

      fs.writeFileSync(paths.frontmatterManifestPath, `${JSON.stringify(nextManifest, null, 2)}\n`, "utf8");

      sendJson(res, 200, {
        bookName,
        saved: true,
        frontmatter: {
          manifest: nextManifest,
          coverPage,
          titlePage,
          copyrightPage
        }
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/cover-image") {
    const bookName = url.searchParams.get("bookName");
    const section = url.searchParams.get("section");
    const fileName = url.searchParams.get("fileName");

    if (!bookName || !section || !fileName) {
      sendJson(res, 400, { error: "bookName, section, and fileName are required." });
      return;
    }

    try {
      validateBookName(bookName);
      validateAssetFileName(fileName);
      const paths = getWorkspacePaths(bookName);
      const sectionRoot = resolveCoverSectionRoot(paths, section);
      const safeFileName = path.basename(fileName);
      const targetPath = path.join(sectionRoot, safeFileName);

      if (!targetPath.startsWith(sectionRoot)) {
        sendJson(res, 403, { error: "Forbidden." });
        return;
      }
      if (!fs.existsSync(targetPath)) {
        sendJson(res, 404, { error: "Cover asset not found." });
        return;
      }

      const ext = path.extname(targetPath).toLowerCase();
      const mime = {
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".webp": "image/webp",
        ".pdf": "application/pdf"
      }[ext] || "application/octet-stream";

      res.writeHead(200, {
        "Content-Type": mime,
        "Cache-Control": "no-store"
      });
      res.end(fs.readFileSync(targetPath));
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/open-cover-folder") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const section = body.section;

      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);
      const sectionRoot = resolveCoverSectionRoot(paths, section);
      if (!fs.existsSync(sectionRoot)) {
        sendJson(res, 404, { error: "Cover folder not found." });
        return;
      }

      openFolder(sectionRoot);
      sendJson(res, 200, { opened: true, bookName, section });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/reveal-cover-file") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const section = body.section;
      const fileName = body.fileName;

      validateBookName(bookName);
      validateAssetFileName(fileName);
      const paths = getWorkspacePaths(bookName);
      const sectionRoot = resolveCoverSectionRoot(paths, section);
      const targetPath = path.join(sectionRoot, path.basename(fileName));

      if (!targetPath.startsWith(sectionRoot)) {
        sendJson(res, 403, { error: "Forbidden." });
        return;
      }
      if (!fs.existsSync(targetPath)) {
        sendJson(res, 404, { error: "Cover file not found." });
        return;
      }

      revealFileInExplorer(targetPath);
      sendJson(res, 200, { opened: true, bookName, section, fileName });
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
