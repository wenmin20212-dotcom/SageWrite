const state = {
  currentJobId: null,
  pollTimer: null,
  workspaces: [],
  selectedRunKey: "",
  runOutputCache: {},
  runOutputLoadingKey: "",
  preflightCache: {},
  preflightLoadingBook: "",
  coverCache: {},
  coverLoadingBook: "",
  coverWorkbenchCache: {},
  coverWorkbenchLoadingBook: "",
  coverCopyCache: {},
  coverCopyLoadingBook: "",
  frontmatterCache: {},
  frontmatterLoadingBook: "",
  publishCache: {},
  publishLoadingKey: "",
  publishEditorKey: "",
  publishEditorDirty: false,
  publishAutoSaveTimer: null,
  publishFeedbackTimer: null,
  publishPreviewRefreshTimer: null,
  publishSaveInFlight: false,
  publishLastSavedAt: "",
  publishSelectedCategories: {},
  users: [],
  userBillingEvents: {},
  userFilterNegative: false,
  userAdminError: "",
  auditEvents: [],
  auditError: "",
  auditLoading: false,
  auditPath: "",
  billingConfig: null,
  account: null,
  accountEvents: [],
  accountError: "",
  chapterListCache: {},
  chapterContentCache: {},
  chapterListLoadingBook: "",
  chapterContentLoadingKey: "",
  coverBaseImport: null,
  kdpAcceptanceFile: null,
  kdpPdf: {
    pdfjs: null,
    tesseract: null,
    document: null,
    page: null,
    mode: "pdf",
    image: null,
    imageSize: null,
    source: null,
    url: "",
    scale: 1,
    spec: null,
    ocrCanvasWidth: 0,
    ocrCanvasHeight: 0,
    textRegions: [],
    visionDebug: null,
    renderTask: null,
    loading: false
  },
  kdpFixWorkbench: {},
  activeFlowTarget: "project",
  suppressFlowSync: false,
  appMode: "local",
  authMode: "off",
  currentUser: null,
  currentJobBookName: "",
  health: null
};

const PDFJS_MODULE_URL = "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/4.10.38/pdf.min.mjs";
const PDFJS_WORKER_URL = "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/4.10.38/pdf.worker.min.mjs";
const TESSERACT_SCRIPT_URL = "https://cdn.jsdelivr.net/npm/tesseract.js@5/dist/tesseract.min.js";

const COVER_PANEL_STORAGE_KEY = "sagewrite-cover-panel-expanded";
const BUILD_WORKBENCH_STORAGE_KEY = "sagewrite-build-workbench-open";
const INTAKE_WORKBENCH_STORAGE_KEY = "sagewrite-intake-workbench-open";
const STRUCTURE_WORKBENCH_STORAGE_KEY = "sagewrite-structure-workbench-open";
const EXPAND_WORKBENCH_STORAGE_KEY = "sagewrite-expand-workbench-open";
const WRITE_WORKBENCH_STORAGE_KEY = "sagewrite-write-workbench-open";
const TRANSLATE_WORKBENCH_STORAGE_KEY = "sagewrite-translate-workbench-open";
const REFINE_WORKBENCH_STORAGE_KEY = "sagewrite-refine-workbench-open";
const CHECK_WORKBENCH_STORAGE_KEY = "sagewrite-check-workbench-open";
const CHECK_PANEL_STORAGE_KEY = "sagewrite-check-panel-expanded";
const COVER_METADATA_WORKBENCH_STORAGE_KEY = "sagewrite-cover-metadata-workbench-open";
const COVER_VISUAL_WORKBENCH_STORAGE_KEY = "sagewrite-cover-visual-workbench-open";
const COVER_OPERATIONS_WORKBENCH_STORAGE_KEY = "sagewrite-cover-operations-workbench-open";
const COVER_RESULTS_WORKBENCH_STORAGE_KEY = "sagewrite-cover-results-workbench-open";
const COVER_KDP_REVIEW_WORKBENCH_STORAGE_KEY = "sagewrite-cover-kdp-review-workbench-open";
const COVER_KDP_FIX_WORKBENCH_STORAGE_KEY = "sagewrite-cover-kdp-fix-workbench-open";
const COVER_KDP_IMG_BLACK_WORKBENCH_STORAGE_KEY = "sagewrite-cover-kdp-img-black-workbench-open";
const PROJECT_PICKER_WORKBENCH_STORAGE_KEY = "sagewrite-project-picker-workbench-open";
const PROJECT_STATUS_WORKBENCH_STORAGE_KEY = "sagewrite-project-status-workbench-open";
const USER_ADMIN_WORKBENCH_STORAGE_KEY = "sagewrite-user-admin-workbench-open";
const ACCOUNT_WORKBENCH_STORAGE_KEY = "sagewrite-account-workbench-open";
const SELECTED_BOOKNAME_STORAGE_KEY = "sagewrite-selected-bookname";
const CURRENT_JOB_STORAGE_KEY = "sagewrite-current-job";
const DEFAULT_MODEL_STORAGE_KEY = "sagewrite-default-model-name";
const PUBLISH_PANEL_STORAGE_KEY = "sagewrite-publish-panel-expanded";
const PUBLISH_PREVIEW_COLUMN_STORAGE_KEY = "sagewrite-publish-preview-column-expanded";
const PUBLISH_PREVIEW_PLATFORM_STORAGE_KEY = "sagewrite-publish-preview-platform";
const PUBLISH_PLATFORM_GROUP_STORAGE_KEY = "sagewrite-publish-platform-groups";
const PUBLISH_RECOMMENDED_CARD_STORAGE_KEY = "sagewrite-publish-recommended-cards";
const PUBLISH_RAW_TOGGLE_STORAGE_KEY = "sagewrite-publish-raw-toggle-open";
const FLOW_ACTIVE_STORAGE_KEY = "sagewrite-active-flow-target";
const FLOW_WORKBENCHES = [
  { id: "project", selector: "#project-picker-workbench-shell", section: '[data-flow-section="project"]' },
  { id: "account", selector: "#account-workbench-shell", section: '[data-flow-section="account"]' },
  { id: "users", selector: "#user-admin-workbench-shell", section: '[data-flow-section="users"]' },
  { id: "intake", selector: "#intake-workbench-shell", section: '[data-flow-section="intake"]' },
  { id: "structure", selector: "#structure-workbench-shell", section: '[data-flow-section="structure"]' },
  { id: "expand", selector: "#expand-workbench-shell", section: '[data-flow-section="expand"]' },
  { id: "write", selector: "#write-workbench-shell", section: '[data-flow-section="write"]' },
  { id: "translate", selector: "#translate-workbench-shell", section: '[data-flow-section="translate"]' },
  { id: "refine", selector: "#refine-workbench-shell", section: '[data-flow-section="refine"]' },
  { id: "check", selector: null, section: '[data-flow-section="check"]', panel: "check" },
  { id: "build", selector: "#build-workbench-shell", section: '[data-flow-section="build"]' },
  { id: "cover", selector: "#cover-metadata-shell", section: '[data-flow-section="cover"]', panel: "cover" },
  { id: "publish", selector: null, section: '[data-flow-section="publish"]', panel: "publish" }
];
const FLOW_AUTO_OPEN_SUPPRESSED = new Set(["cover"]);
const LANGUAGE_LABELS = {
  zh: "中文",
  "zh-tw": "繁體中文（台灣）",
  "zh-hant": "繁體中文",
  en: "English",
  ms: "Bahasa Melayu",
  fr: "Français",
  de: "Deutsch",
  es: "Español",
  it: "Italiano",
  pt: "Português",
  ja: "日本語",
  ko: "한국어"
};

function $(selector) {
  return document.querySelector(selector);
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function formToObject(form) {
  const data = new FormData(form);
  const obj = {};
  for (const [key, value] of data.entries()) {
    obj[key] = value;
  }
  Array.from(form.elements || []).forEach((input) => {
    if (!(input instanceof HTMLInputElement) || input.type !== "checkbox") {
      return;
    }
    obj[input.name] = input.checked;
  });
  return obj;
}

function setStatusBadge(text, kind = "idle") {
  const badge = $("#job-badge");
  badge.textContent = text;
  badge.dataset.kind = kind;
}

function updateCancelJobButton(isRunning = false) {
  const button = $("#cancel-current-job");
  if (!button) {
    return;
  }
  button.disabled = !isRunning || !state.currentJobId;
}

function setLog(text) {
  $("#log-output").textContent = text || "这里会显示 PowerShell 输出。";
}

function appendLog(text) {
  const output = $("#log-output");
  if (!output) {
    return;
  }
  const current = output.textContent || "";
  const placeholder = "这里会显示 PowerShell 输出。";
  output.textContent = current && current !== placeholder ? `${current}\n${text}` : text;
  output.scrollTop = output.scrollHeight;
}

function getBookName() {
  return $("#bookName").value.trim();
}

function setRememberedBookName(bookName) {
  const value = String(bookName || "").trim();
  if (!value) {
    localStorage.removeItem(SELECTED_BOOKNAME_STORAGE_KEY);
    return;
  }
  localStorage.setItem(SELECTED_BOOKNAME_STORAGE_KEY, value);
}

function getRememberedBookName() {
  return String(localStorage.getItem(SELECTED_BOOKNAME_STORAGE_KEY) || "").trim();
}

function rememberCurrentJob(jobId, bookName = "") {
  const value = {
    jobId: String(jobId || "").trim(),
    bookName: String(bookName || "").trim(),
    savedAt: new Date().toISOString()
  };
  if (!value.jobId) {
    localStorage.removeItem(CURRENT_JOB_STORAGE_KEY);
    return;
  }
  localStorage.setItem(CURRENT_JOB_STORAGE_KEY, JSON.stringify(value));
}

function getRememberedCurrentJob() {
  try {
    const value = JSON.parse(localStorage.getItem(CURRENT_JOB_STORAGE_KEY) || "null");
    return {
      jobId: String(value?.jobId || "").trim(),
      bookName: String(value?.bookName || "").trim()
    };
  } catch {
    return { jobId: "", bookName: "" };
  }
}

function clearRememberedCurrentJob(jobId = "") {
  const remembered = getRememberedCurrentJob();
  if (!jobId || !remembered.jobId || remembered.jobId === jobId) {
    localStorage.removeItem(CURRENT_JOB_STORAGE_KEY);
  }
}

function getStoredDefaultModelName() {
  return String(localStorage.getItem(DEFAULT_MODEL_STORAGE_KEY) || "gpt-5.2").trim() || "gpt-5.2";
}

function getDefaultModelName() {
  const heroFieldValue = String($("#default-model-name")?.value || "").trim();
  return heroFieldValue || getStoredDefaultModelName();
}

function setDefaultModelName(value) {
  const normalized = String(value || "").trim() || "gpt-5.2";
  localStorage.setItem(DEFAULT_MODEL_STORAGE_KEY, normalized);

  const heroField = $("#default-model-name");
  if (heroField && heroField.value !== normalized) {
    heroField.value = normalized;
  }

  const refineField = $('#refine-form [name="model"]');
  if (refineField) {
    refineField.value = normalized;
  }

  const translateField = $('#translate-form [name="model"]');
  if (translateField) {
    translateField.value = normalized;
  }

  const writeField = $('#write-form [name="model"]');
  if (writeField) {
    writeField.value = normalized;
  }
}

function setCoverPanelExpanded(expanded) {
  const panel = document.querySelector(".cover-panel");
  const toggle = $("#toggle-cover-panel");
  if (!panel || !toggle) {
    return;
  }

  panel.classList.toggle("collapsed", !expanded);
  toggle.textContent = expanded ? "收起" : "展开";
  toggle.setAttribute("aria-expanded", expanded ? "true" : "false");
  localStorage.setItem(COVER_PANEL_STORAGE_KEY, expanded ? "1" : "0");
}

function setCheckPanelExpanded(expanded) {
  const panel = document.querySelector(".check-panel");
  const toggle = $("#toggle-check-panel");
  if (!panel || !toggle) {
    return;
  }

  panel.classList.toggle("collapsed", !expanded);
  toggle.textContent = expanded ? "收起" : "展开";
  toggle.setAttribute("aria-expanded", expanded ? "true" : "false");
  localStorage.setItem(CHECK_PANEL_STORAGE_KEY, expanded ? "1" : "0");
}

function initCheckPanelState() {
  const stored = localStorage.getItem(CHECK_PANEL_STORAGE_KEY);
  setCheckPanelExpanded(stored === "1");
}

function initCoverPanelState() {
  const stored = localStorage.getItem(COVER_PANEL_STORAGE_KEY);
  setCoverPanelExpanded(stored === "1");
}

function setBuildWorkbenchOpen(isOpen) {
  const panel = $("#build-workbench-shell");
  if (!panel) {
    return;
  }
  panel.open = Boolean(isOpen);
  localStorage.setItem(BUILD_WORKBENCH_STORAGE_KEY, isOpen ? "1" : "0");
}

function initBuildWorkbenchState() {
  const panel = $("#build-workbench-shell");
  if (!panel) {
    return;
  }
  const stored = localStorage.getItem(BUILD_WORKBENCH_STORAGE_KEY);
  panel.open = stored === "1";
}

function setWorkbenchOpen(selector, storageKey, isOpen) {
  const panel = $(selector);
  if (!panel) {
    return;
  }
  panel.open = Boolean(isOpen);
  localStorage.setItem(storageKey, isOpen ? "1" : "0");
}

function initWorkbenchState(selector, storageKey, defaultOpen = false) {
  const panel = $(selector);
  if (!panel) {
    return;
  }
  const stored = localStorage.getItem(storageKey);
  panel.open = stored === null ? Boolean(defaultOpen) : stored === "1";
}

function mountKdpFixModule() {
  const mount = $("#kdp-fix-module-mount");
  const panel = $(".kdp-fix-report-panel");
  if (!mount || !panel || panel.parentElement === mount) {
    return;
  }
  mount.appendChild(panel);
}

function getFlowWorkbench(targetId = "project") {
  return FLOW_WORKBENCHES.find((item) => item.id === targetId) || FLOW_WORKBENCHES[0];
}

function setFlowNavActive(targetId) {
  document.querySelectorAll("[data-flow-target]").forEach((button) => {
    const isActive = button.dataset.flowTarget === targetId;
    button.classList.toggle("active", isActive);
    if (isActive) {
      button.setAttribute("aria-current", "step");
    } else {
      button.removeAttribute("aria-current");
    }
  });
}

function setFlowDetailsOpen(workbench, isOpen) {
  if (!workbench.selector) {
    return;
  }
  const panel = $(workbench.selector);
  if (!panel) {
    return;
  }
  panel.open = Boolean(isOpen);
}

function activateFlowWorkbench(targetId = "project", options = {}) {
  const target = getFlowWorkbench(targetId);
  state.activeFlowTarget = target.id;
  localStorage.setItem(FLOW_ACTIVE_STORAGE_KEY, target.id);
  setFlowNavActive(target.id);

  state.suppressFlowSync = true;
  document.querySelectorAll(".workbench-shell, .build-workbench-shell").forEach((panel) => {
    panel.open = false;
  });
  if (!FLOW_AUTO_OPEN_SUPPRESSED.has(target.id)) {
    setFlowDetailsOpen(target, true);
  }

  setCheckPanelExpanded(target.panel === "check");
  setCoverPanelExpanded(target.panel === "cover");
  setPublishPanelExpanded(target.panel === "publish");

  if (target.id !== "publish") {
    document.querySelectorAll("[data-publish-platform-group]").forEach((panel) => {
      panel.open = false;
    });
  } else {
    document.querySelectorAll("[data-publish-platform-group]").forEach((panel, index) => {
      panel.open = index === 0;
    });
  }

  state.suppressFlowSync = false;

  if (options.scroll) {
    const section = document.querySelector(target.section);
    section?.scrollIntoView({ behavior: "smooth", block: "start" });
  }
}

function initFlowNavigation() {
  document.querySelectorAll("[data-flow-target]").forEach((button) => {
    button.addEventListener("click", () => {
      activateFlowWorkbench(button.dataset.flowTarget || "project", { scroll: true });
    });
  });

  const flowNav = document.querySelector(".flow-nav");
  flowNav?.addEventListener("wheel", (event) => {
    if (Math.abs(event.deltaY) <= Math.abs(event.deltaX)) {
      return;
    }
    const maxScroll = flowNav.scrollHeight - flowNav.clientHeight;
    if (maxScroll <= 1) {
      return;
    }
    const currentScroll = flowNav.scrollTop;
    const nextScroll = Math.max(0, Math.min(maxScroll, currentScroll + event.deltaY));
    if (nextScroll === currentScroll) {
      return;
    }
    flowNav.scrollTop = nextScroll;
    event.preventDefault();
    event.stopPropagation();
  }, { passive: false });

  FLOW_WORKBENCHES.forEach((workbench) => {
    if (!workbench.selector) {
      return;
    }
    const panel = $(workbench.selector);
    panel?.addEventListener("toggle", () => {
      if (state.suppressFlowSync || !panel.open) {
        return;
      }
      activateFlowWorkbench(workbench.id);
    });
  });

  const stored = localStorage.getItem(FLOW_ACTIVE_STORAGE_KEY);
  activateFlowWorkbench(stored || "project");
}

function setPublishPanelExpanded(expanded) {
  const panel = document.querySelector(".publish-panel");
  const toggle = $("#toggle-publish-panel");
  if (!panel || !toggle) {
    return;
  }

  panel.classList.toggle("collapsed", !expanded);
  toggle.textContent = expanded ? "收起" : "展开";
  toggle.setAttribute("aria-expanded", expanded ? "true" : "false");
  localStorage.setItem(PUBLISH_PANEL_STORAGE_KEY, expanded ? "1" : "0");
}

function initPublishPanelState() {
  const stored = localStorage.getItem(PUBLISH_PANEL_STORAGE_KEY);
  setPublishPanelExpanded(stored !== "0");
}

function setPublishPreviewColumnExpanded(expanded) {
  const workbench = document.querySelector(".publish-workbench");
  const toggle = $("#toggle-publish-preview-column");
  if (!workbench || !toggle) {
    return;
  }

  workbench.classList.toggle("preview-collapsed", !expanded);
  toggle.textContent = expanded ? "收起右侧预览" : "显示右侧预览";
  toggle.setAttribute("aria-expanded", expanded ? "true" : "false");
  localStorage.setItem(PUBLISH_PREVIEW_COLUMN_STORAGE_KEY, expanded ? "1" : "0");
}

function initPublishPreviewColumnState() {
  const stored = localStorage.getItem(PUBLISH_PREVIEW_COLUMN_STORAGE_KEY);
  setPublishPreviewColumnExpanded(stored !== "0");
}

function getWriteMode() {
  const field = $('#write-form [name="mode"]');
  return field ? field.value : "all";
}

function getPublishLanguage() {
  const field = $('#publish-form [name="language"]');
  return field ? field.value : "zh";
}

function getPublishTargetPlatform() {
  const field = $('#publish-form [name="platform"]');
  return field ? field.value : "all";
}

function getPublishPreviewPlatform() {
  const field = $("#publish-preview-platform");
  if (field && field.value) {
    return field.value;
  }
  return localStorage.getItem(PUBLISH_PREVIEW_PLATFORM_STORAGE_KEY) || "amazon";
}

function focusPublishPreviewPlatform(platformName, rerender = true) {
  const normalized = String(platformName || "").trim().toLowerCase();
  const field = $("#publish-preview-platform");
  if (!field || !normalized) {
    return;
  }

  const hasOption = Array.from(field.options).some((option) => option.value === normalized);
  if (!hasOption) {
    return;
  }

  if (field.value !== normalized) {
    field.value = normalized;
    localStorage.setItem(PUBLISH_PREVIEW_PLATFORM_STORAGE_KEY, normalized);
    if (rerender) {
      const selected = getSelectedWorkspaceItem();
      if (selected) {
        renderPublishPanel(selected);
      }
    }
    return;
  }

  localStorage.setItem(PUBLISH_PREVIEW_PLATFORM_STORAGE_KEY, normalized);
}

function getPublishPlatformGroupState() {
  try {
    const raw = localStorage.getItem(PUBLISH_PLATFORM_GROUP_STORAGE_KEY);
    const parsed = raw ? JSON.parse(raw) : {};
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch {
    return {};
  }
}

function setPublishPlatformGroupState(platformName, isOpen) {
  const normalized = String(platformName || "").trim().toLowerCase();
  if (!normalized) {
    return;
  }
  const current = getPublishPlatformGroupState();
  current[normalized] = Boolean(isOpen);
  localStorage.setItem(PUBLISH_PLATFORM_GROUP_STORAGE_KEY, JSON.stringify(current));
}

function isPublishPlatformGroupOpen(platformName) {
  const normalized = String(platformName || "").trim().toLowerCase();
  const current = getPublishPlatformGroupState();
  if (!normalized) {
    return true;
  }
  if (!(normalized in current)) {
    return true;
  }
  return Boolean(current[normalized]);
}

function syncPublishPlatformGroups() {
  document.querySelectorAll("[data-publish-platform-group]").forEach((panel) => {
    const platformName = panel.dataset.publishPlatformGroup || "";
    panel.open = isPublishPlatformGroupOpen(platformName);
  });
}

function joinWindowsPath(...parts) {
  return parts
    .filter(Boolean)
    .map((part, index) => {
      const value = String(part || "");
      if (index === 0) {
        return value.replace(/[\\/]+$/g, "");
      }
      return value.replace(/^[\\/]+|[\\/]+$/g, "");
    })
    .filter(Boolean)
    .join("\\");
}

function getPublishRootAbsolutePath(item, language = getPublishLanguage()) {
  if (!item?.workspacePath) {
    return "";
  }
  return joinWindowsPath(item.workspacePath, "sagewrite", "book", "09_publish", language);
}

function getPublishPlatformAbsolutePath(item, language = getPublishLanguage(), platform = getPublishPreviewPlatform()) {
  const rootPath = getPublishRootAbsolutePath(item, language);
  return platform ? joinWindowsPath(rootPath, platform) : rootPath;
}

async function copyTextToClipboard(text) {
  const value = String(text || "").trim();
  if (!value) {
    throw new Error("当前没有可复制的路径。");
  }

  if (navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(value);
    return;
  }

  const probe = document.createElement("textarea");
  probe.value = value;
  probe.setAttribute("readonly", "true");
  probe.style.position = "fixed";
  probe.style.opacity = "0";
  document.body.appendChild(probe);
  probe.select();
  document.execCommand("copy");
  document.body.removeChild(probe);
}

function getLanguageLabel(languageCode) {
  return LANGUAGE_LABELS[String(languageCode || "").trim().toLowerCase()] || String(languageCode || "").trim().toLowerCase();
}

function getWorkspacePublishLanguages(item, publish = null) {
  const languages = [];
  const addLanguage = (value) => {
    const normalized = String(value || "").trim().toLowerCase();
    if (!normalized || languages.includes(normalized)) {
      return;
    }
    languages.push(normalized);
  };

  (publish?.sourceLanguages || []).forEach(addLanguage);
  (publish?.availableLanguages || []).forEach(addLanguage);
  (item?.outputLanguages || []).forEach(addLanguage);
  (item?.publishLanguages || []).forEach(addLanguage);

  if (!languages.length) {
    addLanguage("zh");
  }

  return languages;
}

function syncPublishLanguageOptions(item, publish = null, preferredLanguage = "") {
  const select = $("#publish-language");
  if (!select) {
    return;
  }

  const options = getWorkspacePublishLanguages(item, publish);
  const currentValue = String(preferredLanguage || select.value || "").trim().toLowerCase();
  const nextValue = options.includes(currentValue) ? currentValue : options[0];
  const snapshot = options.join("|");

  if (select.dataset.optionsSnapshot !== snapshot) {
    select.innerHTML = options.map((language) => (
      `<option value="${escapeHtml(language)}">${escapeHtml(getLanguageLabel(language))}（${escapeHtml(language)}）</option>`
    )).join("");
    select.dataset.optionsSnapshot = snapshot;
  }

  select.value = nextValue;

  const hint = $("#publish-language-hint");
  if (hint) {
    hint.textContent = `当前项目检测到语言版本：${options.map((language) => `${getLanguageLabel(language)}（${language}）`).join("、")}。09 会为每个语种分别生成独立上架包。`;
  }
}

function updatePublishEditorStatus() {
  const status = $("#publish-editor-status");
  if (!status) {
    return;
  }
  if (state.publishSaveInFlight) {
    status.textContent = "正在自动保存人工微调...";
    return;
  }

  if (state.publishEditorDirty) {
    status.textContent = "当前是自动生成稿，修改将在短暂静止后自动保存";
    return;
  }

  if (state.publishLastSavedAt) {
    status.textContent = `09 元数据已自动同步（${state.publishLastSavedAt}）`;
    return;
  }

  status.textContent = "09 元数据已自动生成并同步";
}

function getPublishCacheKey(bookName = requireBookName(), language = getPublishLanguage()) {
  return `${bookName}:${language}`;
}

function setPublishSelectedCategories(cacheKey, metadata = {}) {
  state.publishSelectedCategories[cacheKey] = {
    amazon: metadata.platform_selected_categories?.amazon || metadata.discovery?.platform_selected_categories?.amazon || "",
    apple: metadata.platform_selected_categories?.apple || metadata.discovery?.platform_selected_categories?.apple || "",
    google: metadata.platform_selected_categories?.google || metadata.discovery?.platform_selected_categories?.google || "",
    kobo: metadata.platform_selected_categories?.kobo || metadata.discovery?.platform_selected_categories?.kobo || ""
  };
}

function getPublishSelectedCategories(cacheKey) {
  return state.publishSelectedCategories[cacheKey] || { amazon: "", apple: "", google: "", kobo: "" };
}

function getPublishPlatformLabel(platformName) {
  return platformName === "amazon"
    ? "Amazon"
    : platformName === "apple"
      ? "Apple"
      : platformName === "google"
        ? "Google"
        : "Kobo";
}

function updateAmazonDescriptionStatus(text) {
  const status = $("#amazon-description-status");
  if (!status) {
    return;
  }
  status.textContent = text || "尚未单独保存 Amazon Description";
}

function clearPublishAutoSaveTimer() {
  if (!state.publishAutoSaveTimer) {
    return;
  }
  clearTimeout(state.publishAutoSaveTimer);
  state.publishAutoSaveTimer = null;
}

function clearPublishFeedbackTimer() {
  if (!state.publishFeedbackTimer) {
    return;
  }
  clearTimeout(state.publishFeedbackTimer);
  state.publishFeedbackTimer = null;
}

function clearPublishPreviewRefreshTimer() {
  if (!state.publishPreviewRefreshTimer) {
    return;
  }
  clearTimeout(state.publishPreviewRefreshTimer);
  state.publishPreviewRefreshTimer = null;
}

function showPublishSaveFeedback(kind, message, persist = false) {
  const panel = $("#publish-save-feedback");
  if (!panel) {
    return;
  }

  clearPublishFeedbackTimer();
  panel.textContent = message || "";
  panel.dataset.kind = kind || "success";
  panel.classList.remove("hidden");

  if (!persist) {
    state.publishFeedbackTimer = setTimeout(() => {
      panel.classList.add("hidden");
      panel.textContent = "";
      panel.dataset.kind = "";
      state.publishFeedbackTimer = null;
    }, kind === "error" ? 5200 : 2600);
  }
}

function hidePublishSaveFeedback() {
  const panel = $("#publish-save-feedback");
  if (!panel) {
    return;
  }
  clearPublishFeedbackTimer();
  panel.classList.add("hidden");
  panel.textContent = "";
  panel.dataset.kind = "";
}

function flashPublishPreview(message = "右侧预览已刷新") {
  const stack = document.querySelector(".publish-preview-stack");
  if (!stack) {
    return;
  }

  stack.classList.remove("publish-preview-flash");
  void stack.offsetWidth;
  stack.classList.add("publish-preview-flash");
  stack.dataset.previewNotice = message;

  clearPublishPreviewRefreshTimer();
  state.publishPreviewRefreshTimer = setTimeout(() => {
    stack.classList.remove("publish-preview-flash");
    stack.dataset.previewNotice = "";
    state.publishPreviewRefreshTimer = null;
  }, 1800);
}

function formatTimeLabel(date = new Date()) {
  return date.toLocaleTimeString("zh-CN", {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false
  });
}

function formatKdpReportTimestamp(date = new Date()) {
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

function initPublishUiState() {
  const platformField = $("#publish-preview-platform");
  if (platformField) {
    const storedPlatform = localStorage.getItem(PUBLISH_PREVIEW_PLATFORM_STORAGE_KEY);
    if (storedPlatform && Array.from(platformField.options).some((option) => option.value === storedPlatform)) {
      platformField.value = storedPlatform;
    }
  }

  const rawToggle = document.querySelector(".publish-raw-toggle");
  if (rawToggle) {
    rawToggle.open = isPublishRawToggleOpen();
  }

  syncPublishPlatformGroups();
  if (isPublishPlatformGroupOpen("amazon")) {
    focusPublishPreviewPlatform("amazon", false);
  }

  updatePublishSubmitControls();
}

function updatePublishSubmitControls() {
  const platform = getPublishTargetPlatform();
  const attachCheckbox = $("#publish-attach-chrome");
  const portInput = $("#publish-chrome-debug-port");
  const hint = $("#publish-submit-hint");
  const advancedWrap = document.querySelector(".publish-submit-advanced");
  const isGoogle = platform === "google";
  const attachEnabled = Boolean(attachCheckbox?.checked) && isGoogle;

  if (advancedWrap) {
    advancedWrap.classList.toggle("is-disabled", !isGoogle);
  }

  if (attachCheckbox) {
    attachCheckbox.disabled = !isGoogle;
  }

  if (portInput) {
    portInput.disabled = !attachEnabled;
  }

  if (hint) {
    hint.textContent = isGoogle
      ? (attachEnabled
        ? "当前会把 submit 连接到你手动启动并开启远程调试端口的 Chrome。"
        : "仅对 Google 平台 submit 生效。勾选后会连接手动打开的 Chrome，而不是新开自动化浏览器。")
      : "这组设置只在“生成范围”选择 Google Play Books 且点击“提交到当前平台”时生效。";
  }
}

function getPublishRecommendedCardState() {
  try {
    const raw = localStorage.getItem(PUBLISH_RECOMMENDED_CARD_STORAGE_KEY);
    const parsed = raw ? JSON.parse(raw) : {};
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch {
    return {};
  }
}

function setPublishRecommendedCardState(platformName, isOpen) {
  const current = getPublishRecommendedCardState();
  current[String(platformName || "").trim().toLowerCase()] = Boolean(isOpen);
  localStorage.setItem(PUBLISH_RECOMMENDED_CARD_STORAGE_KEY, JSON.stringify(current));
}

function isPublishRecommendedCardOpen(platformName) {
  const current = getPublishRecommendedCardState();
  const key = String(platformName || "").trim().toLowerCase();
  if (Object.prototype.hasOwnProperty.call(current, key)) {
    return Boolean(current[key]);
  }
  return false;
}

function setPublishRawToggleOpen(isOpen) {
  localStorage.setItem(PUBLISH_RAW_TOGGLE_STORAGE_KEY, isOpen ? "1" : "0");
}

function isPublishRawToggleOpen() {
  return localStorage.getItem(PUBLISH_RAW_TOGGLE_STORAGE_KEY) === "1";
}

function requireBookName() {
  const bookName = getBookName();
  if (!bookName) {
    throw new Error("请先填写或选择 BookName。");
  }
  return bookName;
}

function setWriteNotesStatus() {
  const hiddenField = $("#additional-instructions");
  const status = $("#write-notes-status");
  if (!hiddenField || !status) {
    return;
  }

  const text = (hiddenField.value || "").trim();
  status.textContent = text
    ? `已添加附加说明（${text.length} 字）`
    : "未添加附加说明";
}

function openWriteNotesModal() {
  const modal = $("#write-notes-modal");
  const editor = $("#write-notes-editor");
  const hiddenField = $("#additional-instructions");
  if (!modal || !editor || !hiddenField) {
    return;
  }

  editor.value = hiddenField.value || "";
  modal.classList.remove("hidden");
  modal.setAttribute("aria-hidden", "false");
  editor.focus();
}

function closeWriteNotesModal() {
  const modal = $("#write-notes-modal");
  if (!modal) {
    return;
  }
  modal.classList.add("hidden");
  modal.setAttribute("aria-hidden", "true");
}

function saveWriteNotes() {
  const editor = $("#write-notes-editor");
  const hiddenField = $("#additional-instructions");
  if (!editor || !hiddenField) {
    return;
  }

  hiddenField.value = editor.value.trim();
  setWriteNotesStatus();
  closeWriteNotesModal();
}

async function api(path, options = {}) {
  const response = await fetch(path, {
    headers: {
      "Content-Type": "application/json"
    },
    ...options
  });

  const contentType = response.headers.get("content-type") || "";
  let data;

  if (contentType.includes("application/json")) {
    data = await response.json();
  } else {
    const text = await response.text();
    data = { error: text || "请求失败。" };
  }

  if (!response.ok) {
    if (response.status === 401 && data.authRequired) {
      window.location.href = "/login.html";
      return null;
    }
    throw new Error(data.error || "请求失败。");
  }
  return data;
}

function handleOpenTargetResult(result, localMessage) {
  if (!result) {
    return;
  }
  if (result.cloudMode) {
    let downloadUrl = result.downloadUrl || "";
    if (downloadUrl) {
      downloadUrl = new URL(downloadUrl, window.location.href).href;
      window.open(downloadUrl, "_blank", "noopener");
    }
    const lines = [
      result.message || "云端模式不会打开服务器桌面。"
    ];
    if (result.path) {
      lines.push(`路径：${result.path}`);
    }
    if (downloadUrl) {
      lines.push(`下载/预览：${downloadUrl}`);
    }
    setStatusBadge(downloadUrl ? "已生成链接" : "已定位", "success");
    setLog(lines.join("\n"));
    return;
  }
  setStatusBadge("已打开", "success");
  setLog(localMessage);
}

function isCloudAppMode() {
  return state.appMode === "cloud";
}

function getHealthSummaryText(summary) {
  if (summary === "pass") return "通过";
  if (summary === "warn") return "有警告";
  if (summary === "fail") return "有失败";
  return "未检查";
}

function getHealthStatusText(status) {
  if (status === "pass") return "通过";
  if (status === "warn") return "警告";
  if (status === "fail") return "失败";
  return "未知";
}

function renderSystemHealth(health) {
  const card = $("#system-health-card");
  const summary = $("#system-health-summary");
  const detail = $("#system-health-detail");
  const list = $("#system-health-list");
  if (!card || !summary || !detail || !list) {
    return;
  }

  if (!health) {
    card.dataset.health = "idle";
    summary.textContent = "未检查";
    detail.textContent = "检查 PowerShell、ImageMagick、Pandoc、OpenAI Key 和工作区权限。";
    list.innerHTML = "";
    return;
  }

  card.dataset.health = health.summary || "idle";
  summary.textContent = getHealthSummaryText(health.summary);
  detail.textContent = `通过 ${health.passCount || 0} 项，警告 ${health.warnCount || 0} 项，失败 ${health.failCount || 0} 项 · ${health.generatedAt || ""}`;
  const visibleChecks = (health.checks || []).filter((item) => item.status !== "pass");
  const checks = visibleChecks.length ? visibleChecks : (health.checks || []).slice(0, 4);
  list.innerHTML = checks.map((item) => `
    <div class="system-health-item is-${escapeHtml(item.status || "unknown")}">
      <b>${escapeHtml(getHealthStatusText(item.status))}</b>
      <span>${escapeHtml(item.label || item.id || "-")}：${escapeHtml(item.message || "")}</span>
    </div>
  `).join("");
}

async function refreshSystemHealth() {
  const button = $("#refresh-health");
  const summary = $("#system-health-summary");
  if (button) {
    button.disabled = true;
  }
  if (summary) {
    summary.textContent = "检查中";
  }
  try {
    const health = await api("/api/health");
    state.health = health;
    renderSystemHealth(health);
    return health;
  } catch (error) {
    const failedHealth = {
      summary: "fail",
      passCount: 0,
      warnCount: 0,
      failCount: 1,
      generatedAt: "",
      checks: [{
        id: "healthEndpoint",
        label: "健康检查接口",
        status: "fail",
        message: error.message
      }]
    };
    state.health = failedHealth;
    renderSystemHealth(failedHealth);
    throw error;
  } finally {
    if (button) {
      button.disabled = false;
    }
  }
}

function renderTocPreview(item) {
  const panel = $("#toc-preview");
  if (!panel) {
    return;
  }

  if (!item) {
    panel.value = "选择一个已有目录的 BookName 后，这里会显示 toc.md 内容。";
    return;
  }

  if (!item.hasToc || !item.tocContent) {
    panel.value = "当前项目还没有生成 toc.md。";
    return;
  }

  panel.value = item.tocContent;
}

function setFormValue(selector, value) {
  const field = document.querySelector(selector);
  if (!field) {
    return;
  }
  field.value = value || "";
}

function getSelectedWorkspaceItem() {
  const bookName = getBookName();
  return state.workspaces.find((item) => item.bookName === bookName) || null;
}

function getIntakeFormSnapshot() {
  const form = $("#intake-form");
  if (!form) {
    return {
      title: "",
      subtitle: "",
      author: "",
      audience: "",
      type: "",
      coreThesis: "",
      scope: "",
      style: ""
    };
  }

  const data = formToObject(form);
  return {
    title: (data.title || "").trim(),
    subtitle: (data.subtitle || "").trim(),
    author: (data.author || "").trim(),
    audience: (data.audience || "").trim(),
    type: (data.type || "").trim(),
    coreThesis: (data.coreThesis || "").trim(),
    scope: (data.scope || "").trim(),
    style: (data.style || "").trim()
  };
}

function getIntakeBaseline(item) {
  const objective = item?.objectiveData || {};
  return {
    title: (objective.title || "").trim(),
    subtitle: (objective.subtitle || "").trim(),
    author: (objective.author || "").trim(),
    audience: (objective.audience || "").trim(),
    type: (objective.type || "").trim(),
    coreThesis: (objective.core_thesis || "").trim(),
    scope: (objective.scope || "").trim(),
    style: (objective.style || "").trim()
  };
}

function updateIntakeActionState(item = getSelectedWorkspaceItem()) {
  const createButton = $("#intake-create");
  const saveButton = $("#intake-save");
  const hint = $("#intake-action-hint");
  if (!createButton || !saveButton || !hint) {
    return;
  }

  const isExisting = Boolean(item);
  const baseline = getIntakeBaseline(item);
  const current = getIntakeFormSnapshot();
  const isDirty = Object.keys(current).some((key) => current[key] !== baseline[key]);

  createButton.classList.toggle("attention", !isExisting && isDirty);
  saveButton.classList.toggle("attention", isExisting && isDirty);
  saveButton.disabled = !isExisting;

  if (isExisting) {
    createButton.textContent = "创建项目";
    saveButton.textContent = isDirty ? "保存项目修改（未保存）" : "保存项目修改";
    hint.textContent = isDirty
      ? "当前 BookName 已存在。你已修改表单，提交后会更新 objective.md。"
      : "当前 BookName 已存在。提交后会更新 objective.md。";
    return;
  }

  createButton.textContent = isDirty ? "创建项目（未提交）" : "创建项目";
  saveButton.textContent = "保存项目修改";
  hint.textContent = isDirty
    ? "这是一个新项目草稿。提交后会创建并生成 objective.md。"
    : "新项目会创建并生成 objective.md。";
}

function renderIntakePreview(item) {
  const objective = item?.objectiveData || {};
  setFormValue('#intake-form [name="title"]', objective.title || "");
  setFormValue('#intake-form [name="subtitle"]', objective.subtitle || "");
  setFormValue('#intake-form [name="author"]', objective.author || "");
  setFormValue('#intake-form [name="audience"]', objective.audience || "");
  setFormValue('#intake-form [name="type"]', objective.type || "");
  setFormValue('#intake-form [name="coreThesis"]', objective.core_thesis || "");
  setFormValue('#intake-form [name="scope"]', objective.scope || "");
  setFormValue('#intake-form [name="style"]', objective.style || "");
  updateIntakeActionState(item);
  renderObjectiveMarkdownEditor(item);
}

function renderObjectiveMarkdownEditor(item) {
  const editor = $("#objective-md-editor");
  const pathLabel = $("#objective-md-path");
  const saveButton = $("#save-objective-md");
  const status = $("#objective-md-status");

  if (!editor || !pathLabel || !saveButton || !status) {
    return;
  }

  if (!item) {
    editor.value = "选择一个已有项目后，这里会显示 objective.md 内容。";
    editor.disabled = true;
    saveButton.disabled = true;
    pathLabel.textContent = "选择一个 BookName 后，这里会显示 objective.md 路径。";
    status.textContent = "尚未加载 objective.md";
    return;
  }

  editor.disabled = false;
  saveButton.disabled = false;
  editor.value = item.objectiveContent || "";
  pathLabel.textContent = `文件：${item.objectiveRelativePath || "00_brief/objective.md"}`;
  status.textContent = item.hasObjective ? "已加载 objective.md，可直接编辑后保存。" : "当前项目还没有 objective.md，保存后会创建。";
}

async function saveObjectiveMarkdown() {
  const bookName = requireBookName();
  const editor = $("#objective-md-editor");
  const status = $("#objective-md-status");

  if (!editor || editor.disabled) {
    throw new Error("当前没有可保存的 objective.md。");
  }

  if (status) {
    status.textContent = "正在保存 objective.md...";
  }

  const result = await api("/api/objective-md", {
    method: "POST",
    body: JSON.stringify({
      bookName,
      objectiveMarkdown: editor.value || ""
    })
  });

  const selected = state.workspaces.find((item) => item.bookName === bookName);
  if (selected) {
    selected.hasObjective = true;
    selected.objectiveContent = result.objectiveContent || editor.value || "";
    selected.objectiveData = result.objectiveData || selected.objectiveData || {};
    selected.objectiveRelativePath = result.objectiveRelativePath || "00_brief/objective.md";
    renderWorkspaceSelection(selected);
  }

  await refreshStatus();
  setStatusBadge("已保存", "success");
  setLog(`objective.md 已保存：${result.objectiveRelativePath || "00_brief/objective.md"}`);
  if (status) {
    status.textContent = `已保存：${result.objectiveRelativePath || "00_brief/objective.md"}`;
  }
}

function renderPreflightReport(item) {
  const panel = $("#preflight-report");
  if (!panel) {
    return;
  }

  if (!item) {
    panel.value = "选择一个 BookName 后，这里会显示 04 检查报告。";
    return;
  }

  const cached = item ? state.preflightCache[item.bookName] : null;
  const reportText = cached?.reportText || "";
  const cachedRunTime = cached?.reportJson?.run_time || "";
  const currentRunTime = item?.editReport?.run_time || "";
  const needsRefresh = Boolean(item && currentRunTime && currentRunTime !== cachedRunTime);

  if (!reportText || needsRefresh) {
    panel.value = state.preflightLoadingBook === item.bookName
      ? "正在读取检查结果，请稍候..."
      : "当前还没有可显示的检查结果。";
    if (state.preflightLoadingBook !== item.bookName) {
      loadPreflightReport(item);
    }
    return;
  }

  panel.value = reportText;
}

function renderCoverForm(item) {
  const form = $("#cover-form");
  if (!form) {
    return;
  }

  const titleField = form.querySelector('[name="title"]');
  if (titleField) {
    titleField.value = item?.objectiveData?.title || "";
  }
  const authorField = form.querySelector('[name="author"]');
  if (authorField) {
    authorField.value = item?.objectiveData?.author || "";
  }
  const publisherField = $("#cover-edit-publisher");
  if (publisherField && !publisherField.value.trim()) {
    publisherField.value = item?.objectiveData?.publisher || item?.objectiveData?.imprint || "";
  }
  refreshCoverEditText(false);
}

function renderCoverGallerySection(targetId, bookName, section, files) {
  const panel = document.querySelector(targetId);
  if (!panel) {
    return;
  }

  if (!bookName) {
    panel.innerHTML = '<div class="cover-gallery-empty">选择一个 BookName 后，这里会显示封面结果。</div>';
    return;
  }

  if (!files || !files.length) {
    panel.innerHTML = '<div class="cover-gallery-empty">当前分组还没有结果。</div>';
    return;
  }

  panel.innerHTML = files.map((fileName) => {
    const isPdf = /\.pdf$/i.test(fileName);
    const preview = isPdf
      ? '<div class="cover-thumb cover-thumb-pdf">PDF</div>'
      : `<img class="cover-thumb" src="/api/cover-image?bookName=${encodeURIComponent(bookName)}&section=${encodeURIComponent(section)}&fileName=${encodeURIComponent(fileName)}" alt="${escapeHtml(fileName)}">`;

    return `
      <div class="cover-card">
        ${preview}
        <div class="cover-card-meta">
          <strong>${escapeHtml(fileName)}</strong>
          <div class="cover-card-actions">
            <button class="ghost-button cover-file-button" type="button" data-cover-section="${escapeHtml(section)}" data-cover-file="${escapeHtml(fileName)}">打开文件</button>
          </div>
        </div>
      </div>
    `;
  }).join("");

  panel.querySelectorAll("[data-cover-file]").forEach((button) => {
    button.addEventListener("click", async () => {
      try {
        const currentBookName = requireBookName();
        const result = await api("/api/reveal-cover-file", {
          method: "POST",
          body: JSON.stringify({
            bookName: currentBookName,
            section: button.dataset.coverSection,
            fileName: button.dataset.coverFile
          })
        });
        handleOpenTargetResult(result, `已打开封面文件：${button.dataset.coverFile}`);
      } catch (error) {
        setStatusBadge("失败", "failed");
        setLog(error.message);
      }
    });
  });
}

function renderCoverWorkbenchState(item) {
  if (!item) {
    return;
  }

  const cached = state.coverWorkbenchCache[item.bookName] || null;
  if (!cached) {
    if (state.coverWorkbenchLoadingBook !== item.bookName) {
      loadCoverWorkbenchState(item);
    }
    return;
  }

  const promptField = $("#cover-midjourney-prompt");
  if (promptField && cached.prompt && !promptField.dataset.dirty) {
    promptField.value = cached.prompt;
  }

  const requestField = $("#cover-ai-request");
  if (requestField && cached.assistantRequest && !requestField.dataset.dirty) {
    requestField.value = cached.assistantRequest;
  }

  const responseField = $("#cover-ai-response");
  if (responseField && cached.assistantResponse) {
    responseField.value = cached.assistantResponse;
  }

  const publisherField = $("#cover-edit-publisher");
  if (publisherField && cached.publisher && !publisherField.value.trim()) {
    publisherField.value = cached.publisher;
  }

  const imageModelField = $("#cover-edit-image-model");
  if (imageModelField && cached.imageModel) {
    imageModelField.value = cached.imageModel;
  }

  const editTextField = $("#cover-edit-text");
  if (editTextField && cached.editText && !editTextField.dataset.dirty) {
    editTextField.value = cached.editText;
  }

  const selectedImportFile = cached.selectedImportFile || cached.latestImportFile;
  if (selectedImportFile && !state.coverBaseImport) {
    const preview = $("#cover-base-import-preview");
    const meta = $("#cover-base-import-meta");
    const importFiles = Array.isArray(cached.importFiles) ? cached.importFiles : [];
    const selectedIndex = importFiles.indexOf(selectedImportFile);
    if (preview) {
      preview.innerHTML = `<img src="/api/cover-image?bookName=${encodeURIComponent(item.bookName)}&section=next-imports&fileName=${encodeURIComponent(selectedImportFile)}&t=${Date.now()}" alt="">`;
    }
    if (meta) {
      const counter = selectedIndex >= 0 ? `第 ${selectedIndex + 1} / ${importFiles.length} 张 · ` : "";
      meta.textContent = `${counter}当前底图：${selectedImportFile}`;
    }
  }

  const editPreview = $("#cover-edit-result-preview");
  const editMeta = $("#cover-edit-result-meta");
  if (cached.latestEditedFile) {
    if (editPreview) {
      editPreview.innerHTML = `<img src="/api/cover-image?bookName=${encodeURIComponent(item.bookName)}&section=next-layout&fileName=${encodeURIComponent(cached.latestEditedFile)}&t=${Date.now()}" alt="">`;
    }
    if (editMeta) {
      editMeta.textContent = `上次修图结果：${cached.latestEditedFile}`;
    }
  } else {
    if (editPreview) {
      editPreview.innerHTML = "<span>调用图形模型修图后，这里会显示新生成的封面图。</span>";
    }
    if (editMeta) {
      editMeta.textContent = "尚未生成修图结果。";
    }
  }
}

async function loadCoverWorkbenchState(item) {
  if (!item) {
    return;
  }
  state.coverWorkbenchLoadingBook = item.bookName;
  try {
    const result = await api(`/api/cover-workbench-state?bookName=${encodeURIComponent(item.bookName)}&edition=ebook&t=${Date.now()}`);
    state.coverWorkbenchCache[item.bookName] = result.workbench || null;
  } catch {
    state.coverWorkbenchCache[item.bookName] = null;
  } finally {
    state.coverWorkbenchLoadingBook = "";
    const selected = getSelectedWorkspaceItem();
    if (selected?.bookName === item.bookName) {
      renderCoverWorkbenchState(item);
    }
  }
}

function formatCoverCopyCandidates(copyJson) {
  const candidates = copyJson?.candidates || {};
  const editorNotes = Array.isArray(copyJson?.editor_notes) ? copyJson.editor_notes : [];
  const blocks = [];

  [
    ["副标题候选", candidates.subtitle || []],
    ["封底短句候选", candidates.back_cover_hook || []],
    ["腰封文案候选", candidates.obi_copy || []],
    ["宣传语候选", candidates.marketing_tagline || []]
  ].forEach(([title, items]) => {
    blocks.push(`## ${title}`);
    if (items.length) {
      items.forEach((item) => blocks.push(`- ${item}`));
    } else {
      blocks.push("- ");
    }
    blocks.push("");
  });

  blocks.push("## 编辑备注");
  if (editorNotes.length) {
    editorNotes.forEach((item) => blocks.push(`- ${item}`));
  } else {
    blocks.push("- ");
  }

  return blocks.join("\n");
}

function setCoverCopyFields(copyJson) {
  const selected = copyJson?.selected || {};
  setFormValue("#cover-copy-subtitle", selected.subtitle || "");
  setFormValue("#cover-copy-hook", selected.back_cover_hook || "");
  setFormValue("#cover-copy-obi", selected.obi_copy || "");
  setFormValue("#cover-copy-tagline", selected.marketing_tagline || "");
  setFormValue("#cover-copy-spine", selected.spine_text || "");
  setFormValue("#cover-copy-blurb", selected.back_cover_blurb || "");
  setFormValue("#cover-copy-author-bio", selected.author_bio || "");
  setFormValue("#cover-copy-editor-notes", Array.isArray(copyJson?.editor_notes) ? copyJson.editor_notes.join("\n") : "");
  const candidatesPanel = $("#cover-copy-candidates");
  if (candidatesPanel) {
    candidatesPanel.value = copyJson ? formatCoverCopyCandidates(copyJson) : "运行 08g-copy.ps1 后，这里会显示候选池。";
  }
  refreshCoverEditText(false);
}

function renderCoverCopyEditor(item) {
  if (!item) {
    setCoverCopyFields(null);
    return;
  }

  const cached = state.coverCopyCache[item.bookName] || null;
  if (!cached) {
    setCoverCopyFields(null);
    if (state.coverCopyLoadingBook !== item.bookName) {
      loadCoverCopy(item);
    }
    return;
  }

  setCoverCopyFields(cached);
}

async function loadCoverCopy(item) {
  if (!item) {
    return;
  }

  state.coverCopyLoadingBook = item.bookName;
  try {
    const result = await api(`/api/cover-copy?bookName=${encodeURIComponent(item.bookName)}&t=${Date.now()}`);
    state.coverCopyCache[item.bookName] = result.copyJson || null;
  } catch (error) {
    state.coverCopyCache[item.bookName] = {
      selected: {
        subtitle: "",
        back_cover_hook: "",
        obi_copy: "",
        marketing_tagline: "",
        back_cover_blurb: "",
        author_bio: "",
        spine_text: ""
      },
      candidates: {
        subtitle: [],
        back_cover_hook: [],
        obi_copy: [],
        marketing_tagline: []
      },
      editor_notes: [`读取封面文案失败：${error.message}`]
    };
  } finally {
    state.coverCopyLoadingBook = "";
    renderCoverCopyEditor(item);
  }
}

async function saveCoverCopy() {
  const bookName = requireBookName();
  const payload = {
    bookName,
    selected: {
      subtitle: ($("#cover-copy-subtitle")?.value || "").trim(),
      back_cover_hook: ($("#cover-copy-hook")?.value || "").trim(),
      obi_copy: ($("#cover-copy-obi")?.value || "").trim(),
      marketing_tagline: ($("#cover-copy-tagline")?.value || "").trim(),
      back_cover_blurb: ($("#cover-copy-blurb")?.value || "").trim(),
      author_bio: ($("#cover-copy-author-bio")?.value || "").trim(),
      spine_text: ($("#cover-copy-spine")?.value || "").trim()
    },
    editorNotes: ($("#cover-copy-editor-notes")?.value || "")
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean)
  };

  const cached = state.coverCopyCache[bookName] || {};
  payload.candidates = cached.candidates || {};

  const result = await api("/api/cover-copy", {
    method: "POST",
    body: JSON.stringify(payload)
  });

  state.coverCopyCache[bookName] = result.copyJson || payload;
  renderCoverCopyEditor(getSelectedWorkspaceItem());
  setStatusBadge("已保存", "success");
  setLog(`封面文案已保存到 ${bookName} 的 cover_copy.json`);
}

function setFrontmatterFields(frontmatter) {
  setFormValue(
    "#frontmatter-cover-page",
    frontmatter?.coverPage || "è¿è¡Œ 08h-frontmatter.ps1 åŽï¼Œè¿™é‡Œä¼šæ˜¾ç¤ºå°é¢é¡µ markdownã€‚"
  );
  setFormValue(
    "#frontmatter-title-page",
    frontmatter?.titlePage || "è¿è¡Œ 08h-frontmatter.ps1 åŽï¼Œè¿™é‡Œä¼šæ˜¾ç¤ºæ‰‰é¡µ markdownã€‚"
  );
  setFormValue(
    "#frontmatter-copyright-page",
    frontmatter?.copyrightPage || "è¿è¡Œ 08h-frontmatter.ps1 åŽï¼Œè¿™é‡Œä¼šæ˜¾ç¤ºç‰ˆæƒé¡µ markdownã€‚"
  );
}

function renderFrontmatterEditor(item) {
  if (!item) {
    setFrontmatterFields(null);
    return;
  }

  const cached = state.frontmatterCache[item.bookName] || null;
  if (!cached) {
    setFrontmatterFields(null);
    if (state.frontmatterLoadingBook !== item.bookName) {
      loadFrontmatter(item);
    }
    return;
  }

  setFrontmatterFields(cached);
}

async function loadFrontmatter(item) {
  if (!item) {
    return;
  }

  state.frontmatterLoadingBook = item.bookName;
  try {
    const result = await api(`/api/frontmatter?bookName=${encodeURIComponent(item.bookName)}&t=${Date.now()}`);
    state.frontmatterCache[item.bookName] = result.frontmatter || null;
  } catch (error) {
    state.frontmatterCache[item.bookName] = {
      coverPage: `è¯»å–å°é¢é¡µå¤±è´¥ï¼š${error.message}`,
      titlePage: `è¯»å–æ‰‰é¡µå¤±è´¥ï¼š${error.message}`,
      copyrightPage: `è¯»å–ç‰ˆæƒé¡µå¤±è´¥ï¼š${error.message}`
    };
  } finally {
    state.frontmatterLoadingBook = "";
    renderFrontmatterEditor(item);
  }
}

async function saveFrontmatter() {
  const bookName = requireBookName();
  const payload = {
    bookName,
    coverPage: $("#frontmatter-cover-page")?.value || "",
    titlePage: $("#frontmatter-title-page")?.value || "",
    copyrightPage: $("#frontmatter-copyright-page")?.value || ""
  };

  const result = await api("/api/frontmatter", {
    method: "POST",
    body: JSON.stringify(payload)
  });

  state.frontmatterCache[bookName] = result.frontmatter || payload;
  renderFrontmatterEditor(getSelectedWorkspaceItem());
  setStatusBadge("å·²ä¿å­˜", "success");
  setLog(`å‰ç½®ä¸‰é¡µå·²ä¿å­˜åˆ° ${bookName} çš„ 00_frontmatter/ebook ç›®å½•ã€‚`);
}

function renderCoverPanel(item) {
  const summary = $("#cover-summary");
  const report = $("#cover-report");
  const nextSummary = $("#cover-next-summary");
  const nextReport = $("#cover-next-report");
  const cached = item ? state.coverCache[item.bookName] : null;
  const artifacts = cached || item?.coverArtifacts || null;

  renderCoverForm(item);

  if (!summary || !report) {
    return;
  }

  if (!item) {
    summary.textContent = "选择一个 BookName 后，这里会显示封面系统的输出摘要。";
    report.value = "运行 08-cover.ps1 后，这里会显示 final/cover_report.md 的内容。";
    renderCoverGallerySection("#cover-drafts", "", "drafts", []);
    renderCoverGallerySection("#cover-layout", "", "layout", []);
    renderCoverGallerySection("#cover-mockup", "", "mockup", []);
    renderCoverGallerySection("#cover-final", "", "final", []);
    renderCoverGallerySection("#cover-next-imports", "", "next-imports", []);
    renderCoverGallerySection("#cover-next-layout", "", "next-layout", []);
    renderCoverGallerySection("#cover-next-print-spread", "", "next-print-spread", []);
    renderCoverGallerySection("#cover-next-mockup", "", "next-mockup", []);
    renderCoverGallerySection("#cover-next-final", "", "next-final", []);
    renderKdpAcceptancePanel(null, null);
    if (nextSummary) nextSummary.textContent = "Run 08N after selecting a BookName.";
    if (nextReport) nextReport.value = "Run 08n-export.ps1 to see next_cover_report.md.";
    return;
  }

  if (!artifacts) {
    summary.textContent = "当前项目还没有 07_cover 输出。";
    report.value = "当前项目还没有生成 cover_report.md。";
    renderCoverGallerySection("#cover-drafts", item.bookName, "drafts", []);
    renderCoverGallerySection("#cover-layout", item.bookName, "layout", []);
    renderCoverGallerySection("#cover-mockup", item.bookName, "mockup", []);
    renderCoverGallerySection("#cover-final", item.bookName, "final", []);
    renderCoverGallerySection("#cover-next-imports", item.bookName, "next-imports", []);
    renderCoverGallerySection("#cover-next-layout", item.bookName, "next-layout", []);
    renderCoverGallerySection("#cover-next-print-spread", item.bookName, "next-print-spread", []);
    renderCoverGallerySection("#cover-next-mockup", item.bookName, "next-mockup", []);
    renderCoverGallerySection("#cover-next-final", item.bookName, "next-final", []);
    renderKdpAcceptancePanel(item, null);
    if (nextSummary) nextSummary.textContent = "08N next cover flow has not produced artifacts yet.";
    if (nextReport) nextReport.value = "No next_cover_report.md yet.";
    if (state.coverLoadingBook !== item.bookName) {
      loadCoverArtifacts(item);
    }
    return;
  }

  summary.textContent =
    `brief: ${artifacts.hasBrief ? "已生成" : "未生成"} · ` +
    `strategy: ${artifacts.hasStrategy ? "已生成" : "未生成"} · ` +
    `drafts: ${artifacts.draftFiles?.length || 0} · ` +
    `layout: ${artifacts.layoutFiles?.length || 0} · ` +
    `mockup: ${artifacts.mockupFiles?.length || 0} · ` +
    `final: ${artifacts.finalFiles?.length || 0}` +
    (artifacts.topCandidate ? ` · top: ${artifacts.topCandidate}` : "");

  report.value = artifacts.reportText || "当前项目还没有生成 cover_report.md。";

  renderCoverGallerySection("#cover-drafts", item.bookName, "drafts", artifacts.draftFiles || []);
  renderCoverGallerySection("#cover-layout", item.bookName, "layout", artifacts.layoutFiles || []);
  renderCoverGallerySection("#cover-mockup", item.bookName, "mockup", artifacts.mockupFiles || []);
  renderCoverGallerySection("#cover-final", item.bookName, "final", artifacts.finalFiles || []);

  const next = artifacts.next || {};
  if (nextSummary) {
    nextSummary.textContent =
      `base: ${next.hasBaseBrief ? "ready" : "missing"} · ` +
      `prompts: ${next.hasPrompts ? "ready" : "missing"} · ` +
      `review: ${next.hasReview ? "ready" : "missing"} · ` +
      `imports: ${next.importFiles?.length || 0} · ` +
      `layout: ${next.layoutFiles?.length || 0} · ` +
      `print: ${next.printSpreadFiles?.length || 0} · ` +
      `mockup: ${next.mockupFiles?.length || 0} · ` +
      `final: ${next.finalFiles?.length || 0}`;
  }
  if (nextReport) {
    nextReport.value = next.reportText || "No next_cover_report.md yet.";
  }
  renderCoverGallerySection("#cover-next-imports", item.bookName, "next-imports", next.importFiles || []);
  renderCoverGallerySection("#cover-next-layout", item.bookName, "next-layout", next.layoutFiles || []);
  renderCoverGallerySection("#cover-next-print-spread", item.bookName, "next-print-spread", next.printSpreadFiles || []);
  renderCoverGallerySection("#cover-next-mockup", item.bookName, "next-mockup", next.mockupFiles || []);
  renderCoverGallerySection("#cover-next-final", item.bookName, "next-final", next.finalFiles || []);
  renderKdpAcceptancePanel(item, artifacts.kdpAcceptance || null);
  renderCoverWorkbenchState(item);
}

async function loadCoverArtifacts(item) {
  if (!item) {
    return;
  }

  state.coverLoadingBook = item.bookName;
  try {
    const result = await api(`/api/cover-files?bookName=${encodeURIComponent(item.bookName)}&t=${Date.now()}`);
    state.coverCache[item.bookName] = result.coverArtifacts || null;
  } catch (error) {
    state.coverCache[item.bookName] = {
      hasBrief: false,
      hasStrategy: false,
      draftFiles: [],
      layoutFiles: [],
      mockupFiles: [],
      finalFiles: [],
      kdpAcceptance: {
        hasReport: false,
        report: null,
        reportText: "",
        pdfFiles: [],
        llmTextRegions: {
          hasLatest: false,
          latest: null
        }
      },
      next: {
        hasBaseBrief: false,
        hasPrompts: false,
        hasReview: false,
        importFiles: [],
        layoutFiles: [],
        printSpreadFiles: [],
        mockupFiles: [],
        finalFiles: [],
        reportText: ""
      },
      selectedReviewFiles: [],
      topCandidate: "",
      reportText: `读取封面结果失败：${error.message}`
    };
  } finally {
    state.coverLoadingBook = "";
    renderCoverPanel(item);
  }
}

function getKdpVerdictText(verdict) {
  if (verdict === "pass") return "适合提交";
  if (verdict === "review") return "尺寸通过，需视觉复核";
  if (verdict === "fail") return "不适合提交";
  return "尚未验收";
}

function getKdpCheckText(status) {
  if (status === "pass") return "通过";
  if (status === "fail") return "失败";
  if (status === "warn") return "注意";
  if (status === "review") return "复核";
  if (status === "manual") return "人工";
  return "信息";
}

function setKdpFieldValue(selector, value) {
  const field = $(selector);
  if (field && value !== undefined && value !== null && value !== "") {
    field.value = value;
  }
}

function getKdpPaperMultiplier(paperType) {
  if (paperType === "bw-cream") return 0.0025;
  if (paperType === "premium-color") return 0.002347;
  return 0.002252;
}

function getCurrentKdpGuideSpec() {
  const trimWidth = Number($("#kdp-trim-width")?.value || 6);
  const trimHeight = Number($("#kdp-trim-height")?.value || 9);
  const bleed = Number($("#kdp-bleed")?.value || 0.125);
  const pageCount = Math.max(1, Number($("#kdp-page-count")?.value || 120));
  const paperType = $("#kdp-paper-type")?.value || "bw-white";
  const spine = pageCount * getKdpPaperMultiplier(paperType);
  const width = bleed + trimWidth + spine + trimWidth + bleed;
  const height = bleed + trimHeight + bleed;
  const frontBackSafeInsetFromTrim = 0.125;
  const spineSafeInset = 0.0625;
  const barcodeWidth = 2;
  const barcodeHeight = 1.2;
  const barcodeInset = 0.25;
  return {
    trimWidth,
    trimHeight,
    bleed,
    spine,
    width,
    height,
    whiteWidth: (trimWidth * 2) + spine,
    whiteHeight: trimHeight,
    frontBackSafeWidth: trimWidth - (frontBackSafeInsetFromTrim * 2),
    frontBackSafeHeight: trimHeight - (frontBackSafeInsetFromTrim * 2),
    spineSafeWidth: Math.max(0, spine - (spineSafeInset * 2)),
    spineSafeHeight: trimHeight - (frontBackSafeInsetFromTrim * 2),
    frontBackSafeInsetFromTrim,
    spineSafeInset,
    barcodeWidth,
    barcodeHeight,
    barcodeInset
  };
}

function updateKdpGuidePreview(spec = null) {
  const guide = $("#kdp-guide-preview");
  if (!guide) {
    return;
  }
  const current = spec || getCurrentKdpGuideSpec();
  const pct = (value, base) => `${((value / base) * 100).toFixed(3)}%`;
  const spineLeft = (current.bleed + current.trimWidth) / current.width;
  const spineRight = (current.bleed + current.trimWidth + current.spine) / current.width;
  const spineCenter = (spineLeft + spineRight) / 2;
  const safeMargin = current.bleed + 0.25;
  const spineSafeLeft = (current.bleed + current.trimWidth + current.spineSafeInset) / current.width;
  const spineSafeRight = (current.bleed + current.trimWidth + current.spine - current.spineSafeInset) / current.width;
  const barcodeWidth = Number(current.barcodeWidth || 2);
  const barcodeHeight = Number(current.barcodeHeight || 1.2);
  const barcodeInset = Number(current.barcodeInset || 0.25);
  const barcodeLeft = current.bleed + current.trimWidth - barcodeInset - barcodeWidth;
  const barcodeTop = current.bleed + current.trimHeight - barcodeInset - barcodeHeight;

  guide.style.setProperty("--kdp-guide-ratio", String(current.width / current.height));
  guide.style.setProperty("--kdp-bleed-x", pct(current.bleed, current.width));
  guide.style.setProperty("--kdp-bleed-y", pct(current.bleed, current.height));
  guide.style.setProperty("--kdp-safe-x", pct(safeMargin, current.width));
  guide.style.setProperty("--kdp-safe-y", pct(safeMargin, current.height));
  guide.style.setProperty("--kdp-spine-left", `${(spineLeft * 100).toFixed(3)}%`);
  guide.style.setProperty("--kdp-spine-right", `${(spineRight * 100).toFixed(3)}%`);
  guide.style.setProperty("--kdp-spine-center", `${(spineCenter * 100).toFixed(3)}%`);
  guide.style.setProperty("--kdp-spine-safe-left", `${(spineSafeLeft * 100).toFixed(3)}%`);
  guide.style.setProperty("--kdp-spine-safe-right", `${(spineSafeRight * 100).toFixed(3)}%`);
  guide.style.setProperty("--kdp-barcode-left", pct(barcodeLeft, current.width));
  guide.style.setProperty("--kdp-barcode-top", pct(barcodeTop, current.height));
  guide.style.setProperty("--kdp-barcode-width", pct(barcodeWidth, current.width));
  guide.style.setProperty("--kdp-barcode-height", pct(barcodeHeight, current.height));
  const spineField = $("#kdp-spine-width");
  if (spineField) {
    spineField.value = `${formatInches(current.spine)} in / ${formatMm(current.spine)} mm`;
  }
  renderKdpSizeRules(current);
}

function applyKdpLineVariables(element, spec) {
  if (!element || !spec) {
    return;
  }
  const pct = (value, base) => `${((value / base) * 100).toFixed(3)}%`;
  const spineLeft = (spec.bleed + spec.trimWidth) / spec.width;
  const spineRight = (spec.bleed + spec.trimWidth + spec.spine) / spec.width;
  const spineCenter = (spineLeft + spineRight) / 2;
  const safeMargin = spec.bleed + 0.25;
  const spineSafeLeft = (spec.bleed + spec.trimWidth + spec.spineSafeInset) / spec.width;
  const spineSafeRight = (spec.bleed + spec.trimWidth + spec.spine - spec.spineSafeInset) / spec.width;
  const barcodeWidth = Number(spec.barcodeWidth || 2);
  const barcodeHeight = Number(spec.barcodeHeight || 1.2);
  const barcodeInset = Number(spec.barcodeInset || 0.25);
  const barcodeLeft = spec.bleed + spec.trimWidth - barcodeInset - barcodeWidth;
  const barcodeTop = spec.bleed + spec.trimHeight - barcodeInset - barcodeHeight;

  element.style.setProperty("--kdp-bleed-x", pct(spec.bleed, spec.width));
  element.style.setProperty("--kdp-bleed-y", pct(spec.bleed, spec.height));
  element.style.setProperty("--kdp-safe-x", pct(safeMargin, spec.width));
  element.style.setProperty("--kdp-safe-y", pct(safeMargin, spec.height));
  element.style.setProperty("--kdp-spine-left", `${(spineLeft * 100).toFixed(3)}%`);
  element.style.setProperty("--kdp-spine-right", `${(spineRight * 100).toFixed(3)}%`);
  element.style.setProperty("--kdp-spine-center", `${(spineCenter * 100).toFixed(3)}%`);
  element.style.setProperty("--kdp-spine-safe-left", `${(spineSafeLeft * 100).toFixed(3)}%`);
  element.style.setProperty("--kdp-spine-safe-right", `${(spineSafeRight * 100).toFixed(3)}%`);
  element.style.setProperty("--kdp-barcode-left", pct(barcodeLeft, spec.width));
  element.style.setProperty("--kdp-barcode-top", pct(barcodeTop, spec.height));
  element.style.setProperty("--kdp-barcode-width", pct(barcodeWidth, spec.width));
  element.style.setProperty("--kdp-barcode-height", pct(barcodeHeight, spec.height));
}

async function loadPdfJs() {
  if (state.kdpPdf.pdfjs) {
    return state.kdpPdf.pdfjs;
  }
  const pdfjs = await import(PDFJS_MODULE_URL);
  pdfjs.GlobalWorkerOptions.workerSrc = PDFJS_WORKER_URL;
  state.kdpPdf.pdfjs = pdfjs;
  return pdfjs;
}

function loadScriptOnce(url, globalName) {
  return new Promise((resolve, reject) => {
    if (globalName && window[globalName]) {
      resolve(window[globalName]);
      return;
    }
    const existing = Array.from(document.querySelectorAll("script[data-loader-url]"))
      .find((item) => item.dataset.loaderUrl === url);
    if (existing) {
      existing.addEventListener("load", () => resolve(globalName ? window[globalName] : true), { once: true });
      existing.addEventListener("error", () => reject(new Error(`Failed to load ${url}`)), { once: true });
      return;
    }
    const script = document.createElement("script");
    script.src = url;
    script.async = true;
    script.dataset.loaderUrl = url;
    script.onload = () => resolve(globalName ? window[globalName] : true);
    script.onerror = () => reject(new Error(`Failed to load ${url}`));
    document.head.appendChild(script);
  });
}

async function loadTesseract() {
  if (state.kdpPdf.tesseract) {
    return state.kdpPdf.tesseract;
  }
  const tesseract = await loadScriptOnce(TESSERACT_SCRIPT_URL, "Tesseract");
  state.kdpPdf.tesseract = tesseract;
  return tesseract;
}

function setKdpPdfViewerStatus(text) {
  const label = $("#kdp-pdf-zoom-label");
  if (label) {
    label.textContent = text;
  }
}

function clearKdpPdfViewer(message = "提交 PDF 后，这里会显示自定义 KDP 检视器。") {
  state.kdpPdf.document = null;
  state.kdpPdf.page = null;
  state.kdpPdf.mode = "pdf";
  state.kdpPdf.image = null;
  state.kdpPdf.imageSize = null;
  state.kdpPdf.source = null;
  state.kdpPdf.url = "";
  state.kdpPdf.spec = null;
  state.kdpPdf.ocrCanvasWidth = 0;
  state.kdpPdf.ocrCanvasHeight = 0;
  state.kdpPdf.textRegions = [];
  state.kdpPdf.visionDebug = null;
  const page = $("#kdp-pdf-page");
  const empty = $("#kdp-pdf-empty");
  const canvas = $("#kdp-pdf-canvas");
  if (page) page.classList.remove("is-visible");
  if (empty) {
    empty.hidden = false;
    empty.textContent = message;
  }
  if (canvas) {
    canvas.width = 0;
    canvas.height = 0;
  }
  renderKdpTextRegions([]);
  renderKdpTextRegionReport([]);
  setKdpPdfViewerStatus("未加载 PDF");
}

function getKdpPdfFitScale() {
  const stage = $("#kdp-pdf-stage");
  const page = state.kdpPdf.page;
  if (!stage || !page) {
    return 1;
  }
  const baseViewport = state.kdpPdf.mode === "image" && state.kdpPdf.imageSize
    ? state.kdpPdf.imageSize
    : page.getViewport({ scale: 1 });
  const availableWidth = Math.max(240, stage.clientWidth - 32);
  return Math.max(0.2, Math.min(4, availableWidth / baseViewport.width));
}

async function renderKdpPdfPage() {
  const page = state.kdpPdf.page;
  const canvas = $("#kdp-pdf-canvas");
  const pageWrap = $("#kdp-pdf-page");
  const overlay = $("#kdp-pdf-overlay");
  const empty = $("#kdp-pdf-empty");
  if (!page || !canvas || !pageWrap || !overlay) {
    return;
  }

  if (state.kdpPdf.renderTask) {
    try {
      state.kdpPdf.renderTask.cancel();
    } catch {
      // Ignore cancellation races; the next render wins.
    }
  }

  const viewport = state.kdpPdf.mode === "image" && state.kdpPdf.imageSize
    ? {
        width: state.kdpPdf.imageSize.width * state.kdpPdf.scale,
        height: state.kdpPdf.imageSize.height * state.kdpPdf.scale
      }
    : page.getViewport({ scale: state.kdpPdf.scale });
  const context = canvas.getContext("2d");
  canvas.width = Math.ceil(viewport.width);
  canvas.height = Math.ceil(viewport.height);
  canvas.style.width = `${Math.ceil(viewport.width)}px`;
  canvas.style.height = `${Math.ceil(viewport.height)}px`;
  pageWrap.style.width = canvas.style.width;
  pageWrap.style.height = canvas.style.height;
  overlay.style.width = canvas.style.width;
  overlay.style.height = canvas.style.height;
  applyKdpLineVariables(overlay, state.kdpPdf.spec || getCurrentKdpGuideSpec());
  renderKdpTextRegions(state.kdpPdf.textRegions);

  pageWrap.classList.add("is-visible");
  if (empty) empty.hidden = true;
  setKdpPdfViewerStatus(`${Math.round(state.kdpPdf.scale * 100)}%`);

  if (state.kdpPdf.mode === "image" && state.kdpPdf.image) {
    context.clearRect(0, 0, canvas.width, canvas.height);
    context.drawImage(state.kdpPdf.image, 0, 0, canvas.width, canvas.height);
    return;
  }

  const renderTask = page.render({ canvasContext: context, viewport });
  state.kdpPdf.renderTask = renderTask;
  try {
    await renderTask.promise;
  } catch (error) {
    if (error?.name !== "RenderingCancelledException") {
      throw error;
    }
  } finally {
    if (state.kdpPdf.renderTask === renderTask) {
      state.kdpPdf.renderTask = null;
    }
  }
}

function buildKdpVisionDebugFromSaved(saved, fallbackWidth = 0, fallbackHeight = 0) {
  if (!saved) {
    return null;
  }
  return {
    image: saved.image || { width: fallbackWidth, height: fallbackHeight },
    modelImage: saved.modelImage || saved.image || { width: fallbackWidth, height: fallbackHeight },
    coordinateScale: saved.coordinateScale || { x: 1, y: 1 },
    saved: saved.saved || null,
    usage: saved.usage || null,
    responseId: saved.responseId || "",
    responseStatus: saved.responseStatus || "",
    createdAt: saved.createdAt || ""
  };
}

function restoreKdpLatestVisionResult(saved, spec) {
  if (!saved || !Array.isArray(saved.regions) || !saved.regions.length) {
    renderKdpTextRegions([]);
    renderKdpTextRegionReport([]);
    return;
  }
  const dpi = Number(saved.dpi || 300);
  const imageWidth = Number(saved.image?.width || 0);
  const imageHeight = Number(saved.image?.height || 0);
  state.kdpPdf.ocrCanvasWidth = imageWidth;
  state.kdpPdf.ocrCanvasHeight = imageHeight;
  state.kdpPdf.visionDebug = buildKdpVisionDebugFromSaved(saved, imageWidth, imageHeight);
  state.kdpPdf.textRegions = saved.regions
    .map((region, index) => normalizeLlmRegion(region, index, spec || state.kdpPdf.spec || getCurrentKdpGuideSpec(), dpi))
    .filter((region) => region.width > 0 && region.height > 0);
  renderKdpTextRegions(state.kdpPdf.textRegions);
  renderKdpTextRegionReport(state.kdpPdf.textRegions);
  setKdpPdfViewerStatus(`已恢复上次 LLM 识别 · ${state.kdpPdf.textRegions.length} 个文字区域`);
}

async function loadKdpPdfViewer(url, spec, latestVision = null) {
  if (!url) {
    clearKdpPdfViewer();
    return;
  }
  state.kdpPdf.spec = spec || getCurrentKdpGuideSpec();
  if (state.kdpPdf.url === url && state.kdpPdf.page) {
    applyKdpLineVariables($("#kdp-pdf-overlay"), state.kdpPdf.spec);
    restoreKdpLatestVisionResult(latestVision, state.kdpPdf.spec);
    return;
  }

  const empty = $("#kdp-pdf-empty");
  if (empty) {
    empty.hidden = false;
    empty.textContent = "正在加载 PDF 检视器...";
  }
  setKdpPdfViewerStatus("加载中");
  state.kdpPdf.url = url;
  state.kdpPdf.mode = "pdf";
  state.kdpPdf.image = null;
  state.kdpPdf.imageSize = null;
  state.kdpPdf.source = state.kdpPdf.source || { type: "PDF" };
  state.kdpPdf.loading = true;
  state.kdpPdf.textRegions = [];
  state.kdpPdf.visionDebug = null;
  state.kdpPdf.ocrCanvasWidth = 0;
  state.kdpPdf.ocrCanvasHeight = 0;
  renderKdpTextRegions([]);
  renderKdpTextRegionReport([]);

  try {
    const pdfjs = await loadPdfJs();
    const documentTask = pdfjs.getDocument({ url });
    const pdfDocument = await documentTask.promise;
    const page = await pdfDocument.getPage(1);
    state.kdpPdf.document = pdfDocument;
    state.kdpPdf.page = page;
    state.kdpPdf.scale = getKdpPdfFitScale();
    await renderKdpPdfPage();
    restoreKdpLatestVisionResult(latestVision, state.kdpPdf.spec);
  } catch (error) {
    clearKdpPdfViewer(`PDF.js 加载失败：${error.message}`);
  } finally {
    state.kdpPdf.loading = false;
  }
}

async function loadKdpImageViewer(url, spec, latestVision = null) {
  if (!url) {
    clearKdpPdfViewer();
    return;
  }
  state.kdpPdf.spec = spec || getCurrentKdpGuideSpec();
  const empty = $("#kdp-pdf-empty");
  if (empty) {
    empty.hidden = false;
    empty.textContent = "Loading PNG KDP viewer...";
  }
  setKdpPdfViewerStatus("Loading PNG");
  state.kdpPdf.url = url;
  state.kdpPdf.mode = "image";
  state.kdpPdf.source = state.kdpPdf.source || { type: "PNG" };
  state.kdpPdf.loading = true;
  state.kdpPdf.document = null;
  state.kdpPdf.textRegions = [];
  state.kdpPdf.visionDebug = null;
  state.kdpPdf.ocrCanvasWidth = 0;
  state.kdpPdf.ocrCanvasHeight = 0;
  renderKdpTextRegions([]);
  renderKdpTextRegionReport([]);

  try {
    const image = await loadImageElement(url);
    const width = image.naturalWidth || image.width;
    const height = image.naturalHeight || image.height;
    state.kdpPdf.image = image;
    state.kdpPdf.imageSize = { width, height };
    state.kdpPdf.page = {
      getViewport: ({ scale = 1 } = {}) => ({ width: width * scale, height: height * scale }),
      render: ({ canvasContext, viewport }) => {
        canvasContext.clearRect(0, 0, Math.ceil(viewport.width), Math.ceil(viewport.height));
        canvasContext.drawImage(image, 0, 0, Math.ceil(viewport.width), Math.ceil(viewport.height));
        return { promise: Promise.resolve(), cancel() {} };
      }
    };
    state.kdpPdf.ocrCanvasWidth = width;
    state.kdpPdf.ocrCanvasHeight = height;
    state.kdpPdf.scale = getKdpPdfFitScale();
    await renderKdpPdfPage();
    restoreKdpLatestVisionResult(latestVision, state.kdpPdf.spec);
    setKdpPdfViewerStatus(`PNG ${width} x ${height}px`);
  } catch (error) {
    clearKdpPdfViewer(`PNG load failed: ${error.message}`);
  } finally {
    state.kdpPdf.loading = false;
  }
}

async function zoomKdpPdf(delta) {
  if (!state.kdpPdf.page) {
    return;
  }
  state.kdpPdf.scale = Math.max(0.2, Math.min(5, state.kdpPdf.scale + delta));
  await renderKdpPdfPage();
}

async function fitKdpPdfToWidth() {
  if (!state.kdpPdf.page) {
    return;
  }
  state.kdpPdf.scale = getKdpPdfFitScale();
  await renderKdpPdfPage();
}

async function setKdpPdfActualSize() {
  if (!state.kdpPdf.page) {
    return;
  }
  state.kdpPdf.scale = 1;
  await renderKdpPdfPage();
}

function getHorizontalOverlap(leftA, rightA, leftB, rightB) {
  return Math.max(0, Math.min(rightA, rightB) - Math.max(leftA, leftB));
}

function getKdpPanelBounds(spec, dpi = 300) {
  const bleed = spec.bleed * dpi;
  const backLeft = bleed;
  const backRight = (spec.bleed + spec.trimWidth) * dpi;
  const spineLeft = backRight;
  const spineRight = (spec.bleed + spec.trimWidth + spec.spine) * dpi;
  const frontRight = (spec.bleed + spec.trimWidth + spec.spine + spec.trimWidth) * dpi;
  return {
    bleed,
    backLeft,
    backRight,
    spineLeft,
    spineRight,
    frontRight,
    spineWidth: Math.max(1, spineRight - spineLeft)
  };
}

function getKdpZoneHintFromLlmNotes(box) {
  if (box.source !== "llm_vision") {
    return "";
  }
  const notes = String(box.notes || "").toLowerCase();
  if (!notes) {
    return "";
  }
  if (/(^|[^a-z])(book\s+spine|spine|spine\s+title|spine\s+author|spine\s+publisher)([^a-z]|$)|书脊|书籍/.test(notes)) {
    return "spine";
  }
  if (/(^|[^a-z])(back\s+cover|rear\s+cover|back\s+panel)([^a-z]|$)|封底|封底文字/.test(notes)) {
    return "back";
  }
  if (/(^|[^a-z])(front\s+cover|front\s+panel|cover\s+title|front\s+title)([^a-z]|$)|封面|封面文字/.test(notes)) {
    return "front";
  }
  return "";
}

function getKdpZoneDecisionForBox(box, spec, dpi = 300) {
  const left = Number(box.x || 0);
  const right = Number(box.right ?? (left + Number(box.width || 0)));
  const width = Math.max(1, right - left, Number(box.width || 0));
  const height = Math.max(1, Number(box.height || 0));
  const centerX = left + (width / 2);
  const { backLeft, backRight, spineLeft, spineRight, frontRight, spineWidth } = getKdpPanelBounds(spec, dpi);
  const orientation = String(box.orientation || "").toLowerCase();
  const verticalish = orientation === "vertical" || orientation === "rotated" || height >= width * 1.25;
  const spineOverlap = getHorizontalOverlap(left, right, spineLeft, spineRight);
  const backOverlap = getHorizontalOverlap(left, right, backLeft, backRight);
  const frontOverlap = getHorizontalOverlap(left, right, spineRight, frontRight);
  const spineOverlapRatio = spineOverlap / width;
  const spineHalo = Math.max(Math.round(0.18 * dpi), Math.round(spineWidth * 0.35));
  const nearSpine = right >= spineLeft - spineHalo && left <= spineRight + spineHalo;
  const narrowEnoughForSpine = width <= Math.max(spineWidth * 2.6, 260);
  const leftEdgeNearSpine = left >= spineLeft - Math.max(spineHalo * 2, 140) && left <= spineRight + spineHalo;
  const shortLineNearSpine = height <= Math.max(0.42 * dpi, spineWidth * 0.9);
  const notesHint = getKdpZoneHintFromLlmNotes(box);

  if (notesHint) {
    return {
      zone: notesHint,
      reason: `LLM notes indicate ${notesHint}: ${String(box.notes || "").slice(0, 96)}`
    };
  }

  if (spineOverlapRatio >= 0.35 || (verticalish && spineOverlap >= 8)) {
    return {
      zone: "spine",
      reason: `spine overlap ${Math.round(spineOverlap)}px (${Math.round(spineOverlapRatio * 100)}%)`
    };
  }

  if (nearSpine && narrowEnoughForSpine) {
    return {
      zone: "spine",
      reason: `${verticalish ? "vertical" : "small"} text near spine edge (${Math.round(left)}-${Math.round(right)}px; spine ${Math.round(spineLeft)}-${Math.round(spineRight)}px)`
    };
  }

  if (nearSpine && leftEdgeNearSpine && shortLineNearSpine) {
    return {
      zone: "spine",
      reason: `wide LLM box anchored near spine left edge x=${Math.round(left)}px (spine ${Math.round(spineLeft)}-${Math.round(spineRight)}px)`
    };
  }

  const candidates = [
    ["back", backOverlap],
    ["spine", spineOverlap],
    ["front", frontOverlap]
  ].sort((a, b) => b[1] - a[1]);
  if (candidates[0][1] > 0) {
    return {
      zone: candidates[0][0],
      reason: `largest overlap ${Math.round(candidates[0][1])}px`
    };
  }

  return {
    zone: centerX < backLeft ? "bleed-left" : "bleed-right",
    reason: `outside trim by center x ${Math.round(centerX)}px`
  };
}

function getKdpZoneForBox(box, spec, dpi = 300) {
  return getKdpZoneDecisionForBox(box, spec, dpi).zone;
}

function getKdpDisplayBoxForRegion(box, decision, spec, dpi = 300) {
  const display = {
    x: Math.round(Number(box.x || 0)),
    y: Math.round(Number(box.y || 0)),
    width: Math.round(Number(box.width || 0)),
    height: Math.round(Number(box.height || 0))
  };
  display.right = display.x + display.width;
  display.bottom = display.y + display.height;

  if (decision?.zone !== "spine" || box.source !== "llm_vision") {
    return display;
  }

  const { spineLeft, spineRight, spineWidth } = getKdpPanelBounds(spec, dpi);
  const halo = Math.max(Math.round(0.2 * dpi), Math.round(spineWidth * 0.45));
  const maxDisplayWidth = Math.max(Math.round(spineWidth + (halo * 1.35)), Math.round(0.82 * dpi));
  const spillsFarOutsideSpine = display.x < spineLeft - halo || display.right > spineRight + halo || display.width > maxDisplayWidth;
  if (!spillsFarOutsideSpine) {
    return display;
  }

  const clampedWidth = Math.min(display.width, maxDisplayWidth);
  const anchorX = Math.min(Math.max(display.x, spineLeft - halo), spineRight + halo);
  const minX = Math.max(0, spineLeft - halo);
  const maxX = Math.max(minX, spineRight + halo - clampedWidth);
  const x = Math.min(Math.max(anchorX, minX), maxX);
  return {
    x: Math.round(x),
    y: display.y,
    width: Math.round(clampedWidth),
    height: display.height,
    right: Math.round(x + clampedWidth),
    bottom: display.bottom,
    adjusted: true,
    reason: "display clipped to spine vicinity"
  };
}

function getKdpZoneLabel(zone) {
  return {
    back: "封底",
    spine: "书脊",
    front: "封面",
    "bleed-left": "左侧出血区",
    "bleed-right": "右侧出血区",
    unclassified: "未分类"
  }[zone] || zone;
}

function normalizeOcrWord(word, index, spec, dpi = 300) {
  const bbox = word.bbox || {};
  const x0 = Number(bbox.x0 ?? word.x0 ?? 0);
  const y0 = Number(bbox.y0 ?? word.y0 ?? 0);
  const x1 = Number(bbox.x1 ?? word.x1 ?? x0);
  const y1 = Number(bbox.y1 ?? word.y1 ?? y0);
  const width = Math.max(0, x1 - x0);
  const height = Math.max(0, y1 - y0);
  const text = String(word.text || "").trim();
  const confidence = Number(word.confidence ?? word.conf ?? 0);
  const box = {
    id: `ocr-${index}`,
    text,
    confidence: Number(confidence.toFixed(1)),
    x: Math.round(x0),
    y: Math.round(y0),
    width: Math.round(width),
    height: Math.round(height),
    right: Math.round(x1),
    bottom: Math.round(y1)
  };
  const decision = getKdpZoneDecisionForBox(box, spec, dpi);
  const displayBox = getKdpDisplayBoxForRegion(box, decision, spec, dpi);
  return {
    ...box,
    zone: decision.zone,
    zoneReason: decision.reason,
    displayBox,
    inches: {
      x: roundForDisplay(box.x / dpi),
      y: roundForDisplay(box.y / dpi),
      width: roundForDisplay(box.width / dpi),
      height: roundForDisplay(box.height / dpi),
      right: roundForDisplay(box.right / dpi),
      bottom: roundForDisplay(box.bottom / dpi)
    }
  };
}

function roundForDisplay(value, digits = 3) {
  return Number(Number(value || 0).toFixed(digits));
}

function preprocessKdpOcrCanvas(sourceCanvas) {
  const target = document.createElement("canvas");
  target.width = sourceCanvas.width;
  target.height = sourceCanvas.height;
  const sourceContext = sourceCanvas.getContext("2d");
  const targetContext = target.getContext("2d");
  const image = sourceContext.getImageData(0, 0, sourceCanvas.width, sourceCanvas.height);
  const data = image.data;

  for (let index = 0; index < data.length; index += 4) {
    const r = data[index];
    const g = data[index + 1];
    const b = data[index + 2];
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    const bright = max > 168;
    const goldText = r > 145 && g > 105 && b < 105 && (r - b) > 45;
    const whiteText = r > 185 && g > 185 && b > 170 && (max - min) < 65;
    const keep = bright && (goldText || whiteText);
    const value = keep ? 255 : 0;
    data[index] = value;
    data[index + 1] = value;
    data[index + 2] = value;
    data[index + 3] = 255;
  }

  targetContext.putImageData(image, 0, 0);
  return target;
}

function isLikelyTextRegion(region) {
  const text = String(region.text || "").trim();
  if (!/[A-Za-z0-9]/.test(text)) {
    return false;
  }
  if (text.length <= 1 && region.width < 18 && region.height < 18) {
    return false;
  }
  if (region.confidence < 45) {
    return false;
  }
  const area = region.width * region.height;
  if (area < 70) {
    return false;
  }
  const ratio = region.width / Math.max(1, region.height);
  if (ratio > 18 || ratio < 0.035) {
    return false;
  }
  return true;
}

function renderKdpTextRegions(regions = state.kdpPdf.textRegions || []) {
  const layer = $("#kdp-pdf-text-layer");
  const canvas = $("#kdp-pdf-canvas");
  if (!layer || !canvas) {
    return;
  }
  if (!regions.length || !state.kdpPdf.ocrCanvasWidth || !state.kdpPdf.ocrCanvasHeight) {
    layer.innerHTML = "";
    return;
  }
  const scaleX = canvas.width / state.kdpPdf.ocrCanvasWidth;
  const scaleY = canvas.height / state.kdpPdf.ocrCanvasHeight;
  layer.innerHTML = regions.map((region) => {
    const box = region.displayBox || region;
    const displayNote = region.displayBox?.adjusted
      ? ` · display ${box.x},${box.y},${box.width}x${box.height}px`
      : "";
    return `
      <div class="kdp-text-box kdp-text-box-${escapeHtml(region.zone)}${region.displayBox?.adjusted ? " kdp-text-box-adjusted" : ""}"
        title="${escapeHtml(`${getKdpZoneLabel(region.zone)} · ${region.text} · raw ${region.x},${region.y},${region.width}x${region.height}px${displayNote}`)}"
        style="left:${box.x * scaleX}px;top:${box.y * scaleY}px;width:${box.width * scaleX}px;height:${box.height * scaleY}px"></div>
    `;
  }).join("");
}

function formatKdpLlmUsage(usage) {
  if (!usage || typeof usage !== "object") {
    return "tokens -";
  }
  const input = usage.input_tokens ?? usage.prompt_tokens ?? "-";
  const output = usage.output_tokens ?? usage.completion_tokens ?? "-";
  const total = usage.total_tokens ?? ((Number.isFinite(Number(input)) && Number.isFinite(Number(output))) ? Number(input) + Number(output) : "-");
  const cached = usage.input_tokens_details?.cached_tokens;
  const cachedPart = Number.isFinite(Number(cached)) ? ` · cached ${cached}` : "";
  return `tokens input ${input} · output ${output} · total ${total}${cachedPart}`;
}

function formatKdpLlmSavedPath(saved, key) {
  if (!saved) return "-";
  const explicit = key === "json"
    ? (saved.resultRelativePath || saved.resultPathRelative)
    : (saved.imageRelativePath || saved.imagePathRelative);
  if (explicit) return explicit;
  const fileName = key === "json" ? saved.resultFileName : saved.imageFileName;
  return fileName ? `07_cover/kdp_acceptance/llm_text_regions/${fileName}` : "-";
}

function setKdpSourceMetadata(source = null) {
  const fileName = source?.fileName || source?.relativePath || source?.originalFileName || "";
  state.kdpPdf.source = source ? {
    type: getKdpFileTypeLabel(fileName, source.type),
    origin: source.origin || "",
    directory: source.directory || "",
    fileName: source.fileName || "",
    relativePath: source.relativePath || "",
    originalFileName: source.originalFileName || ""
  } : null;
}

function getKdpFileTypeLabel(fileName = "", fallback = "") {
  const normalizedName = String(fileName || "").toLowerCase();
  if (/\.pdf(?:$|[?#])/.test(normalizedName)) return "PDF";
  if (/\.png(?:$|[?#])/.test(normalizedName)) return "PNG";
  const normalizedFallback = String(fallback || "").toUpperCase();
  if (normalizedFallback === "PDF" || normalizedFallback === "PNG") return normalizedFallback;
  return "";
}

function getKdpAcceptanceSourceMetadata(fileName, type = "") {
  const normalizedFileName = String(fileName || "");
  const normalizedPath = normalizedFileName.replaceAll("\\", "/");
  const slashIndex = normalizedPath.lastIndexOf("/");
  const directory = slashIndex >= 0
    ? `07_cover/kdp_acceptance/${normalizedPath.slice(0, slashIndex)}`
    : "07_cover/kdp_acceptance";
  const baseName = slashIndex >= 0 ? normalizedPath.slice(slashIndex + 1) : normalizedPath;
  const normalizedType = getKdpFileTypeLabel(normalizedPath || normalizedFileName, type) || "PDF";
  return {
    type: normalizedType,
    origin: "KDP acceptance directory",
    directory,
    fileName: baseName,
    relativePath: normalizedPath ? `07_cover/kdp_acceptance/${normalizedPath}` : ""
  };
}

function getKdpLocalUploadSourceMetadata(file) {
  if (!file) return null;
  const type = getKdpFileTypeLabel(file.name, file.type === "image/png" ? "PNG" : "") || "PDF";
  return {
    type,
    origin: "local upload",
    directory: "local upload",
    fileName: file.name,
    relativePath: "",
    originalFileName: file.name
  };
}

function getKdpFixReportHeaderLines(generatedAt = formatKdpReportTimestamp()) {
  const source = state.kdpPdf.source || {};
  return [
    `# KDP 封面修改意见报告（生成时间：${generatedAt}）`,
    "",
    `- BookName：${getBookName() || "-"}`,
    `- 针对文件类型：${source.type || (state.kdpPdf.mode === "image" ? "PNG" : "PDF")}`,
    `- 源文件目录：${source.directory || "-"}`,
    `- 源文件名：${source.fileName || "-"}`,
    `- 源文件路径：${source.relativePath || "-"}`,
    ...(source.originalFileName && source.originalFileName !== source.fileName ? [`- 原始上传文件名：${source.originalFileName}`] : []),
    ""
  ];
}

function renderKdpCurrentFileMeta({
  status = "尚未选择 PDF/PNG。",
  type = "",
  fileName = "",
  path = "",
  detail = ""
} = {}) {
  const meta = $("#kdp-pdf-meta");
  if (!meta) return;
  if (!fileName && !path && !detail) {
    meta.classList.remove("has-file");
    meta.textContent = status;
    return;
  }
  meta.classList.add("has-file");
  meta.innerHTML = `
    <strong>当前检查文件</strong>
    <span>${escapeHtml(status)}</span>
    ${type ? `<span>类型：${escapeHtml(type)}</span>` : ""}
    ${fileName ? `<span>文件名：${escapeHtml(fileName)}</span>` : ""}
    ${path ? `<span>路径：${escapeHtml(path)}</span>` : ""}
    ${detail ? `<span>${escapeHtml(detail)}</span>` : ""}
  `;
}

function renderKdpCurrentSourceMeta(status = "已加载") {
  const source = state.kdpPdf.source || null;
  if (!source) {
    renderKdpCurrentFileMeta();
    return;
  }
  const fileName = source.fileName || source.relativePath || source.originalFileName || "";
  const type = getKdpFileTypeLabel(fileName, source.type);
  renderKdpCurrentFileMeta({
    status,
    type,
    fileName: source.fileName || source.originalFileName || "",
    path: source.relativePath || source.directory || source.origin || "",
    detail: source.originalFileName && source.originalFileName !== source.fileName
      ? `原始上传文件名：${source.originalFileName}`
      : ""
  });
}

function getKdpSourceAcceptanceRelativePath(source = {}) {
  if (source.acceptanceRelativePath) return source.acceptanceRelativePath;
  const relativePath = String(source.relativePath || "").replaceAll("\\", "/");
  return relativePath.replace(/^07_cover\/kdp_acceptance\//i, "");
}

function renderKdpTextRegionReport(regions = state.kdpPdf.textRegions || []) {
  const panel = $("#kdp-text-region-report");
  if (!panel) {
    return;
  }
  if (!regions.length) {
    panel.innerHTML = '<div class="cover-gallery-empty">点击“识别文字区域”后，这里会按封底、书脊、封面列出 OCR 坐标。</div>';
    return;
  }
  const groups = ["back", "spine", "front", "bleed-left", "bleed-right"]
    .map((zone) => [zone, regions.filter((item) => item.zone === zone)])
    .filter(([, items]) => items.length);
  const debug = state.kdpPdf.visionDebug;
  const scaleX = Number(debug?.coordinateScale?.x || 1);
  const scaleY = Number(debug?.coordinateScale?.y || 1);
  const taskId = debug?.saved?.resultFileName
    ? debug.saved.resultFileName.replace(/\.json$/i, "")
    : (debug?.responseId || "-");
  const debugHtml = debug ? `
    <div class="kdp-vision-debug">
      Task: ${escapeHtml(taskId)}${debug.responseId ? ` · Response: ${escapeHtml(debug.responseId)}` : ""}
      ${debug.createdAt ? ` · Time: ${escapeHtml(debug.createdAt)}` : ""}
      <br>${escapeHtml(formatKdpLlmUsage(debug.usage))}
      <br>
      LLM coordinate calibration: model ${escapeHtml(debug.modelImage?.width || "-")} x ${escapeHtml(debug.modelImage?.height || "-")}
      -> PNG ${escapeHtml(debug.image?.width || "-")} x ${escapeHtml(debug.image?.height || "-")}
      · scale ${escapeHtml(scaleX.toFixed(4))} / ${escapeHtml(scaleY.toFixed(4))}
      ${debug.saved?.resultFileName ? `<br>Saved: ${escapeHtml(formatKdpLlmSavedPath(debug.saved, "json"))} · ${escapeHtml(formatKdpLlmSavedPath(debug.saved, "png"))}` : ""}
    </div>
  ` : "";

  panel.innerHTML = debugHtml + groups.map(([zone, items]) => `
    <details class="kdp-text-region-group" open>
      <summary>${escapeHtml(getKdpZoneLabel(zone))} · ${items.length} 个文字框</summary>
      <div class="kdp-text-table-wrap">
        <table class="kdp-text-table">
          <thead>
            <tr>
              <th>文字</th>
              <th>置信</th>
              <th>x px</th>
              <th>y px</th>
              <th>w px</th>
              <th>h px</th>
              <th>right px</th>
              <th>bottom px</th>
              <th>判定依据</th>
              <th>notes</th>
              <th>x in</th>
              <th>y in</th>
              <th>w in</th>
              <th>h in</th>
            </tr>
          </thead>
          <tbody>
            ${items.map((item) => `
              <tr>
                <th>${escapeHtml(item.text || "(blank)")}</th>
                <td>${escapeHtml(item.confidence)}</td>
                <td>${escapeHtml(item.x)}</td>
                <td>${escapeHtml(item.y)}</td>
                <td>${escapeHtml(item.width)}</td>
                <td>${escapeHtml(item.height)}</td>
                <td>${escapeHtml(item.right)}</td>
                <td>${escapeHtml(item.bottom)}</td>
                <td>${escapeHtml(item.zoneReason || "-")}</td>
                <td>${escapeHtml(item.notes || "-")}</td>
                <td>${escapeHtml(item.inches.x)}</td>
                <td>${escapeHtml(item.inches.y)}</td>
                <td>${escapeHtml(item.inches.width)}</td>
                <td>${escapeHtml(item.inches.height)}</td>
              </tr>
            `).join("")}
          </tbody>
        </table>
      </div>
    </details>
  `).join("");
}

function getKdpRectPx(rect) {
  if (!rect) return null;
  const x = Number(rect.x || 0);
  const y = Number(rect.y || 0);
  const width = Number(rect.width || 0);
  const height = Number(rect.height || 0);
  return {
    x,
    y,
    width,
    height,
    right: Number(rect.right ?? (x + width)),
    bottom: Number(rect.bottom ?? (y + height))
  };
}

function getKdpSpecRectsPx(spec, dpi = 300) {
  const bleed = Number(spec.bleed || 0.125);
  const trimWidth = Number(spec.trimWidth || 6);
  const trimHeight = Number(spec.trimHeight || 9);
  const spine = Number(spec.spine || 0);
  const safeInset = Number(spec.frontBackSafeInsetFromTrim || 0.125);
  const spineSafeInset = Number(spec.spineSafeInset || 0.0625);
  const barcodeWidth = Number(spec.barcodeWidth || 2);
  const barcodeHeight = Number(spec.barcodeHeight || 1.2);
  const barcodeInset = Number(spec.barcodeInset || 0.25);
  const px = (value) => Math.round(Number(value || 0) * dpi);
  const rect = (x, y, width, height) => ({
    x: px(x),
    y: px(y),
    width: px(width),
    height: px(height),
    right: px(x + width),
    bottom: px(y + height),
    centerX: px(x + (width / 2))
  });
  return {
    fullCover: rect(0, 0, (trimWidth * 2) + spine + (bleed * 2), trimHeight + (bleed * 2)),
    whiteTrim: rect(bleed, bleed, (trimWidth * 2) + spine, trimHeight),
    backTrim: rect(bleed, bleed, trimWidth, trimHeight),
    spineTrim: rect(bleed + trimWidth, bleed, spine, trimHeight),
    frontTrim: rect(bleed + trimWidth + spine, bleed, trimWidth, trimHeight),
    backSafe: rect(bleed + safeInset, bleed + safeInset, trimWidth - (safeInset * 2), trimHeight - (safeInset * 2)),
    spineSafe: rect(bleed + trimWidth + spineSafeInset, bleed + safeInset, Math.max(0, spine - (spineSafeInset * 2)), trimHeight - (safeInset * 2)),
    frontSafe: rect(bleed + trimWidth + spine + safeInset, bleed + safeInset, trimWidth - (safeInset * 2), trimHeight - (safeInset * 2)),
    barcode: rect(bleed + trimWidth - barcodeInset - barcodeWidth, bleed + trimHeight - barcodeInset - barcodeHeight, barcodeWidth, barcodeHeight)
  };
}

function getKdpPdfActualSizePx(dpi = 300) {
  if (state.kdpPdf.mode === "image" && state.kdpPdf.imageSize) {
    return {
      width: Math.round(state.kdpPdf.imageSize.width),
      height: Math.round(state.kdpPdf.imageSize.height)
    };
  }
  if (!state.kdpPdf.page) {
    return null;
  }
  const viewport = state.kdpPdf.page.getViewport({ scale: dpi / 72 });
  return {
    width: Math.ceil(viewport.width),
    height: Math.ceil(viewport.height)
  };
}

function getKdpPngActualSizePx() {
  const debugImage = state.kdpPdf.visionDebug?.image || null;
  const width = Math.round(Number(state.kdpPdf.ocrCanvasWidth || debugImage?.width || 0));
  const height = Math.round(Number(state.kdpPdf.ocrCanvasHeight || debugImage?.height || 0));
  return width > 0 && height > 0 ? { width, height } : null;
}

function getKdpScaledCenterAxes(rects, actualSize) {
  const baseWidth = Math.max(1, Number(rects.fullCover?.width || 0));
  const scaleX = actualSize?.width ? actualSize.width / baseWidth : 1;
  const axis = (rect) => Math.round(Number(rect.centerX || 0) * scaleX);
  return {
    width: actualSize?.width || baseWidth,
    height: actualSize?.height || rects.fullCover.height,
    scaleX,
    back: axis(rects.backTrim),
    spine: axis(rects.spineTrim),
    front: axis(rects.frontTrim),
    full: axis(rects.fullCover)
  };
}

function formatKdpAxisDelta(pdfAxis, pngAxis) {
  if (!pngAxis) {
    return "PNG 未生成/未恢复，暂不能比较。";
  }
  const delta = pngAxis - pdfAxis;
  if (delta === 0) return "一致";
  if (Math.abs(delta) <= 1) return `基本一致，差 ${delta}px（通常是 PDF 渲染取整差）`;
  return `不一致，差 ${delta}px`;
}

function getKdpOverlapArea(a, b) {
  const left = Math.max(a.x, b.x);
  const top = Math.max(a.y, b.y);
  const right = Math.min(a.right, b.right);
  const bottom = Math.min(a.bottom, b.bottom);
  return Math.max(0, right - left) * Math.max(0, bottom - top);
}

function describeKdpRegionIssues(region, safeRect, options = {}) {
  const box = getKdpRectPx(region.displayBox || region);
  if (!box || !safeRect) {
    return ["坐标不足，需要重新识别文字区域。"];
  }
  const issues = [];
  if (box.x < safeRect.x) issues.push(`左侧越过安全线 ${safeRect.x - box.x}px`);
  if (box.right > safeRect.right) issues.push(`右侧越过安全线 ${box.right - safeRect.right}px`);
  if (box.y < safeRect.y) issues.push(`上侧越过安全线 ${safeRect.y - box.y}px`);
  if (box.bottom > safeRect.bottom) issues.push(`下侧越过安全线 ${box.bottom - safeRect.bottom}px`);
  if (options.barcodeRect) {
    const overlap = getKdpOverlapArea(box, options.barcodeRect);
    if (overlap > 0) issues.push(`压到 KDP 条码预留区，重叠面积约 ${Math.round(overlap)}px²`);
  }
  return issues.length ? issues : ["未发现明显安全线/条码区冲突。"];
}

function buildKdpPreciseMoveAdvice(region, safeRect, options = {}) {
  const box = getKdpRectPx(region.displayBox || region);
  if (!box || !safeRect) {
    return "坐标不足，无法计算精确移动量。";
  }
  const boxCenterX = Math.round(box.x + (box.width / 2));
  const safeCenterX = Math.round(safeRect.x + (safeRect.width / 2));
  const deltaX = safeCenterX - boxCenterX;
  const horizontalText = deltaX > 0 ? `向右移动 ${deltaX}px` : deltaX < 0 ? `向左移动 ${Math.abs(deltaX)}px` : "水平居中无需移动";
  const widthAdvice = box.width > safeRect.width
    ? `当前宽度 ${box.width}px 大于安全宽度 ${safeRect.width}px，需先缩小至少 ${box.width - safeRect.width}px，目标宽度 <= ${safeRect.width}px`
    : `当前宽度 ${box.width}px，小于/等于安全宽度 ${safeRect.width}px`;
  const verticalMoves = [];
  if (box.y < safeRect.y) verticalMoves.push(`向下移动至少 ${safeRect.y - box.y}px`);
  if (box.bottom > safeRect.bottom) verticalMoves.push(`向上移动至少 ${box.bottom - safeRect.bottom}px`);
  const barcodeAdvice = options.barcodeRect && getKdpOverlapArea(box, options.barcodeRect) > 0
    ? "同时需要离开条码预留区"
    : "";
  return [
    `区域安全框：x=${safeRect.x}, w=${safeRect.width}, center=${safeCenterX}px`,
    `文字框：x=${box.x}, w=${box.width}, center=${boxCenterX}px`,
    widthAdvice,
    `水平建议：${horizontalText}`,
    verticalMoves.length ? `垂直建议：${verticalMoves.join("；")}` : "垂直建议：无需移动",
    barcodeAdvice
  ].filter(Boolean).join("；");
}

function buildKdpFixReport() {
  const regions = state.kdpPdf.textRegions || [];
  const spec = state.kdpPdf.spec || getCurrentKdpGuideSpec();
  const dpi = 300;
  const rects = getKdpSpecRectsPx(spec, dpi);
  const isImageMode = state.kdpPdf.mode === "image";
  const primaryLabel = isImageMode ? "PNG" : "PDF";
  const primarySize = isImageMode ? getKdpPngActualSizePx() : getKdpPdfActualSizePx(dpi);
  const primaryAxes = getKdpScaledCenterAxes(rects, primarySize);
  const pngSize = getKdpPngActualSizePx();
  const pngAxes = !isImageMode && pngSize ? getKdpScaledCenterAxes(rects, pngSize) : null;
  const groups = {
    back: regions.filter((item) => item.zone === "back"),
    spine: regions.filter((item) => item.zone === "spine"),
    front: regions.filter((item) => item.zone === "front")
  };
  const lines = [
    ...getKdpFixReportHeaderLines(),
    "生成方式：程序根据当前文字区域坐标、红线安全区、白线裁切/书脊线、KDP 条码区自动生成；未调用 LLM。",
    `坐标基准：PDF/PNG 左上角，${dpi} DPI 像素坐标。`,
    "区域中轴线（x 坐标）：",
    `- ${primaryLabel} 文件实际尺寸：${primaryAxes.width} x ${primaryAxes.height}px；x 缩放=${primaryAxes.scaleX.toFixed(6)}`,
    `  - 封底中轴线：x=${primaryAxes.back}px`,
    `  - 书脊中轴线：x=${primaryAxes.spine}px`,
    `  - 封面中轴线：x=${primaryAxes.front}px`,
    `  - 整张 ${primaryLabel} 中轴线：x=${primaryAxes.full}px`,
    ...(!isImageMode ? [
      pngAxes
        ? `- PNG 文件实际尺寸：${pngAxes.width} x ${pngAxes.height}px；x 缩放=${pngAxes.scaleX.toFixed(6)}`
        : "- PNG 文件实际尺寸：未生成/未恢复，暂不能计算。",
      ...(pngAxes ? [
        `  - 封底中轴线：x=${pngAxes.back}px；与 PDF 比较：${formatKdpAxisDelta(primaryAxes.back, pngAxes.back)}`,
        `  - 书脊中轴线：x=${pngAxes.spine}px；与 PDF 比较：${formatKdpAxisDelta(primaryAxes.spine, pngAxes.spine)}`,
        `  - 封面中轴线：x=${pngAxes.front}px；与 PDF 比较：${formatKdpAxisDelta(primaryAxes.front, pngAxes.front)}`,
        `  - 整张 PNG 中轴线：x=${pngAxes.full}px；与 PDF 比较：${formatKdpAxisDelta(primaryAxes.full, pngAxes.full)}`
      ] : [])
    ] : []),
    "- 说明：后续自动修图如果改变 PNG 宽度或裁切比例，上述 PNG 中轴线会随之变化；程序会用这一组数判断修图前后是否偏移。",
    ""
  ];
  [
    ["back", "一、封底", rects.backSafe, rects.backTrim, { barcodeRect: rects.barcode }],
    ["spine", "二、书脊", rects.spineSafe, rects.spineTrim, {}],
    ["front", "三、封面", rects.frontSafe, rects.frontTrim, {}]
  ].forEach(([zone, heading, safeRect, trimRect, options]) => {
    const items = groups[zone] || [];
    lines.push(heading, "");
    lines.push(`- 本区域裁切区中轴线：x=${trimRect.centerX}px；红线安全区中轴线：x=${safeRect.centerX}px。`);
    if (!items.length) {
      lines.push("- 未识别到文字区域。");
      lines.push("- 修改建议：无需针对文字位置做自动修图任务，除非肉眼发现遗漏。", "");
      return;
    }
    items.forEach((item, index) => {
      const box = getKdpRectPx(item.displayBox || item);
      const rawBox = getKdpRectPx(item);
      const issues = describeKdpRegionIssues(item, safeRect, options);
      const hasIssue = issues.some((issue) => !issue.includes("未发现"));
      lines.push(`${index + 1}. 文字：${item.text || "(blank)"}`);
      lines.push(`   - 原始坐标：x=${rawBox.x}, y=${rawBox.y}, w=${rawBox.width}, h=${rawBox.height}, right=${rawBox.right}, bottom=${rawBox.bottom}`);
      if (item.displayBox?.adjusted) {
        lines.push(`   - 显示修正坐标：x=${box.x}, y=${box.y}, w=${box.width}, h=${box.height}`);
      }
      lines.push(`   - 程序判定：${item.zoneReason || "按区域坐标归类"}`);
      lines.push(`   - 检查结果：${issues.join("；")}`);
      lines.push(`   - 修改建议：${hasIssue ? buildKdpPreciseMoveAdvice(item, safeRect, options) : "暂不需要调整位置。"}`);
    });
    lines.push("");
  });
  return lines.join("\n");
}

function getKdpFixReportPlaceholder() {
  return "点击“生成修改意见报告”后，这里会按封底、书脊、封面输出程序生成的修改意见。";
}

function getKdpFixCommandPromptPlaceholder() {
  return "点击“生成修改命令提示词”后，这里会输出给自动修图 LLM/图像模型使用的任务提示词。";
}

function getKdpImageMagickInstructionPlaceholder() {
  return "点击“生成ImageMagick指令集”后，这里会输出可编辑的书脊修图 JSON 指令。";
}

function renderKdpSavedFixReport(acceptance) {
  const reportField = $("#kdp-fix-report");
  const promptField = $("#kdp-fix-command-prompt");
  const imageMagickField = $("#kdp-imagemagick-instructions");
  if (!reportField) return;
  const savedText = acceptance?.fixReport?.latest?.reportText || "";
  reportField.value = savedText || getKdpFixReportPlaceholder();
  if (promptField) promptField.value = getKdpFixCommandPromptPlaceholder();
  if (imageMagickField && !imageMagickField.value) {
    imageMagickField.value = getKdpImageMagickInstructionPlaceholder();
  }
}

function getKdpFixCommandTasks(rects) {
  const zoneSpecs = [
    { key: "back", label: "BACK COVER", safeRect: rects.backSafe, trimRect: rects.backTrim, options: { barcodeRect: rects.barcode } },
    { key: "spine", label: "SPINE", safeRect: rects.spineSafe, trimRect: rects.spineTrim, options: {} },
    { key: "front", label: "FRONT COVER", safeRect: rects.frontSafe, trimRect: rects.frontTrim, options: {} }
  ];
  const tasks = [];
  zoneSpecs.forEach((zoneSpec) => {
    (state.kdpPdf.textRegions || [])
      .filter((item) => item.zone === zoneSpec.key)
      .forEach((item) => {
        const box = getKdpRectPx(item.displayBox || item);
        const rawBox = getKdpRectPx(item);
        if (!box || !zoneSpec.safeRect) return;
        const issues = [];
        if (box.x < zoneSpec.safeRect.x) issues.push(`left overflow ${zoneSpec.safeRect.x - box.x}px`);
        if (box.right > zoneSpec.safeRect.right) issues.push(`right overflow ${box.right - zoneSpec.safeRect.right}px`);
        if (box.y < zoneSpec.safeRect.y) issues.push(`top overflow ${zoneSpec.safeRect.y - box.y}px`);
        if (box.bottom > zoneSpec.safeRect.bottom) issues.push(`bottom overflow ${box.bottom - zoneSpec.safeRect.bottom}px`);
        const barcodeOverlap = zoneSpec.options.barcodeRect ? getKdpOverlapArea(box, zoneSpec.options.barcodeRect) : 0;
        if (barcodeOverlap > 0) issues.push(`barcode overlap about ${Math.round(barcodeOverlap)} px^2`);
        if (!issues.length) return;
        const boxCenterX = Math.round(box.x + (box.width / 2));
        const safeCenterX = Math.round(zoneSpec.safeRect.x + (zoneSpec.safeRect.width / 2));
        const deltaX = safeCenterX - boxCenterX;
        const moveX = deltaX > 0 ? `move right ${deltaX}px` : deltaX < 0 ? `move left ${Math.abs(deltaX)}px` : "keep current x center";
        const verticalMoves = [];
        if (box.y < zoneSpec.safeRect.y) verticalMoves.push(`move down at least ${zoneSpec.safeRect.y - box.y}px`);
        if (box.bottom > zoneSpec.safeRect.bottom) verticalMoves.push(`move up at least ${box.bottom - zoneSpec.safeRect.bottom}px`);
        const scaleText = box.width > zoneSpec.safeRect.width
          ? `reduce width by at least ${box.width - zoneSpec.safeRect.width}px; target width <= ${zoneSpec.safeRect.width}px`
          : `keep width <= ${zoneSpec.safeRect.width}px`;
        tasks.push({
          zone: zoneSpec.label,
          text: item.text || "(unreadable text)",
          box,
          rawBox,
          safeRect: zoneSpec.safeRect,
          trimRect: zoneSpec.trimRect,
          issues,
          actions: [scaleText, moveX, ...verticalMoves],
          centerAxisX: zoneSpec.trimRect.centerX,
          safeCenterX
        });
      });
  });
  return tasks;
}

function buildKdpFixCommandPrompt() {
  const spec = state.kdpPdf.spec || getCurrentKdpGuideSpec();
  const dpi = 300;
  const rects = getKdpSpecRectsPx(spec, dpi);
  const pdfAxes = getKdpScaledCenterAxes(rects, getKdpPdfActualSizePx(dpi));
  const pngSize = getKdpPngActualSizePx();
  const pngAxes = pngSize ? getKdpScaledCenterAxes(rects, pngSize) : null;
  const tasks = getKdpFixCommandTasks(rects);
  if (!tasks.length) {
    return [
      "Edit the attached KDP cover PNG.",
      "",
      `Canvas: preserve the exact input size (${pngAxes ? `${pngAxes.width} x ${pngAxes.height}px` : `${pdfAxes.width} x ${pdfAxes.height}px @ ${dpi} DPI`}).`,
      "No text blocks currently require movement based on the detected safe-area and barcode checks.",
      "Do not change the image."
    ].join("\n");
  }
  const touchedZones = [...new Set(tasks.map((task) => task.zone))];
  const relevantAxes = touchedZones.map((zone) => {
    if (zone === "BACK COVER") return `back cover center x=${pngAxes?.back ?? pdfAxes.back}`;
    if (zone === "SPINE") return `spine center x=${pngAxes?.spine ?? pdfAxes.spine}`;
    return `front cover center x=${pngAxes?.front ?? pdfAxes.front}`;
  }).join("; ");
  const taskLines = tasks.map((task, index) => [
    `${index + 1}. ${task.zone}`,
    `   Text: "${task.text}"`,
    `   Current box: x=${task.rawBox.x}, y=${task.rawBox.y}, w=${task.rawBox.width}, h=${task.rawBox.height}, right=${task.rawBox.right}, bottom=${task.rawBox.bottom}`,
    `   Safe box: x=${task.safeRect.x}, y=${task.safeRect.y}, w=${task.safeRect.width}, h=${task.safeRect.height}, right=${task.safeRect.right}, bottom=${task.safeRect.bottom}`,
    `   Center reference: region center x=${task.centerAxisX}, safe center x=${task.safeCenterX}`,
    `   Problem: ${task.issues.join("; ")}`,
    `   Required edit: ${task.actions.join("; ")}.`
  ].join("\n")).join("\n\n");
  return [
    "Edit the attached KDP cover PNG.",
    "",
    "Goal: fix only the listed text blocks so they sit fully inside their safe boxes.",
    "",
    `Canvas: preserve the exact input size (${pngAxes ? `${pngAxes.width} x ${pngAxes.height}px` : `${pdfAxes.width} x ${pdfAxes.height}px @ ${dpi} DPI`}). Do not crop, rotate, add borders, or shift the background.`,
    `Relevant center axes: ${relevantAxes}.`,
    "Do not change any text content. Do not move artwork, background, barcode area, trim lines, bleed lines, or guide lines.",
    "",
    "Required edits:",
    taskLines,
    "",
    "Return only the corrected image."
  ].join("\n");
}

function generateKdpFixCommandPrompt() {
  const promptField = $("#kdp-fix-command-prompt");
  const reportField = $("#kdp-fix-report");
  if (!promptField) return;
  if (!state.kdpPdf.textRegions?.length) {
    promptField.value = "尚未识别文字区域。请先点击“LLM识别文字区域”，再生成修改意见报告和修改命令提示词。";
    return;
  }
  const placeholder = getKdpFixReportPlaceholder();
  let reportText = reportField?.value || "";
  if (!reportText || reportText === placeholder || reportText.includes("点击“生成修改意见报告”")) {
    reportText = buildKdpFixReport();
    if (reportField) reportField.value = reportText;
  }
  promptField.value = buildKdpFixCommandPrompt();
  setStatusBadge("已生成", "success");
  setLog([
    "KDP 修改命令提示词已生成。",
    "来源：当前文字区域坐标 + 修改意见报告 + PDF/PNG 中轴线。",
    "说明：本步骤只生成提示词，暂不调用 LLM，也不修改图片。"
  ].join("\n"));
}

function toKdpInstructionRect(rect) {
  return {
    x: Math.round(rect.x),
    y: Math.round(rect.y),
    w: Math.round(rect.width),
    h: Math.round(rect.height)
  };
}

function buildKdpImageMagickInstructionSet() {
  const spec = state.kdpPdf.spec || getCurrentKdpGuideSpec();
  const dpi = 300;
  const rects = getKdpSpecRectsPx(spec, dpi);
  const pngSize = getKdpPngActualSizePx();
  const actualSize = pngSize || getKdpPdfActualSizePx(dpi);
  const spineTasks = getKdpFixCommandTasks(rects).filter((task) => task.zone === "SPINE");
  const operations = spineTasks.map((task, index) => {
    const box = task.box;
    const boxCenterX = Math.round(box.x + (box.width / 2));
    const safeCenterX = Math.round(task.safeRect.x + (task.safeRect.width / 2));
    const dx = safeCenterX - boxCenterX;
    let dy = 0;
    if (box.y < task.safeRect.y) {
      dy = task.safeRect.y - box.y;
    } else if (box.bottom > task.safeRect.bottom) {
      dy = task.safeRect.bottom - box.bottom;
    }
    return {
      id: `spine-${index + 1}`,
      type: "move_region",
      zone: "spine",
      text: task.text,
      reason: task.issues.join("; "),
      sourceRect: toKdpInstructionRect(box),
      targetRect: {
        x: Math.round(box.x + dx),
        y: Math.round(box.y + dy),
        w: Math.round(box.width),
        h: Math.round(box.height)
      },
      dx,
      dy,
      sourceCenterX: boxCenterX,
      targetCenterX: safeCenterX,
      spineSafeCenterX: safeCenterX,
      clearSource: true,
      fillSourceWith: "#07121b",
      feather: 0
    };
  });
  return {
    version: 1,
    scope: "spine",
    engine: "ImageMagick",
    canvas: {
      width: actualSize.width,
      height: actualSize.height,
      preserveSourceSize: true,
      outputDpi: 300
    },
    guides: {
      spineTrim: toKdpInstructionRect(rects.spineTrim),
      spineSafe: toKdpInstructionRect(rects.spineSafe),
      spineTrimCenterX: Math.round(rects.spineTrim.centerX),
      spineSafeCenterX: Math.round(rects.spineSafe.centerX)
    },
    notes: [
      "Edit only the spine text regions listed in operations.",
      "Review sourceRect, targetRect, dx, dy, and fillSourceWith before running.",
      "clearSource fills the old rectangle with fillSourceWith; adjust this color manually if the local background is different."
    ],
    operations
  };
}

function generateKdpImageMagickInstructions() {
  const field = $("#kdp-imagemagick-instructions");
  const status = $("#kdp-img-black-status");
  if (!field) return;
  if (!state.kdpPdf.textRegions?.length) {
    field.value = "尚未识别文字区域。请先点击“LLM识别文字区域”，再生成 ImageMagick 指令集。";
    if (status) status.textContent = "尚未识别文字区域。";
    return;
  }
  const instructionSet = buildKdpImageMagickInstructionSet();
  field.value = JSON.stringify(instructionSet, null, 2);
  if (status) status.textContent = `已生成 ${instructionSet.operations.length} 条 ImageMagick 操作。`;
  setStatusBadge("已生成", "success");
  setLog([
    "KDP ImageMagick 书脊指令集已生成。",
    `Operations: ${instructionSet.operations.length}`,
    "说明：可在文本框中人工修改 JSON；点击 ImageMagick修图 时会执行当前文本框内容。"
  ].join("\n"));
}

function renderKdpFixWorkbench(workbench = state.kdpFixWorkbench || {}) {
  state.kdpFixWorkbench = workbench || {};
  const item = getSelectedWorkspaceItem();
  const status = $("#kdp-edit-workbench-status");
  const sourcePreview = $("#kdp-fix-source-preview");
  const outputPreview = $("#kdp-fix-output-preview");
  const sourceMeta = $("#kdp-fix-source-meta");
  const outputMeta = $("#kdp-fix-output-meta");
  const promptField = $("#kdp-fix-command-prompt");
  const imageMagickField = $("#kdp-imagemagick-instructions");
  if (promptField && workbench.prompt && promptField.value === getKdpFixCommandPromptPlaceholder()) {
    promptField.value = workbench.prompt;
  }
  if (imageMagickField && workbench.imageMagickInstructions && imageMagickField.value === getKdpImageMagickInstructionPlaceholder()) {
    imageMagickField.value = workbench.imageMagickInstructions;
  }
  if (status) {
    status.textContent = workbench.outputFileName
      ? `已生成：${workbench.outputFileName}`
      : workbench.sourceFileName
        ? `已准备：${workbench.sourceFileName}`
        : "尚未准备修改文件。";
  }
  if (sourcePreview) {
    sourcePreview.innerHTML = item?.bookName && workbench.sourceFileName
      ? `<img src="/api/kdp-fix-image?bookName=${encodeURIComponent(item.bookName)}&kind=source&fileName=${encodeURIComponent(workbench.sourceFileName)}&t=${Date.now()}" alt="">`
      : "<span>准备后显示源文件</span>";
  }
  if (outputPreview) {
    outputPreview.innerHTML = item?.bookName && workbench.outputFileName
      ? `<img src="/api/kdp-fix-image?bookName=${encodeURIComponent(item.bookName)}&kind=output&fileName=${encodeURIComponent(workbench.outputFileName)}&t=${Date.now()}" alt="">`
      : "<span>执行后显示结果</span>";
  }
  if (sourceMeta) {
    sourceMeta.textContent = workbench.sourceFileName
      ? `${workbench.sourceFileName} · ${workbench.sourceImage?.width || "-"} x ${workbench.sourceImage?.height || "-"} px`
      : "未准备。";
  }
  if (outputMeta) {
    const run = workbench.latestRun;
    outputMeta.textContent = workbench.outputFileName
      ? `${workbench.outputFileName}${run?.durationSeconds ? ` · ${run.durationSeconds}s` : ""}`
      : "未生成。";
  }
  renderKdpImgBlackWorkbenchState(workbench);
}

function loadKdpImgBlackSourceToWorkarea() {
  const bookName = requireBookName();
  const workbench = state.kdpFixWorkbench || {};
  const target = $("#kdp-img-black-workarea-1");
  const fileLabel = $("#kdp-img-black-workarea-1-file");
  const status = $("#kdp-img-black-status");
  if (!target) return;
  if (!workbench.sourceFileName) {
    target.innerHTML = '<div class="cover-gallery-empty">尚未准备待修改 PNG。请先在 KDP 修图工作台点击“准备修改文件”。</div>';
    if (fileLabel) fileLabel.textContent = "文件名：未加载";
    if (status) status.textContent = "尚未准备待修改 PNG。";
    return;
  }
  const src = `/api/kdp-fix-image?bookName=${encodeURIComponent(bookName)}&kind=source&fileName=${encodeURIComponent(workbench.sourceFileName)}&t=${Date.now()}`;
  if (fileLabel) fileLabel.textContent = `文件名：${workbench.sourceFileName}`;
  target.innerHTML = `<div class="kdp-img-black-image-wrap"><img id="kdp-img-black-source-image" src="${src}" alt="待修改 PNG"></div>`;
  if (status) status.textContent = `已载入待修改图：${workbench.sourceFileName}`;
}

function getKdpImgBlackStorageKey(bookName = getBookName()) {
  return `sagewrite-kdp-img-black-state:${bookName || "default"}`;
}

function readKdpImgBlackLocalState(bookName = getBookName()) {
  try {
    return JSON.parse(localStorage.getItem(getKdpImgBlackStorageKey(bookName)) || "{}") || {};
  } catch {
    return {};
  }
}

function writeKdpImgBlackLocalState(uiState, bookName = getBookName()) {
  try {
    localStorage.setItem(getKdpImgBlackStorageKey(bookName), JSON.stringify(uiState || {}));
  } catch {
    // localStorage can be unavailable in restricted browser contexts.
  }
}

function getKdpImgBlackUiStateFromFields() {
  const valueOrEmpty = (selector) => {
    const value = $(selector)?.value;
    return value === undefined || value === null || value === "" ? "" : Math.round(Number(value));
  };
  return {
    crop: {
      x: valueOrEmpty("#kdp-img-black-crop-x"),
      y: valueOrEmpty("#kdp-img-black-crop-y"),
      width: valueOrEmpty("#kdp-img-black-crop-width"),
      height: valueOrEmpty("#kdp-img-black-crop-height")
    },
    fill: {
      color: $("#kdp-img-black-fill-color")?.value || "#07121b",
      preset: $("#kdp-img-black-fill-preset")?.value || "#07121b",
      mode: $("#kdp-img-black-fill-mode")?.value || "Auto"
    },
    composite: {
      x: valueOrEmpty("#kdp-img-black-composite-x"),
      y: valueOrEmpty("#kdp-img-black-composite-y")
    },
    resize: {
      scalePercent: valueOrEmpty("#kdp-img-black-resize-percent") || 95
    }
  };
}

let kdpImgBlackSaveTimer = null;

function persistKdpImgBlackUiState({ immediate = false } = {}) {
  const bookName = getBookName();
  const uiState = getKdpImgBlackUiStateFromFields();
  writeKdpImgBlackLocalState(uiState, bookName);
  if (!bookName) return;

  const save = async () => {
    try {
      const result = await api("/api/kdp-img-black/state", {
        method: "POST",
        body: JSON.stringify({ bookName, uiState })
      });
      if (result.fixWorkbench) {
        state.kdpFixWorkbench = result.fixWorkbench;
      }
    } catch (error) {
      appendLog(`KDP IMG Black 状态保存失败：${error.message}`);
    }
  };

  if (kdpImgBlackSaveTimer) {
    clearTimeout(kdpImgBlackSaveTimer);
    kdpImgBlackSaveTimer = null;
  }
  if (immediate) {
    save();
    return;
  }
  kdpImgBlackSaveTimer = setTimeout(save, 350);
}

function setKdpImgBlackCropFields(crop = {}) {
  [
    ["#kdp-img-black-crop-x", crop.x],
    ["#kdp-img-black-crop-y", crop.y],
    ["#kdp-img-black-crop-width", crop.width],
    ["#kdp-img-black-crop-height", crop.height]
  ].forEach(([selector, value]) => {
    const field = $(selector);
    if (!field || value === undefined || value === null || value === "") return;
    field.value = String(Math.round(Number(value)));
  });
}

function getKdpImgBlackSavedCrop(workbench = state.kdpFixWorkbench || {}) {
  const uiCrop = workbench.imgBlackUi?.crop || readKdpImgBlackLocalState().crop || {};
  const latestCrop = workbench.latestCrop?.crop || {};
  const latestFill = workbench.latestFill?.fill || {};
  return {
    x: uiCrop.x !== "" && uiCrop.x !== undefined ? uiCrop.x : (latestCrop.x ?? latestFill.x ?? ""),
    y: uiCrop.y !== "" && uiCrop.y !== undefined ? uiCrop.y : (latestCrop.y ?? latestFill.y ?? ""),
    width: uiCrop.width !== "" && uiCrop.width !== undefined ? uiCrop.width : (latestCrop.width ?? latestFill.width ?? ""),
    height: uiCrop.height !== "" && uiCrop.height !== undefined ? uiCrop.height : (latestCrop.height ?? latestFill.height ?? "")
  };
}

function renderKdpImgBlackSourceImage(bookName, sourceFileName, crop = null) {
  const target = $("#kdp-img-black-workarea-1");
  const fileLabel = $("#kdp-img-black-workarea-1-file");
  if (!target || !bookName || !sourceFileName) return;
  const src = `/api/kdp-fix-image?bookName=${encodeURIComponent(bookName)}&kind=source&fileName=${encodeURIComponent(sourceFileName)}&t=${Date.now()}`;
  if (fileLabel) fileLabel.textContent = `文件名：${sourceFileName}`;
  target.innerHTML = `<div class="kdp-img-black-image-wrap"><img id="kdp-img-black-source-image" src="${src}" alt="待修改 PNG"></div>`;
  const img = $("#kdp-img-black-source-image");
  const mark = () => {
    if (crop && crop.x !== "" && crop.y !== "" && crop.width !== "" && crop.height !== "") {
      markKdpImgBlackCropRegion(img, crop);
    }
  };
  img?.addEventListener("load", mark, { once: true });
  if (img?.complete) mark();
}

function renderKdpImgBlackWorkbenchState(workbench = state.kdpFixWorkbench || {}) {
  const item = getSelectedWorkspaceItem();
  const bookName = item?.bookName || getBookName();
  const localState = readKdpImgBlackLocalState(bookName);
  const uiState = {
    ...localState,
    ...(workbench.imgBlackUi || {}),
    crop: {
      ...(localState.crop || {}),
      ...(workbench.imgBlackUi?.crop || {})
    },
    fill: {
      ...(localState.fill || {}),
      ...(workbench.imgBlackUi?.fill || {})
    },
    composite: {
      ...(localState.composite || {}),
      ...(workbench.imgBlackUi?.composite || {})
    },
    resize: {
      ...(localState.resize || {}),
      ...(workbench.imgBlackUi?.resize || {})
    }
  };
  const crop = getKdpImgBlackSavedCrop(workbench);
  setKdpImgBlackCropFields(crop);
  const resizeField = $("#kdp-img-black-resize-percent");
  const resizePercent = uiState.resize?.scalePercent || workbench.latestResize?.scalePercent || 95;
  if (resizeField) resizeField.value = String(Math.round(Number(resizePercent)));

  const fillColor = uiState.fill?.color || workbench.latestFill?.fillColor || "#07121b";
  const fillPreset = uiState.fill?.preset || fillColor;
  const colorField = $("#kdp-img-black-fill-color");
  const presetField = $("#kdp-img-black-fill-preset");
  const modeField = $("#kdp-img-black-fill-mode");
  if (colorField && /^#[0-9a-fA-F]{6}$/.test(fillColor)) colorField.value = fillColor;
  if (modeField) modeField.value = uiState.fill?.mode === "Solid" ? "Solid" : "Auto";
  if (presetField) {
    const presetExists = Array.from(presetField.options).some((option) => option.value === fillPreset);
    presetField.value = presetExists ? fillPreset : "custom";
  }

  if (bookName && workbench.sourceFileName) {
    renderKdpImgBlackSourceImage(bookName, workbench.sourceFileName, crop);
  }

  const cropTarget = $("#kdp-img-black-workarea-2");
  const cropMeta = $("#kdp-img-black-workarea-2-meta");
  if (bookName && workbench.latestCrop?.outputFileName && cropTarget) {
    const name = workbench.latestCrop.outputFileName;
    cropTarget.innerHTML = `<img src="/api/kdp-fix-image?bookName=${encodeURIComponent(bookName)}&kind=crop&fileName=${encodeURIComponent(name)}&t=${Date.now()}" alt="局部小图">`;
    if (cropMeta) cropMeta.textContent = `局部小图：${name} | 来源：${workbench.sourceFileName || "-"} | x=${workbench.latestCrop.crop?.x ?? "-"}, y=${workbench.latestCrop.crop?.y ?? "-"}, 宽=${workbench.latestCrop.crop?.width ?? "-"}, 长度=${workbench.latestCrop.crop?.height ?? "-"}`;
  }

  const fillTarget = $("#kdp-img-black-workarea-3");
  const fillMeta = $("#kdp-img-black-workarea-3-meta");
  if (bookName && workbench.latestFill?.outputFileName && fillTarget) {
    const name = workbench.latestFill.outputFileName;
    fillTarget.innerHTML = `<img src="/api/kdp-fix-image?bookName=${encodeURIComponent(bookName)}&kind=fill&fileName=${encodeURIComponent(name)}&t=${Date.now()}" alt="回填后的原图">`;
    if (fillMeta) fillMeta.textContent = `回填图：${name} | 方式=${workbench.latestFill.fillMode || "Auto"} | 颜色=${workbench.latestFill.fillColor || fillColor} | x=${workbench.latestFill.fill?.x ?? "-"}, y=${workbench.latestFill.fill?.y ?? "-"}, 宽=${workbench.latestFill.fill?.width ?? "-"}, 长度=${workbench.latestFill.fill?.height ?? "-"}`;
  }

  const compositeX = uiState.composite?.x !== "" && uiState.composite?.x !== undefined
    ? uiState.composite.x
    : (workbench.latestComposite?.composite?.x ?? crop.x ?? "");
  const compositeY = uiState.composite?.y !== "" && uiState.composite?.y !== undefined
    ? uiState.composite.y
    : (workbench.latestComposite?.composite?.y ?? crop.y ?? "");
  [
    ["#kdp-img-black-composite-x", compositeX],
    ["#kdp-img-black-composite-y", compositeY]
  ].forEach(([selector, value]) => {
    const field = $(selector);
    if (!field || value === undefined || value === null || value === "") return;
    field.value = String(Math.round(Number(value)));
  });

  const compositeTarget = $("#kdp-img-black-workarea-4");
  const compositeMeta = $("#kdp-img-black-workarea-4-meta");
  const compositePath = $("#kdp-img-black-workarea-4-path");
  const pdfMeta = $("#kdp-img-black-workarea-4-pdf");
  const pdfPath = $("#kdp-img-black-workarea-4-pdf-path");
  if (bookName && workbench.latestComposite?.outputFileName && compositeTarget) {
    const name = workbench.latestComposite.outputFileName;
    compositeTarget.innerHTML = `<img src="/api/kdp-fix-image?bookName=${encodeURIComponent(bookName)}&kind=composite&fileName=${encodeURIComponent(name)}&t=${Date.now()}" alt="拼接图">`;
    if (compositeMeta) compositeMeta.textContent = `拼接图：${name} | x=${workbench.latestComposite.composite?.x ?? "-"}, y=${workbench.latestComposite.composite?.y ?? "-"}`;
    if (compositePath) compositePath.textContent = `路径：${workbench.latestComposite.outputPath || "fix_workbench/composites/" + name}`;
  }
  if (bookName && workbench.latestPdf?.outputFileName) {
    const name = workbench.latestPdf.outputFileName;
    const href = `/api/kdp-fix-pdf?bookName=${encodeURIComponent(bookName)}&fileName=${encodeURIComponent(name)}&t=${Date.now()}`;
    if (pdfMeta) pdfMeta.innerHTML = `PDF：<a href="${href}" target="_blank" rel="noopener">${escapeHtml(name)}</a>`;
    if (pdfPath) pdfPath.textContent = `PDF路径：${workbench.latestPdf.outputPath || "fix_workbench/pdfs/" + name}`;
  }

  const status = $("#kdp-img-black-status");
  if (status && (workbench.sourceFileName || workbench.latestCrop?.outputFileName || workbench.latestFill?.outputFileName || workbench.latestComposite?.outputFileName || workbench.latestPdf?.outputFileName)) {
    status.textContent = "已恢复 imageMagcik 修图工作台状态，可继续往下做。";
  }
}

function getKdpImgBlackCompositeParams() {
  const x = Math.round(Number($("#kdp-img-black-composite-x")?.value));
  const y = Math.round(Number($("#kdp-img-black-composite-y")?.value));
  if (!Number.isFinite(x) || !Number.isFinite(y)) {
    throw new Error("请先填写贴回X和贴回Y两个数字。");
  }
  if (x < 0 || y < 0) {
    throw new Error("贴回X/Y不能小于 0。");
  }
  return { x, y };
}

function getKdpImgBlackResizePercent() {
  const scalePercent = Number($("#kdp-img-black-resize-percent")?.value);
  if (!Number.isFinite(scalePercent) || scalePercent <= 1 || scalePercent > 400) {
    throw new Error("缩放比例必须大于 1 且不超过 400。例如 95 或 105。");
  }
  return scalePercent;
}

function getKdpImgBlackCropParams() {
  const fields = {
    x: $("#kdp-img-black-crop-x"),
    y: $("#kdp-img-black-crop-y"),
    width: $("#kdp-img-black-crop-width"),
    height: $("#kdp-img-black-crop-height")
  };
  const params = Object.fromEntries(Object.entries(fields).map(([key, field]) => [
    key,
    Math.round(Number(field?.value))
  ]));
  if (!Number.isFinite(params.x) || !Number.isFinite(params.y) || !Number.isFinite(params.width) || !Number.isFinite(params.height)) {
    throw new Error("请先填写相对X、相对Y、宽、长度四个数字。");
  }
  if (params.x < 0 || params.y < 0 || params.width <= 0 || params.height <= 0) {
    throw new Error("相对坐标不能小于 0，宽和长度必须大于 0。");
  }
  return params;
}

function markKdpImgBlackCropRegion(img, params) {
  const wrap = img.closest(".kdp-img-black-image-wrap");
  if (!wrap || !img.naturalWidth || !img.naturalHeight) return;
  wrap.querySelector(".kdp-img-black-crop-marker")?.remove();
  const scaleX = img.clientWidth / img.naturalWidth;
  const scaleY = img.clientHeight / img.naturalHeight;
  const marker = document.createElement("div");
  marker.className = "kdp-img-black-crop-marker";
  marker.style.left = `${params.x * scaleX}px`;
  marker.style.top = `${params.y * scaleY}px`;
  marker.style.width = `${params.width * scaleX}px`;
  marker.style.height = `${params.height * scaleY}px`;
  wrap.appendChild(marker);
}

async function cropKdpImgBlackSourceRegion() {
  const bookName = requireBookName();
  const workbench = state.kdpFixWorkbench || {};
  const img = $("#kdp-img-black-source-image");
  const target = $("#kdp-img-black-workarea-2");
  const meta = $("#kdp-img-black-workarea-2-meta");
  const status = $("#kdp-img-black-status");
  if (!workbench.sourceFileName) {
    throw new Error("尚未准备待修改 PNG。请先在 KDP 修图工作台点击“准备修改文件”。");
  }
  if (!img || !target) {
    throw new Error("请先点击“取待修改图”，把原图载入图形工作区1。");
  }
  if (!img.complete || !img.naturalWidth || !img.naturalHeight) {
    throw new Error("待修改图还没有加载完成，请稍后再取局部小图。");
  }
  const params = getKdpImgBlackCropParams();
  if (params.x + params.width > img.naturalWidth || params.y + params.height > img.naturalHeight) {
    throw new Error(`局部小图范围超出原图。原图尺寸：${img.naturalWidth} x ${img.naturalHeight}px。`);
  }

  persistKdpImgBlackUiState({ immediate: true });
  if (status) status.textContent = "正在调用 kdp-crop-image-region.ps1 截取局部小图...";
  const result = await api("/api/kdp-img-black/crop", {
    method: "POST",
    body: JSON.stringify({
      bookName,
      sourceFileName: workbench.sourceFileName,
      x: params.x,
      y: params.y,
      width: params.width,
      height: params.height,
      force: true
    })
  });
  if (result.fixWorkbench) {
    state.kdpFixWorkbench = result.fixWorkbench;
  }
  const imageUrl = result.cropImageUrl || `/api/kdp-fix-image?bookName=${encodeURIComponent(bookName)}&kind=crop&fileName=${encodeURIComponent(result.crop?.outputFileName || "")}&t=${Date.now()}`;
  target.innerHTML = `<img src="${imageUrl}" alt="局部小图">`;
  markKdpImgBlackCropRegion(img, params);

  const sourceName = state.kdpFixWorkbench?.sourceFileName || "待修改图";
  const outputName = result.crop?.outputFileName || "局部小图";
  const label = `${outputName} | 来源：${sourceName} | x=${params.x}, y=${params.y}, 宽=${params.width}, 长度=${params.height}`;
  if (meta) meta.textContent = `局部小图：${label}`;
  if (status) status.textContent = `已调用 kdp-crop-image-region.ps1 生成局部小图：${outputName}`;
}

async function resizeKdpImgBlackCropImage() {
  const bookName = requireBookName();
  const workbench = state.kdpFixWorkbench || {};
  const target = $("#kdp-img-black-workarea-2");
  const meta = $("#kdp-img-black-workarea-2-meta");
  const status = $("#kdp-img-black-status");
  if (!workbench.latestCrop?.outputFileName) {
    throw new Error("请先在图形工作区2生成局部小图。");
  }
  if (!target) return;

  const scalePercent = getKdpImgBlackResizePercent();
  persistKdpImgBlackUiState({ immediate: true });
  if (status) status.textContent = `正在调用 kdp-resize-image-region.ps1 缩放局部小图到 ${scalePercent}%...`;
  const result = await api("/api/kdp-img-black/resize", {
    method: "POST",
    body: JSON.stringify({
      bookName,
      inputFileName: workbench.latestCrop.outputFileName,
      scalePercent,
      force: true
    })
  });
  if (result.fixWorkbench) {
    state.kdpFixWorkbench = result.fixWorkbench;
  }
  const outputName = result.resize?.outputFileName || "缩放图";
  const imageUrl = result.cropImageUrl || `/api/kdp-fix-image?bookName=${encodeURIComponent(bookName)}&kind=crop&fileName=${encodeURIComponent(outputName)}&t=${Date.now()}`;
  target.innerHTML = `<img src="${imageUrl}" alt="缩放后的局部小图">`;
  if (meta) {
    const size = result.resize?.output ? `${result.resize.output.width} x ${result.resize.output.height}px` : "-";
    meta.textContent = `局部小图：${outputName} | 缩放=${scalePercent}% | 尺寸=${size}`;
  }
  if (status) status.textContent = `已调用 kdp-resize-image-region.ps1 生成缩放图：${outputName}`;
}

function getKdpImgBlackFillColor() {
  const colorField = $("#kdp-img-black-fill-color");
  const value = String(colorField?.value || "#07121b").trim();
  if (!/^#[0-9a-fA-F]{6}$/.test(value)) {
    throw new Error("请选择有效的回填颜色。");
  }
  return value;
}

async function fillKdpImgBlackSourceRegion() {
  const bookName = requireBookName();
  const workbench = state.kdpFixWorkbench || {};
  const img = $("#kdp-img-black-source-image");
  const target = $("#kdp-img-black-workarea-3");
  const meta = $("#kdp-img-black-workarea-3-meta");
  const status = $("#kdp-img-black-status");
  if (!workbench.sourceFileName) {
    throw new Error("尚未准备待修改 PNG。请先在 KDP 修图工作台点击“准备修改文件”。");
  }
  if (!img || !target) {
    throw new Error("请先点击“取待修改图”，把原图载入图形工作区1。");
  }
  if (!img.complete || !img.naturalWidth || !img.naturalHeight) {
    throw new Error("待修改图还没有加载完成，请稍后再回填原图。");
  }
  const params = getKdpImgBlackCropParams();
  if (params.x + params.width > img.naturalWidth || params.y + params.height > img.naturalHeight) {
    throw new Error(`回填区域超出原图。原图尺寸：${img.naturalWidth} x ${img.naturalHeight}px。`);
  }
  const fillColor = getKdpImgBlackFillColor();
  const fillMode = $("#kdp-img-black-fill-mode")?.value === "Solid" ? "Solid" : "Auto";

  persistKdpImgBlackUiState({ immediate: true });
  if (status) status.textContent = fillMode === "Auto"
    ? "正在调用 kdp-fill-image-region.ps1 自动取样回填原图..."
    : "正在调用 kdp-fill-image-region.ps1 纯色回填原图...";
  const result = await api("/api/kdp-img-black/fill", {
    method: "POST",
    body: JSON.stringify({
      bookName,
      sourceFileName: workbench.sourceFileName,
      x: params.x,
      y: params.y,
      width: params.width,
      height: params.height,
      fillColor,
      fillMode,
      force: true
    })
  });
  if (result.fixWorkbench) {
    state.kdpFixWorkbench = result.fixWorkbench;
  }
  const imageUrl = result.fillImageUrl || `/api/kdp-fix-image?bookName=${encodeURIComponent(bookName)}&kind=fill&fileName=${encodeURIComponent(result.fill?.outputFileName || "")}&t=${Date.now()}`;
  target.innerHTML = `<img src="${imageUrl}" alt="回填后的原图">`;
  markKdpImgBlackCropRegion(img, params);

  const sourceName = state.kdpFixWorkbench?.sourceFileName || "待修改图";
  const outputName = result.fill?.outputFileName || "回填图";
  const label = `${outputName} | 来源：${sourceName} | 方式=${fillMode} | 颜色=${fillColor} | x=${params.x}, y=${params.y}, 宽=${params.width}, 长度=${params.height}`;
  if (meta) meta.textContent = `回填图：${label}`;
  if (status) status.textContent = `已调用 kdp-fill-image-region.ps1 生成回填图：${outputName}`;
}

async function compositeKdpImgBlackImages() {
  const bookName = requireBookName();
  const workbench = state.kdpFixWorkbench || {};
  const target = $("#kdp-img-black-workarea-4");
  const meta = $("#kdp-img-black-workarea-4-meta");
  const pathLabel = $("#kdp-img-black-workarea-4-path");
  const status = $("#kdp-img-black-status");
  if (!workbench.latestCrop?.outputFileName) {
    throw new Error("请先在图形工作区2生成局部小图。");
  }
  if (!workbench.latestFill?.outputFileName) {
    throw new Error("请先在图形工作区3生成回填后的原图。");
  }
  if (!target) return;

  const params = getKdpImgBlackCompositeParams();
  persistKdpImgBlackUiState({ immediate: true });
  if (status) status.textContent = "正在调用 kdp-composite-image-region.ps1 拼接图片...";
  const result = await api("/api/kdp-img-black/composite", {
    method: "POST",
    body: JSON.stringify({
      bookName,
      baseFileName: workbench.latestFill.outputFileName,
      overlayFileName: workbench.latestCrop.outputFileName,
      x: params.x,
      y: params.y,
      force: true
    })
  });
  if (result.fixWorkbench) {
    state.kdpFixWorkbench = result.fixWorkbench;
  }
  const outputName = result.composite?.outputFileName || "拼接图";
  const outputPath = result.composite?.outputPath || "";
  const imageUrl = result.compositeImageUrl || `/api/kdp-fix-image?bookName=${encodeURIComponent(bookName)}&kind=composite&fileName=${encodeURIComponent(outputName)}&t=${Date.now()}`;
  target.innerHTML = `<img src="${imageUrl}" alt="拼接图">`;
  if (meta) meta.textContent = `拼接图：${outputName} | x=${params.x}, y=${params.y}`;
  if (pathLabel) pathLabel.textContent = `路径：${outputPath || "-"}`;
  if (status) status.textContent = `已调用 kdp-composite-image-region.ps1 生成拼接图：${outputName}`;
}

async function convertKdpImgBlackCompositePngToPdf() {
  const bookName = requireBookName();
  const workbench = state.kdpFixWorkbench || {};
  const pdfMeta = $("#kdp-img-black-workarea-4-pdf");
  const pdfPath = $("#kdp-img-black-workarea-4-pdf-path");
  const status = $("#kdp-img-black-status");
  if (!workbench.latestComposite?.outputFileName) {
    throw new Error("请先在图形工作区4生成当前拼接 PNG。");
  }

  if (status) status.textContent = "正在调用 kdp-png-to-pdf.ps1 将当前 PNG 文件转换为 PDF...";
  const result = await api("/api/kdp-img-black/png-to-pdf", {
    method: "POST",
    body: JSON.stringify({
      bookName,
      inputFileName: workbench.latestComposite.outputFileName,
      force: true
    })
  });
  if (result.fixWorkbench) {
    state.kdpFixWorkbench = result.fixWorkbench;
  }
  const outputName = result.pdf?.outputFileName || "PDF";
  const outputPath = result.pdf?.outputPath || "";
  const href = result.pdfUrl || `/api/kdp-fix-pdf?bookName=${encodeURIComponent(bookName)}&fileName=${encodeURIComponent(outputName)}&t=${Date.now()}`;
  if (pdfMeta) pdfMeta.innerHTML = `PDF：<a href="${href}" target="_blank" rel="noopener">${escapeHtml(outputName)}</a>`;
  if (pdfPath) pdfPath.textContent = `PDF路径：${outputPath || "-"}`;
  if (status) status.textContent = `已调用 kdp-png-to-pdf.ps1 生成 PDF：${outputName}`;
}

function renderKdpAcceptanceFileList(files = []) {
  const panel = $("#kdp-acceptance-file-list");
  if (!panel) return;
  if (!files.length) {
    panel.innerHTML = '<div class="cover-gallery-empty">KDP acceptance directory has no PDF/PNG files.</div>';
    return;
  }
  panel.innerHTML = files.map((file) => {
    const type = String(file.type || "").toUpperCase();
    const label = file.role ? `${file.role} · ${file.modifiedAt || ""}` : (file.modifiedAt || "");
    return `
      <button class="kdp-acceptance-file-item" type="button" data-kdp-file="${escapeHtml(file.relativePath || file.name || "")}" data-kdp-type="${escapeHtml(file.type || "")}">
        <span>${escapeHtml(type || "FILE")}</span>
        <strong>${escapeHtml(file.relativePath || file.name || "")}</strong>
        <em>${escapeHtml(label)}</em>
      </button>
    `;
  }).join("");
}

async function refreshKdpAcceptanceFileList() {
  const bookName = requireBookName();
  const result = await api(`/api/kdp-acceptance-files?bookName=${encodeURIComponent(bookName)}`);
  renderKdpAcceptanceFileList(result.files || []);
  return result;
}

async function openKdpAcceptanceDirectoryAndList() {
  const bookName = requireBookName();
  setStatusBadge(isCloudAppMode() ? "定位中" : "打开中", "running");
  setLog(isCloudAppMode()
    ? "云端模式不会打开服务器资源管理器，正在刷新 KDP 验收目录列表..."
    : "Opening KDP acceptance directory with kdp-acceptance-files.ps1...");
  if (isCloudAppMode()) {
    const result = await refreshKdpAcceptanceFileList();
    setStatusBadge("已定位", "success");
    setLog([
      "云端模式不会打开服务器资源管理器；已刷新 KDP 验收目录列表。",
      `路径：${result.acceptanceRoot || ""}`,
      `文件数：${(result.files || []).length}`
    ].join("\n"));
    return;
  }
  await run("kdp-acceptance-files", {
    bookName,
    action: "OpenDirectory"
  });
  const result = await refreshKdpAcceptanceFileList();
  setStatusBadge("已打开", "success");
  appendLog(`KDP acceptance directory listed: ${(result.files || []).length} PDF/PNG files.`);
}

async function useKdpAcceptanceDirectoryFile(fileName, fileType) {
  const bookName = requireBookName();
  const type = String(fileType || "").toLowerCase();
  const effectiveType = getKdpFileTypeLabel(fileName, type);
  const fileUrl = `/api/kdp-acceptance-file?bookName=${encodeURIComponent(bookName)}&fileName=${encodeURIComponent(fileName)}&t=${Date.now()}`;
  if (effectiveType === "PNG") {
    const result = await api("/api/kdp-acceptance-existing-file", {
      method: "POST",
      body: JSON.stringify({ bookName, fileName })
    });
    const spec = getCurrentKdpGuideSpec();
    setKdpSourceMetadata(result.currentSource || getKdpAcceptanceSourceMetadata(result.fileName || fileName, "PNG"));
    await loadKdpImageViewer(result.fileUrl || fileUrl, spec, null);
    renderKdpPngInspectionState({ fileName });
    setStatusBadge("PNG已加载", "success");
    setLog(`Loaded PNG from KDP acceptance directory: ${fileName}`);
    return;
  }

  const result = await api("/api/kdp-acceptance-existing-file", {
    method: "POST",
    body: JSON.stringify({
      bookName,
      fileName,
      trimWidthIn: Number($("#kdp-trim-width")?.value || 6),
      trimHeightIn: Number($("#kdp-trim-height")?.value || 9),
      pageCount: Number($("#kdp-page-count")?.value || 120),
      paperType: $("#kdp-paper-type")?.value || "bw-white",
      bleedIn: Number($("#kdp-bleed")?.value || 0.125)
    })
  });
  const selected = getSelectedWorkspaceItem();
  const currentArtifacts = state.coverCache[bookName] || selected?.coverArtifacts || {};
  setKdpSourceMetadata(result.currentSource || getKdpAcceptanceSourceMetadata(result.fileName || fileName, "PDF"));
  renderKdpCurrentSourceMeta("PDF 已加载，当前走 KDP 技术验收。");
  state.coverCache[bookName] = {
    ...currentArtifacts,
    kdpAcceptance: result.kdpAcceptance || null
  };
  renderKdpAcceptancePanel(selected || null, result.kdpAcceptance || null);
  setStatusBadge("PDF已验收", "success");
  setLog(`Loaded PDF from KDP acceptance directory: ${fileName}`);
}

async function prepareKdpFixWorkbench() {
  if (!state.kdpPdf.page) {
    throw new Error("请先提交并加载 PDF。");
  }
  if (!state.kdpPdf.textRegions?.length) {
    throw new Error("请先识别文字区域，再准备修改文件。");
  }
  const bookName = requireBookName();
  const promptField = $("#kdp-fix-command-prompt");
  if (!promptField?.value || promptField.value === getKdpFixCommandPromptPlaceholder()) {
    generateKdpFixCommandPrompt();
  }
  const prompt = ($("#kdp-fix-command-prompt")?.value || "").trim();
  if (!prompt) {
    throw new Error("请先生成修改命令提示词。");
  }
  const canvas = await renderKdpPageToPngCanvas(300);
  const model = "gpt-image-1.5";
  setStatusBadge("准备中", "running");
  setLog([
    "KDP 修改工作台：准备修改文件。",
    `Source PNG: ${canvas.width} x ${canvas.height}px @ 300DPI`,
    "Saving source PNG and edit prompt..."
  ].join("\n"));
  const result = await api("/api/kdp-fix-workbench/prepare", {
    method: "POST",
    body: JSON.stringify({
      bookName,
      imageDataUrl: canvas.toDataURL("image/png"),
      imageWidth: canvas.width,
      imageHeight: canvas.height,
      prompt,
      model
    })
  });
  if (result.currentSource) {
    setKdpSourceMetadata(result.currentSource);
    renderKdpCurrentSourceMeta("修图源文件已准备为当前工作对象。");
  }
  renderKdpFixWorkbench(result.fixWorkbench || {});
  setStatusBadge("已准备", "success");
  setLog([
    "KDP 修改工作台准备完成。",
    `Source: ${result.fixWorkbench?.sourceFileName || "-"}`,
    `Prompt: ${result.fixWorkbench?.promptFileName || "-"}`
  ].join("\n"));
}

async function runKdpFixWorkbench() {
  const bookName = requireBookName();
  let workbench = state.kdpFixWorkbench || {};
  if (!workbench.sourceFileName) {
    await prepareKdpFixWorkbench();
    workbench = state.kdpFixWorkbench || {};
  }
  const prompt = ($("#kdp-fix-command-prompt")?.value || workbench.prompt || "").trim();
  if (!prompt) {
    throw new Error("缺少修改命令提示词。");
  }
  const model = workbench.model || "gpt-image-1.5";
  setStatusBadge("修图中", "running");
  setLog([
    "KDP 修改工作台：启动独立 PowerShell 修图程序。",
    "Program: kdp-fix-image-edit.ps1",
    `Model: ${model}`,
    `Source: ${workbench.sourceFileName}`,
    `Prompt source: current editable textarea (${prompt.length} characters)`,
    "PowerShell 输出会在这里持续显示，包括任务、程序、输入输出、usage/token。"
  ].join("\n"));
  const job = await run("kdp-fix-image-edit", {
      bookName,
      sourceFileName: workbench.sourceFileName,
      promptFileName: workbench.promptFileName || "",
      prompt,
      imageModel: model,
      force: true
  });
  if (job?.status !== "success") {
    throw new Error("KDP 修改 PowerShell 程序执行失败。");
  }
  const refreshed = await api(`/api/kdp-acceptance?bookName=${encodeURIComponent(bookName)}`);
  renderKdpFixWorkbench(refreshed.kdpAcceptance?.fixWorkbench || {});
  setStatusBadge("已生成", "success");
  appendLog("KDP 修改工作台：修改后文件已生成，并已刷新结果预览。");
}

async function runKdpImageMagickFixWorkbench() {
  const bookName = requireBookName();
  let workbench = state.kdpFixWorkbench || {};
  const instructionField = $("#kdp-imagemagick-instructions");
  const status = $("#kdp-img-black-status");
  const placeholder = getKdpImageMagickInstructionPlaceholder();
  if (instructionField && (!instructionField.value?.trim() || instructionField.value === placeholder)) {
    generateKdpImageMagickInstructions();
  }
  const instructionJson = ($("#kdp-imagemagick-instructions")?.value || "").trim();
  if (!instructionJson || instructionJson === placeholder) {
    throw new Error("请先生成并确认 ImageMagick 指令集。");
  }
  try {
    JSON.parse(instructionJson);
  } catch (error) {
    throw new Error(`ImageMagick 指令集不是有效 JSON：${error.message}`);
  }
  if (!workbench.sourceFileName) {
    await prepareKdpFixWorkbench();
    workbench = state.kdpFixWorkbench || {};
  }
  if (status) status.textContent = "ImageMagick 修图执行中。";
  setStatusBadge("修图中", "running");
  setLog([
    "KDP ImageMagick 修图程序启动。",
    "Program: kdp-imagemagick-fix.ps1",
    `Source: ${workbench.sourceFileName}`,
    `Candidate edit: ${workbench.outputFileName || "-"}`,
    `Instruction source: current editable JSON textarea (${instructionJson.length} characters)`,
    "说明：ImageMagick 会保护原始 300DPI 画布；候选修图尺寸不一致时不会作为整图替换。"
  ].join("\n"));
  const job = await run("kdp-imagemagick-fix", {
    bookName,
    sourceFileName: workbench.sourceFileName,
    inputEditFileName: workbench.outputFileName || "",
    instructionJson,
    force: true
  });
  if (job?.status !== "success") {
    throw new Error("KDP ImageMagick PowerShell 程序执行失败。");
  }
  const refreshed = await api(`/api/kdp-acceptance?bookName=${encodeURIComponent(bookName)}`);
  renderKdpFixWorkbench(refreshed.kdpAcceptance?.fixWorkbench || {});
  if (status) status.textContent = "ImageMagick 修图完成，结果已刷新。";
  setStatusBadge("已生成", "success");
  appendLog("KDP ImageMagick 修图完成，并已刷新结果预览。");
}

function loadImageElement(src) {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve(image);
    image.onerror = () => reject(new Error("图片加载失败。"));
    image.src = src;
  });
}

function bytesToBase64(bytes) {
  let binary = "";
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}

function concatUint8Arrays(parts) {
  const total = parts.reduce((sum, part) => sum + part.length, 0);
  const output = new Uint8Array(total);
  let offset = 0;
  parts.forEach((part) => {
    output.set(part, offset);
    offset += part.length;
  });
  return output;
}

function buildPdfDataUrlFromJpeg(jpegBytes, imageWidth, imageHeight, widthIn, heightIn) {
  const encoder = new TextEncoder();
  const widthPt = Number(widthIn) * 72;
  const heightPt = Number(heightIn) * 72;
  const objects = [];
  const pushObject = (bodyParts) => {
    objects.push(bodyParts);
    return objects.length;
  };
  pushObject([encoder.encode("<< /Type /Catalog /Pages 2 0 R >>")]);
  pushObject([encoder.encode("<< /Type /Pages /Kids [3 0 R] /Count 1 >>")]);
  pushObject([encoder.encode(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${widthPt.toFixed(3)} ${heightPt.toFixed(3)}] /Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>`)]);
  pushObject([
    encoder.encode(`<< /Type /XObject /Subtype /Image /Width ${imageWidth} /Height ${imageHeight} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${jpegBytes.length} >>\nstream\n`),
    jpegBytes,
    encoder.encode("\nendstream")
  ]);
  const content = encoder.encode(`q\n${widthPt.toFixed(3)} 0 0 ${heightPt.toFixed(3)} 0 0 cm\n/Im0 Do\nQ\n`);
  pushObject([encoder.encode(`<< /Length ${content.length} >>\nstream\n`), content, encoder.encode("endstream")]);
  const parts = [encoder.encode("%PDF-1.4\n%\xFF\xFF\xFF\xFF\n")];
  const offsets = [0];
  objects.forEach((bodyParts, index) => {
    offsets.push(parts.reduce((sum, part) => sum + part.length, 0));
    parts.push(encoder.encode(`${index + 1} 0 obj\n`), ...bodyParts, encoder.encode("\nendobj\n"));
  });
  const xrefOffset = parts.reduce((sum, part) => sum + part.length, 0);
  const xrefLines = ["xref", `0 ${objects.length + 1}`, "0000000000 65535 f "];
  for (let i = 1; i < offsets.length; i += 1) {
    xrefLines.push(`${String(offsets[i]).padStart(10, "0")} 00000 n `);
  }
  xrefLines.push("trailer", `<< /Size ${objects.length + 1} /Root 1 0 R >>`, "startxref", String(xrefOffset), "%%EOF");
  parts.push(encoder.encode(xrefLines.join("\n")));
  return `data:application/pdf;base64,${bytesToBase64(concatUint8Arrays(parts))}`;
}

async function submitKdpFixedOutputForAcceptance() {
  const bookName = requireBookName();
  const workbench = state.kdpFixWorkbench || {};
  if (!workbench.outputFileName) {
    throw new Error("请先执行修改，生成修改后的 PNG。");
  }
  const sourceUrl = `/api/kdp-fix-image?bookName=${encodeURIComponent(bookName)}&kind=output&fileName=${encodeURIComponent(workbench.outputFileName)}&t=${Date.now()}`;
  const image = await loadImageElement(sourceUrl);
  const canvas = document.createElement("canvas");
  canvas.width = image.naturalWidth || image.width;
  canvas.height = image.naturalHeight || image.height;
  const context = canvas.getContext("2d");
  context.fillStyle = "#ffffff";
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.drawImage(image, 0, 0);
  const jpegDataUrl = canvas.toDataURL("image/jpeg", 0.96);
  const jpegBytes = Uint8Array.from(atob(jpegDataUrl.split(",")[1] || ""), (char) => char.charCodeAt(0));
  const spec = state.kdpPdf.spec || getCurrentKdpGuideSpec();
  const pdfDataUrl = buildPdfDataUrlFromJpeg(jpegBytes, canvas.width, canvas.height, spec.width, spec.height);
  setStatusBadge("验收中", "running");
  setLog([
    "KDP 修改工作台：提交修改后文件验收。",
    `Output PNG: ${workbench.outputFileName}`,
    `Wrapped PDF size: ${spec.width} x ${spec.height} in`
  ].join("\n"));
  const result = await api("/api/kdp-acceptance", {
    method: "POST",
    body: JSON.stringify({
      bookName,
      fileName: `kdp-fixed-${Date.now()}.pdf`,
      dataUrl: pdfDataUrl,
      trimWidthIn: Number($("#kdp-trim-width")?.value || 6),
      trimHeightIn: Number($("#kdp-trim-height")?.value || 9),
      pageCount: Number($("#kdp-page-count")?.value || 120),
      paperType: $("#kdp-paper-type")?.value || "bw-white",
      bleedIn: Number($("#kdp-bleed")?.value || 0.125)
    })
  });
  const item = getSelectedWorkspaceItem();
  if (item) {
    renderKdpAcceptancePanel(item, result.kdpAcceptance);
  }
  setStatusBadge("已验收", "success");
  setLog("修改后文件已包装成 PDF 并提交 KDP 验收。请查看新的验收结果，然后继续识别/报告/修改循环。");
}

async function generateKdpFixReport() {
  const reportField = $("#kdp-fix-report");
  if (!reportField) return;
  if (!state.kdpPdf.textRegions?.length) {
    reportField.value = "尚未识别文字区域。请先点击“LLM识别文字区域”，或等待上次识别结果恢复后再生成修改意见报告。";
    return;
  }
  const bookName = requireBookName();
  const reportText = buildKdpFixReport();
  const spec = state.kdpPdf.spec || getCurrentKdpGuideSpec();
  const isImageMode = state.kdpPdf.mode === "image";
  const primaryLabel = isImageMode ? "PNG" : "PDF";
  const primarySize = isImageMode ? getKdpPngActualSizePx() : getKdpPdfActualSizePx(300);
  const pngSize = getKdpPngActualSizePx();
  reportField.value = reportText;
  setStatusBadge("保存中", "running");
  setLog([
    "KDP 修改意见报告程序启动。",
    `任务：计算 ${primaryLabel} 的封底/书脊/封面中轴线，生成修图建议报告，并保存版本。`,
    `${primaryLabel} 文件实际尺寸：${primarySize ? `${primarySize.width} x ${primarySize.height}px${isImageMode ? "" : " @ 300DPI"}` : "未加载"}`,
    ...(!isImageMode ? [
      `PNG 文件实际尺寸：${pngSize ? `${pngSize.width} x ${pngSize.height}px` : "未生成/未恢复"}`
    ] : []),
    "正在保存到 07_cover/kdp_acceptance/fix_reports ..."
  ].join("\n"));
  const result = await api("/api/kdp-fix-report", {
    method: "POST",
    body: JSON.stringify({
      bookName,
      reportText,
      spec,
      source: state.kdpPdf.source || null,
      textRegionCount: state.kdpPdf.textRegions.length
    })
  });
  const savedText = result?.fixReport?.latest?.reportText || reportText;
  reportField.value = savedText;
  setStatusBadge("已保存", "success");
  setLog([
    "KDP 修改意见报告程序完成。",
    `已保存当前版本：${result?.saved?.textFileName || "latest_kdp_fix_report.md"}`,
    `latest 文件：${result?.saved?.latestTextFileName || "latest_kdp_fix_report.md"}`,
    `back 备份目录：${result?.saved?.backupDir || "fix_reports/back"}`,
    "旧 latest 已在覆盖前自动备份。"
  ].join("\n"));
}

async function recognizeKdpTextRegions() {
  if (!state.kdpPdf.page) {
    throw new Error("请先提交并加载 PDF。");
  }
  const button = $("#kdp-ocr-text");
  const spec = state.kdpPdf.spec || getCurrentKdpGuideSpec();
  const dpi = 300;
  const ocrScale = dpi / 72;
  const viewport = state.kdpPdf.page.getViewport({ scale: ocrScale });
  const ocrCanvas = document.createElement("canvas");
  ocrCanvas.width = Math.ceil(viewport.width);
  ocrCanvas.height = Math.ceil(viewport.height);
  const context = ocrCanvas.getContext("2d");

  button?.setAttribute("disabled", "true");
  setKdpPdfViewerStatus("正在渲染 300DPI PNG");
  await state.kdpPdf.page.render({ canvasContext: context, viewport }).promise;
  state.kdpPdf.ocrCanvasWidth = ocrCanvas.width;
  state.kdpPdf.ocrCanvasHeight = ocrCanvas.height;
  const preprocessedCanvas = preprocessKdpOcrCanvas(ocrCanvas);

  setKdpPdfViewerStatus("正在 OCR 识别文字区域");
  const tesseract = await loadTesseract();
  const result = await tesseract.recognize(preprocessedCanvas, "eng", {
    logger: (event) => {
      if (event?.status) {
        const progress = Number.isFinite(event.progress) ? ` ${Math.round(event.progress * 100)}%` : "";
        setKdpPdfViewerStatus(`${event.status}${progress}`);
      }
    }
  });
  const words = Array.isArray(result?.data?.words) ? result.data.words : [];
  const regions = words
    .map((word, index) => normalizeOcrWord(word, index, spec, dpi))
    .filter(isLikelyTextRegion);

  state.kdpPdf.visionDebug = null;
  state.kdpPdf.textRegions = regions;
  renderKdpTextRegions(regions);
  renderKdpTextRegionReport(regions);
  setKdpPdfViewerStatus(`OCR 完成 · ${regions.length} 个文字框`);
  button?.removeAttribute("disabled");
}

async function renderKdpPageToPngCanvas(dpi = 300) {
  if (!state.kdpPdf.page) {
    throw new Error("请先提交并加载 PDF。");
  }
  if (state.kdpPdf.mode === "image" && state.kdpPdf.image && state.kdpPdf.imageSize) {
    const canvas = document.createElement("canvas");
    canvas.width = Math.ceil(state.kdpPdf.imageSize.width);
    canvas.height = Math.ceil(state.kdpPdf.imageSize.height);
    canvas.getContext("2d").drawImage(state.kdpPdf.image, 0, 0, canvas.width, canvas.height);
    return canvas;
  }
  const scale = dpi / 72;
  const viewport = state.kdpPdf.page.getViewport({ scale });
  const canvas = document.createElement("canvas");
  canvas.width = Math.ceil(viewport.width);
  canvas.height = Math.ceil(viewport.height);
  await state.kdpPdf.page.render({
    canvasContext: canvas.getContext("2d"),
    viewport
  }).promise;
  return canvas;
}

function normalizeLlmRegion(region, index, spec, dpi = 300) {
  const x = Math.max(0, Math.round(Number(region.x || 0)));
  const y = Math.max(0, Math.round(Number(region.y || 0)));
  const width = Math.max(0, Math.round(Number(region.width || 0)));
  const height = Math.max(0, Math.round(Number(region.height || 0)));
  const box = {
    id: String(region.id || `llm-${index + 1}`),
    text: String(region.text || "").trim(),
    confidence: Number(Number(region.confidence ?? 0.75).toFixed(2)),
    x,
    y,
    width,
    height,
    right: x + width,
    bottom: y + height,
    orientation: String(region.orientation || "unknown"),
    notes: String(region.notes || ""),
    source: "llm_vision"
  };
  const decision = getKdpZoneDecisionForBox(box, spec, dpi);
  const displayBox = getKdpDisplayBoxForRegion(box, decision, spec, dpi);
  return {
    ...box,
    rawZone: String(region.zone || "unclassified").toLowerCase(),
    zone: decision.zone,
    zoneReason: decision.reason,
    displayBox,
    inches: {
      x: roundForDisplay(box.x / dpi),
      y: roundForDisplay(box.y / dpi),
      width: roundForDisplay(box.width / dpi),
      height: roundForDisplay(box.height / dpi),
      right: roundForDisplay(box.right / dpi),
      bottom: roundForDisplay(box.bottom / dpi)
    }
  };
}

async function recognizeKdpTextRegionsWithLlm() {
  const button = $("#kdp-llm-text");
  const spec = state.kdpPdf.spec || getCurrentKdpGuideSpec();
  const dpi = 300;
  const bookName = requireBookName();
  const model = getDefaultModelName();
  const startedAt = new Date();
  button?.setAttribute("disabled", "true");
  setStatusBadge("LLM运行中", "running");
  setLog([
    "KDP LLM text-region inspection started.",
    `BookName: ${bookName}`,
    `Model: ${model}`,
    `Started: ${startedAt.toLocaleString()}`
  ].join("\n"));
  const currentSource = state.kdpPdf.source || {};
  const currentType = getKdpFileTypeLabel(currentSource.fileName || currentSource.relativePath, currentSource.type);
  const currentSourcePath = currentType === "PNG" ? getKdpSourceAcceptanceRelativePath(currentSource) : "";
  let requestBody = { bookName, model };
  let imageWidth = 0;
  let imageHeight = 0;
  if (currentType === "PNG") {
    if (!currentSourcePath || currentSource.origin === "local upload") {
      throw new Error("当前 PNG 尚未保存到验收目录。请重新选择 PNG，让系统先保存为当前工作对象。");
    }
    const pngSize = getKdpPngActualSizePx() || state.kdpPdf.imageSize || null;
    imageWidth = Math.round(Number(pngSize?.width || 0));
    imageHeight = Math.round(Number(pngSize?.height || 0));
    requestBody = {
      ...requestBody,
      sourceRelativePath: currentSourcePath,
      imageWidth,
      imageHeight
    };
    setKdpPdfViewerStatus("正在提交当前 PNG 给 LLM");
    appendLog(`Using current PNG source without canvas re-export: ${currentSource.relativePath || currentSourcePath}`);
  } else {
    setKdpPdfViewerStatus("正在生成 300DPI PNG");
    const canvas = await renderKdpPageToPngCanvas(dpi);
    imageWidth = canvas.width;
    imageHeight = canvas.height;
    state.kdpPdf.ocrCanvasWidth = canvas.width;
    state.kdpPdf.ocrCanvasHeight = canvas.height;
    requestBody = {
      ...requestBody,
      imageDataUrl: canvas.toDataURL("image/png"),
      imageWidth: canvas.width,
      imageHeight: canvas.height
    };
    appendLog(`PNG rendered: ${canvas.width} x ${canvas.height}px @ ${dpi} DPI`);
  }

  setKdpPdfViewerStatus("正在提交给 LLM 识别文字区域");
  appendLog("Submitting PNG to LLM vision endpoint...");
  const result = await api("/api/kdp-llm-text-regions", {
    method: "POST",
    body: JSON.stringify(requestBody)
  });
  imageWidth = Math.round(Number(result.image?.width || imageWidth || 0));
  imageHeight = Math.round(Number(result.image?.height || imageHeight || 0));
  if (imageWidth > 0 && imageHeight > 0) {
    state.kdpPdf.ocrCanvasWidth = imageWidth;
    state.kdpPdf.ocrCanvasHeight = imageHeight;
  }

  const regions = (Array.isArray(result.regions) ? result.regions : [])
    .map((region, index) => normalizeLlmRegion(region, index, spec, dpi))
    .filter((region) => region.width > 0 && region.height > 0);
  state.kdpPdf.visionDebug = {
    image: result.image || { width: imageWidth, height: imageHeight },
    modelImage: result.modelImage || result.image || { width: imageWidth, height: imageHeight },
    coordinateScale: result.coordinateScale || { x: 1, y: 1 },
    saved: result.saved || null,
    usage: result.usage || null,
    responseId: result.responseId || "",
    responseStatus: result.responseStatus || "",
    createdAt: result.createdAt || ""
  };
  state.kdpPdf.textRegions = regions;
  renderKdpTextRegions(regions);
  renderKdpTextRegionReport(regions);
  setKdpPdfViewerStatus(`LLM 完成 · ${regions.length} 个文字区域${result.saved?.resultFileName ? " · 已保存" : ""}`);
  setStatusBadge("LLM完成", "success");
  appendLog([
    "LLM text-region inspection completed.",
    `Response: ${result.responseId || "-"}`,
    `Status: ${result.responseStatus || "-"}`,
    `Regions: ${regions.length}`,
    formatKdpLlmUsage(result.usage),
    `Coordinate scale: ${Number(result.coordinateScale?.x || 1).toFixed(4)} / ${Number(result.coordinateScale?.y || 1).toFixed(4)}`,
    `Saved JSON: ${formatKdpLlmSavedPath(result.saved, "json")}`,
    `Saved PNG: ${formatKdpLlmSavedPath(result.saved, "png")}`,
    `Finished: ${new Date().toLocaleString()}`
  ].join("\n"));
  button?.removeAttribute("disabled");
}

function formatInches(value, digits = 3) {
  return Number(value || 0).toFixed(digits).replace(/\.?0+$/g, "");
}

function formatMm(value, digits = 2) {
  return Number((Number(value || 0) * 25.4).toFixed(digits)).toFixed(digits).replace(/\.?0+$/g, "");
}

function formatDimensionPair(width, height) {
  return `${formatInches(width)} x ${formatInches(height)} in / ${formatMm(width)} x ${formatMm(height)} mm`;
}

function renderKdpSizeRules(spec) {
  const panel = $("#kdp-size-rules");
  if (!panel) {
    return;
  }
  const spineTextNote = spec.spine >= 0.125
    ? `书脊红线内可用宽度 ${formatInches(spec.spineSafeWidth)} in / ${formatMm(spec.spineSafeWidth)} mm。`
    : "书脊太窄，红线内几乎没有可用文字空间。";
  const barcodeWidth = Number(spec.barcodeWidth || 2);
  const barcodeHeight = Number(spec.barcodeHeight || 1.2);
  const barcodeInset = Number(spec.barcodeInset || 0.25);
  const barcodeX = spec.bleed + spec.trimWidth - barcodeInset - barcodeWidth;
  const barcodeY = spec.bleed + spec.trimHeight - barcodeInset - barcodeHeight;
  panel.innerHTML = `
    <div class="kdp-size-rule-card">
      <span>1 · PDF 外边界</span>
      <strong>${escapeHtml(formatDimensionPair(spec.width, spec.height))}</strong>
      <em>提交给 KDP 的整张封面尺寸：出血 + 封底 + 书脊 + 封面 + 出血。</em>
    </div>
    <div class="kdp-size-rule-card">
      <span>2 · 白线裁切尺寸</span>
      <strong>${escapeHtml(formatDimensionPair(spec.whiteWidth, spec.whiteHeight))}</strong>
      <em>裁切后的整张封面摊开尺寸；白线也是书脊左右边缘。</em>
    </div>
    <div class="kdp-size-rule-card">
      <span>3 · 红线安全尺寸</span>
      <strong>封面/封底 ${escapeHtml(formatDimensionPair(spec.frontBackSafeWidth, spec.frontBackSafeHeight))}</strong>
      <em>${escapeHtml(spineTextNote)}文字和重要元素留在红线以内。</em>
    </div>
    <div class="kdp-size-rule-card">
      <span>4 · KDP 条码区域</span>
      <strong>${escapeHtml(formatDimensionPair(barcodeWidth, barcodeHeight))}</strong>
      <em>封底右下角；x=${escapeHtml(formatInches(barcodeX))} in，y=${escapeHtml(formatInches(barcodeY))} in。距离书脊和底部裁切白线均为 ${escapeHtml(formatInches(barcodeInset))} in。</em>
    </div>
  `;
}

function formatKdpRectLine(rect) {
  if (!rect) {
    return "";
  }
  return `
    <tr>
      <th>${escapeHtml(rect.name)}</th>
      <td>${escapeHtml(rect.px.x)}</td>
      <td>${escapeHtml(rect.px.y)}</td>
      <td>${escapeHtml(rect.px.width)}</td>
      <td>${escapeHtml(rect.px.height)}</td>
      <td>${escapeHtml(rect.inches.x)}</td>
      <td>${escapeHtml(rect.inches.y)}</td>
      <td>${escapeHtml(rect.inches.width)}</td>
      <td>${escapeHtml(rect.inches.height)}</td>
      <td>${escapeHtml(rect.mm.x)}</td>
      <td>${escapeHtml(rect.mm.y)}</td>
      <td>${escapeHtml(rect.mm.width)}</td>
      <td>${escapeHtml(rect.mm.height)}</td>
    </tr>
  `;
}

function buildClientKdpCoordinateMapFromReport(report) {
  const spec = report?.spec || {};
  const trimWidth = Number(spec.trimWidthIn || spec.trim_width_in || 6);
  const trimHeight = Number(spec.trimHeightIn || spec.trim_height_in || 9);
  const bleed = Number(spec.bleedIn || spec.bleed_in || 0.125);
  const spine = Number(spec.spineWidthIn || spec.spine_width_in || 0);
  if (!spine) {
    return null;
  }
  const width = Number(spec.expectedWidthIn || spec.cover_width_in || report?.pdf?.widthIn || ((trimWidth * 2) + spine + (bleed * 2)));
  const height = Number(spec.expectedHeightIn || spec.cover_height_in || report?.pdf?.heightIn || (trimHeight + (bleed * 2)));
  const dpi = Number(report?.requiredResolution?.dpi || 300);
  const safeInset = 0.125;
  const spineSafeInset = 0.0625;
  const barcodeWidth = 2;
  const barcodeHeight = 1.2;
  const barcodeInset = 0.25;
  const round = (value) => Number(Number(value || 0).toFixed(3));
  const mm = (value) => Number((Number(value || 0) * 25.4).toFixed(2));
  const px = (value) => Math.round(Number(value || 0) * dpi);
  const rect = (name, x, y, w, h) => ({
    name,
    inches: { x: round(x), y: round(y), width: round(w), height: round(h), right: round(x + w), bottom: round(y + h) },
    mm: { x: mm(x), y: mm(y), width: mm(w), height: mm(h), right: mm(x + w), bottom: mm(y + h) },
    px: { x: px(x), y: px(y), width: px(w), height: px(h), right: px(x + w), bottom: px(y + h) }
  });
  return {
    origin: "top-left of submitted PDF page",
    dpi,
    fullCover: rect("PDF full cover", 0, 0, width, height),
    trimBox: rect("White trim box", bleed, bleed, (trimWidth * 2) + spine, trimHeight),
    backCover: rect("Back cover trim", bleed, bleed, trimWidth, trimHeight),
    spine: rect("Spine trim", bleed + trimWidth, bleed, spine, trimHeight),
    frontCover: rect("Front cover trim", bleed + trimWidth + spine, bleed, trimWidth, trimHeight),
    backSafe: rect("Back cover red safe area", bleed + safeInset, bleed + safeInset, trimWidth - (safeInset * 2), trimHeight - (safeInset * 2)),
    spineSafe: rect("Spine red safe area", bleed + trimWidth + spineSafeInset, bleed + safeInset, Math.max(0, spine - (spineSafeInset * 2)), trimHeight - (safeInset * 2)),
    frontSafe: rect("Front cover red safe area", bleed + trimWidth + spine + safeInset, bleed + safeInset, trimWidth - (safeInset * 2), trimHeight - (safeInset * 2)),
    barcodeBox: rect("KDP barcode box", bleed + trimWidth - barcodeInset - barcodeWidth, bleed + trimHeight - barcodeInset - barcodeHeight, barcodeWidth, barcodeHeight)
  };
}

function renderKdpPdfParameters(report) {
  const panel = $("#kdp-pdf-parameters");
  if (!panel) {
    return;
  }
  if (!report) {
    panel.innerHTML = "";
    return;
  }
  const map = report.coordinateMap || buildClientKdpCoordinateMapFromReport(report);
  const dpi = Number(report.requiredResolution?.dpi || map?.dpi || 300);
  const fullCoverPixelWidth = Number(report.requiredResolution?.fullCoverPixelWidth || Math.ceil((report.spec?.expectedWidthIn || report.pdf?.widthIn || 0) * dpi));
  const fullCoverPixelHeight = Number(report.requiredResolution?.fullCoverPixelHeight || Math.ceil((report.spec?.expectedHeightIn || report.pdf?.heightIn || 0) * dpi));
  const largestImage = report.pdf?.largestImage || null;
  const imageLine = largestImage
    ? `${largestImage.pixelWidth} x ${largestImage.pixelHeight} px · full-page ${largestImage.ifFullPageDpiX} x ${largestImage.ifFullPageDpiY} DPI`
    : "未解析到内嵌位图尺寸，需检查导出源文件";
  const rects = map ? [
    map.fullCover,
    map.trimBox,
    map.backCover,
    map.spine,
    map.frontCover,
    map.backSafe,
    map.spineSafe,
    map.frontSafe,
    map.barcodeBox
  ] : [];

  panel.innerHTML = `
    <div class="kdp-param-card">
      <div class="kdp-param-title">提交 PDF 参数</div>
      <div class="kdp-param-row">
        <span>PDF 外尺寸</span>
        <strong>${escapeHtml(formatDimensionPair(report.pdf?.widthIn || 0, report.pdf?.heightIn || 0))}</strong>
        <em>页面框：${escapeHtml(report.pdf?.boxType || "-")} · 页数：${escapeHtml(report.pdf?.pageCount || "-")}</em>
      </div>
      <div class="kdp-param-row">
        <span>DPI / 像素基准</span>
        <strong>${escapeHtml(fullCoverPixelWidth || "-")} x ${escapeHtml(fullCoverPixelHeight || "-")} px @ ${escapeHtml(dpi)} DPI</strong>
        <em>最大内嵌图：${escapeHtml(imageLine)}</em>
      </div>
    </div>
    <div class="kdp-param-card">
      <div class="kdp-param-title">区域坐标（原点：PDF 左上角）</div>
      <div class="kdp-param-table-wrap">
        <table class="kdp-param-table">
          <thead>
            <tr>
              <th>区域</th>
              <th>x px</th>
              <th>y px</th>
              <th>w px</th>
              <th>h px</th>
              <th>x in</th>
              <th>y in</th>
              <th>w in</th>
              <th>h in</th>
              <th>x mm</th>
              <th>y mm</th>
              <th>w mm</th>
              <th>h mm</th>
            </tr>
          </thead>
          <tbody>${rects.map(formatKdpRectLine).join("")}</tbody>
        </table>
      </div>
    </div>
  `;
}

function renderKdpAcceptancePanel(item, acceptance) {
  const summary = $("#kdp-acceptance-summary");
  const checksPanel = $("#kdp-acceptance-checks");
  const reportField = $("#kdp-acceptance-report");
  const meta = $("#kdp-pdf-meta");
  if (!summary || !checksPanel || !reportField) {
    return;
  }
  updateKdpGuidePreview();

  if (!item) {
    summary.textContent = "选择一个 BookName 后，可以提交 KDP 封面 PDF 做验收。";
    checksPanel.innerHTML = "";
    reportField.value = "提交 PDF 后，这里会显示 KDP 验收报告。";
    renderKdpSavedFixReport(null);
    renderKdpFixWorkbench({});
    renderKdpAcceptanceFileList([]);
    renderKdpPdfParameters(null);
    clearKdpPdfViewer();
    renderKdpCurrentFileMeta();
    return;
  }

  const currentSource = acceptance?.currentSource || null;
  if (currentSource) {
    setKdpSourceMetadata(currentSource);
  }

  if (state.kdpAcceptanceFile) {
    const selectedType = getKdpFileTypeLabel(state.kdpAcceptanceFile.name, state.kdpAcceptanceFile.type === "image/png" ? "PNG" : "");
    renderKdpCurrentFileMeta({
      status: "已选择本地文件，等待提交/加载。",
      type: selectedType || "PDF",
      fileName: state.kdpAcceptanceFile.name,
      path: "local upload",
      detail: formatFileSize(state.kdpAcceptanceFile.size)
    });
  } else if (currentSource || meta) {
    renderKdpCurrentSourceMeta();
  }

  const report = acceptance?.report || null;
  renderKdpSavedFixReport(acceptance);
  renderKdpFixWorkbench(acceptance?.fixWorkbench || {});
  if (!report) {
    summary.textContent = "当前项目还没有 KDP 验收报告。";
    checksPanel.innerHTML = "";
    reportField.value = acceptance?.reportText || "提交 PDF 后，这里会显示 KDP 验收报告。";
    renderKdpPdfParameters(null);
    if (currentSource && getKdpFileTypeLabel(currentSource.fileName || currentSource.relativePath, currentSource.type) === "PNG") {
      const sourcePath = getKdpSourceAcceptanceRelativePath(currentSource);
      if (sourcePath) {
        loadKdpImageViewer(
          `/api/kdp-acceptance-file?bookName=${encodeURIComponent(item.bookName)}&fileName=${encodeURIComponent(sourcePath)}&t=${Date.now()}`,
          getCurrentKdpGuideSpec(),
          acceptance?.llmTextRegions?.latest || null
        );
      }
    } else {
      clearKdpPdfViewer();
    }
    return;
  }

  setKdpFieldValue("#kdp-trim-width", report.spec?.trimWidthIn);
  setKdpFieldValue("#kdp-trim-height", report.spec?.trimHeightIn);
  setKdpFieldValue("#kdp-page-count", report.spec?.pageCount);
  setKdpFieldValue("#kdp-bleed", report.spec?.bleedIn);
  const paperField = $("#kdp-paper-type");
  if (paperField && report.spec?.paperType) {
    paperField.value = report.spec.paperType;
  }
  const reportSpec = {
    trimWidth: Number(report.spec?.trimWidthIn || 6),
    trimHeight: Number(report.spec?.trimHeightIn || 9),
    bleed: Number(report.spec?.bleedIn || 0.125),
    spine: Number(report.spec?.spineWidthIn || 0.27),
    width: Number(report.spec?.expectedWidthIn || 12.52),
    height: Number(report.spec?.expectedHeightIn || 9.25),
    whiteWidth: (Number(report.spec?.trimWidthIn || 6) * 2) + Number(report.spec?.spineWidthIn || 0.27),
    whiteHeight: Number(report.spec?.trimHeightIn || 9),
    frontBackSafeWidth: Number(report.spec?.trimWidthIn || 6) - 0.25,
    frontBackSafeHeight: Number(report.spec?.trimHeightIn || 9) - 0.25,
    spineSafeWidth: Math.max(0, Number(report.spec?.spineWidthIn || 0.27) - 0.125),
    spineSafeHeight: Number(report.spec?.trimHeightIn || 9) - 0.25,
    frontBackSafeInsetFromTrim: 0.125,
    spineSafeInset: 0.0625,
    barcodeWidth: 2,
    barcodeHeight: 1.2,
    barcodeInset: 0.25
  };
  updateKdpGuidePreview(reportSpec);

  const verdict = report.verdict || "";
  summary.dataset.verdict = verdict;
  summary.textContent =
    `结论：${getKdpVerdictText(verdict)} · ` +
    `PDF ${report.pdf?.widthIn || "-"} x ${report.pdf?.heightIn || "-"} in · ` +
    `KDP 目标 ${report.spec?.expectedWidthIn || "-"} x ${report.spec?.expectedHeightIn || "-"} in`;

  checksPanel.innerHTML = (report.checks || []).map((check) => `
    <div class="kdp-check-item ${escapeHtml(check.status || "info")}">
      <span>${escapeHtml(getKdpCheckText(check.status))}</span>
      <strong>${escapeHtml(check.title || "")}</strong>
      <em>${escapeHtml(check.detail || "")}</em>
    </div>
  `).join("");

  renderKdpPdfParameters(report);
  reportField.value = acceptance?.reportText || "";
  if (currentSource && getKdpFileTypeLabel(currentSource.fileName || currentSource.relativePath, currentSource.type) === "PNG") {
    const sourcePath = getKdpSourceAcceptanceRelativePath(currentSource);
    summary.dataset.verdict = "review";
    summary.textContent = "当前工作对象是 PNG，PDF 技术验收结果仅作历史参考；后续识别/报告/修图会使用这个 PNG。";
    checksPanel.innerHTML = `
      <div class="kdp-check-item review">
        <span>${escapeHtml(getKdpCheckText("review"))}</span>
        <strong>Current source is PNG</strong>
        <em>当前文件来自 ${escapeHtml(currentSource.relativePath || sourcePath || currentSource.fileName || "PNG")}。</em>
      </div>
    `;
    if (sourcePath) {
      loadKdpImageViewer(
        `/api/kdp-acceptance-file?bookName=${encodeURIComponent(item.bookName)}&fileName=${encodeURIComponent(sourcePath)}&t=${Date.now()}`,
        reportSpec,
        acceptance?.llmTextRegions?.latest || null
      );
    }
    return;
  }
  if (report.pdfFileName && (!currentSource || getKdpFileTypeLabel(currentSource.fileName || currentSource.relativePath, currentSource.type) === "PDF")) {
    setKdpSourceMetadata(getKdpAcceptanceSourceMetadata(report.pdfFileName, "PDF"));
    renderKdpCurrentSourceMeta("PDF 已加载，当前走 KDP 技术验收。");
    loadKdpPdfViewer(
      `/api/kdp-acceptance-pdf?bookName=${encodeURIComponent(item.bookName)}&fileName=${encodeURIComponent(report.pdfFileName)}&t=${Date.now()}`,
      reportSpec,
      acceptance?.llmTextRegions?.latest || null
    );
  }
}

function renderKdpPngInspectionState({ fileName = "", fileSize = "" } = {}) {
  const summary = $("#kdp-acceptance-summary");
  const checksPanel = $("#kdp-acceptance-checks");
  const reportField = $("#kdp-acceptance-report");
  const source = state.kdpPdf.source || {};
  const displayFileName = source.fileName || fileName || source.originalFileName || "";
  const displayType = getKdpFileTypeLabel(displayFileName || source.relativePath, source.type) || "PNG";
  renderKdpCurrentFileMeta({
    status: `${displayType} 已加载，当前走视觉检查/修图流程。`,
    type: displayType,
    fileName: displayFileName,
    path: source.relativePath || source.directory || source.origin || "local upload",
    detail: fileSize || (source.originalFileName && source.originalFileName !== source.fileName ? `原始上传文件名：${source.originalFileName}` : "")
  });
  if (summary) {
    summary.dataset.verdict = "review";
    summary.textContent = "PNG 检视模式：PDF MediaBox、加密、页数等技术验收项不适用于 PNG。请继续做文字区域识别和修图检查。";
  }
  if (checksPanel) {
    checksPanel.innerHTML = `
      <div class="kdp-check-item info">
        <span>${escapeHtml(getKdpCheckText("info"))}</span>
        <strong>PNG file loaded for visual inspection</strong>
        <em>当前对象是 PNG，走自定义 KDP 检视器、LLM 文字区域识别、修改报告和修图流程。</em>
      </div>
      <div class="kdp-check-item review">
        <span>${escapeHtml(getKdpCheckText("review"))}</span>
        <strong>PDF technical checks skipped</strong>
        <em>PDF 加密、页数、MediaBox、PDF 外尺寸检查只在提交 PDF 时有效；PNG 需要在修图后重新包装/导出为 PDF 再验收。</em>
      </div>
    `;
  }
  renderKdpPdfParameters(null);
  if (reportField) {
    reportField.value = [
      "# KDP PNG inspection flow",
      "",
      fileName ? `- File: ${fileName}` : "- File: PNG image",
      fileSize ? `- Size: ${fileSize}` : "",
      "- Flow: PNG viewer -> LLM text-region detection -> fix report -> image edit -> submit fixed output.",
      "- Note: PNG does not contain PDF MediaBox/page metadata, so PDF technical acceptance checks are skipped until it is wrapped/exported back to PDF."
    ].filter(Boolean).join("\n");
  }
}

async function submitKdpAcceptancePdf() {
  const bookName = requireBookName();
  const file = state.kdpAcceptanceFile || $("#kdp-pdf-file")?.files?.[0] || null;
  if (!file) {
    throw new Error("请先选择一个 KDP 封面 PDF 或 PNG。");
  }
  const fileType = getKdpFileTypeLabel(file.name, file.type === "image/png" ? "PNG" : "");
  if (fileType === "PNG") {
    await submitKdpAcceptancePng(file);
    return;
  }
  if (fileType !== "PDF") {
    throw new Error("KDP 验收工具目前只接受 PDF 或 PNG。");
  }

  const dataUrl = await readFileAsDataUrl(file);
  const result = await api("/api/kdp-acceptance", {
    method: "POST",
    body: JSON.stringify({
      bookName,
      fileName: file.name,
      dataUrl,
      trimWidthIn: Number($("#kdp-trim-width")?.value || 6),
      trimHeightIn: Number($("#kdp-trim-height")?.value || 9),
      pageCount: Number($("#kdp-page-count")?.value || 120),
      paperType: $("#kdp-paper-type")?.value || "bw-white",
      bleedIn: Number($("#kdp-bleed")?.value || 0.125)
    })
  });

  const selected = getSelectedWorkspaceItem();
  const currentArtifacts = state.coverCache[bookName] || selected?.coverArtifacts || {};
  if (result.kdpAcceptance?.currentSource || result.kdpAcceptance?.report?.pdfFileName) {
    setKdpSourceMetadata(result.kdpAcceptance?.currentSource || {
      ...getKdpAcceptanceSourceMetadata(result.kdpAcceptance.report.pdfFileName, "PDF"),
      originalFileName: file.name
    });
    renderKdpCurrentSourceMeta("PDF 已提交并保存到验收目录。");
  }
  state.kdpAcceptanceFile = null;
  if ($("#kdp-pdf-file")) $("#kdp-pdf-file").value = "";
  state.coverCache[bookName] = {
    ...currentArtifacts,
    kdpAcceptance: result.kdpAcceptance || null
  };
  renderCoverPanel(selected || null);
  setStatusBadge("验收完成", "success");
  setLog(`KDP 验收完成：${getKdpVerdictText(result.kdpAcceptance?.report?.verdict)}`);
}

async function submitKdpAcceptancePng(file) {
  const bookName = requireBookName();
  const dataUrl = await readFileAsDataUrl(file);
  const spec = getCurrentKdpGuideSpec();
  updateKdpGuidePreview(spec);
  const result = await api("/api/kdp-acceptance-png", {
    method: "POST",
    body: JSON.stringify({
      bookName,
      fileName: file.name,
      dataUrl
    })
  });
  setKdpSourceMetadata(result.currentSource || result.kdpAcceptance?.currentSource || {
    ...getKdpAcceptanceSourceMetadata(result.fileName || file.name, "PNG"),
    originalFileName: file.name
  });
  state.kdpAcceptanceFile = null;
  if ($("#kdp-pdf-file")) $("#kdp-pdf-file").value = "";
  await loadKdpImageViewer(result.fileUrl || dataUrl, spec, null);
  const selected = getSelectedWorkspaceItem();
  if (selected) {
    const currentArtifacts = state.coverCache[bookName] || selected.coverArtifacts || {};
    state.coverCache[bookName] = {
      ...currentArtifacts,
      kdpAcceptance: result.kdpAcceptance || currentArtifacts.kdpAcceptance || null
    };
  }
  renderKdpPngInspectionState({ fileName: result.fileName || file.name, fileSize: formatFileSize(file.size) });
  setStatusBadge("PNG已加载", "success");
  setLog(`PNG 已保存并加载为当前工作对象：${result.fileName || file.name}`);
}

function getSelectedChapterFileName() {
  const select = $("#chapter-preview-select");
  return select ? select.value : "";
}

function updateChapterSaveState() {
  const saveButton = $("#save-chapter");
  const panel = $("#chapter-preview");
  const bookName = getBookName();
  const fileName = getSelectedChapterFileName();

  if (!saveButton || !panel || !bookName || !fileName) {
    if (saveButton) {
      saveButton.classList.remove("attention");
      saveButton.textContent = "保存章节";
      saveButton.disabled = !fileName;
    }
    return;
  }

  const cacheKey = `${bookName}:${fileName}`;
  const savedContent = state.chapterContentCache[cacheKey];
  const currentContent = panel.value || "";
  const isDirty = typeof savedContent === "string" && currentContent !== savedContent;

  saveButton.disabled = false;
  saveButton.classList.toggle("attention", isDirty);
  saveButton.textContent = isDirty ? "保存章节（未保存）" : "保存章节";
}

function getSelectedChapterNumber(item) {
  if (!item) {
    return null;
  }

  const fileName = getSelectedChapterFileName();
  if (!fileName) {
    return null;
  }

  const chapterList = state.chapterListCache[item.bookName] || item.chapterFiles || [];
  const chapter = chapterList.find((entry) => entry.fileName === fileName);
  if (!chapter) {
    return null;
  }

  return Number(chapter.chapterIndex || Number.parseInt(fileName, 10) || 0) || null;
}

function jumpToRewriteCurrentChapter() {
  const selected = state.workspaces.find((item) => item.bookName === getBookName());
  const chapterNumber = getSelectedChapterNumber(selected || null);

  if (!selected || !chapterNumber) {
    setStatusBadge("失败", "failed");
    setLog("请先在章节浏览里选中一章，再使用“重写这一章”。");
    return;
  }

  const modeField = $('#write-form [name="mode"]');
  const chapterField = $('#write-form [name="chapter"]');
  const startField = $('#write-form [name="startChapter"]');
  const endField = $('#write-form [name="endChapter"]');
  const forceField = $('#write-form [name="force"]');

  if (modeField) {
    modeField.value = "chapter";
  }
  if (chapterField) {
    chapterField.value = String(chapterNumber);
  }
  if (startField) {
    startField.value = "";
  }
  if (endField) {
    endField.value = "";
  }
  if (forceField) {
    forceField.checked = true;
  }

  const writeForm = $("#write-form");
  if (writeForm) {
    writeForm.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  setStatusBadge("已定位", "success");
  setLog(`已切换到单章重写模式：第 ${chapterNumber} 章。你现在可以直接点“附加说明”，或者直接运行 03-write.ps1。`);
}

function updateChapterNavButtons(item, chapterList) {
  const prevButton = $("#chapter-prev");
  const nextButton = $("#chapter-next");
  const currentValue = getSelectedChapterFileName();

  if (!prevButton || !nextButton) {
    return;
  }

  if (!item || !chapterList.length || !currentValue) {
    prevButton.disabled = true;
    nextButton.disabled = true;
    return;
  }

  const currentIndex = chapterList.findIndex((chapter) => chapter.fileName === currentValue);
  prevButton.disabled = currentIndex <= 0;
  nextButton.disabled = currentIndex < 0 || currentIndex >= chapterList.length - 1;
}

function selectRelativeChapter(offset, item) {
  if (!item) {
    return;
  }

  const select = $("#chapter-preview-select");
  const chapterList = state.chapterListCache[item.bookName] || item.chapterFiles || [];
  if (!select || !chapterList.length) {
    return;
  }

  const currentIndex = chapterList.findIndex((chapter) => chapter.fileName === select.value);
  if (currentIndex < 0) {
    return;
  }

  const nextIndex = currentIndex + offset;
  if (nextIndex < 0 || nextIndex >= chapterList.length) {
    return;
  }

  select.value = chapterList[nextIndex].fileName;
  updateChapterNavButtons(item, chapterList);
  showCurrentChapter().catch((error) => {
    setStatusBadge("失败", "failed");
    setLog(error.message);
  });
}

function renderChapterBrowser(item) {
  const select = $("#chapter-preview-select");
  const panel = $("#chapter-preview");

  if (!select || !panel) {
    return;
  }

  if (!item) {
    select.innerHTML = '<option value="">请选择章节</option>';
    panel.value = "选中一个已有章节的 BookName 后，这里会显示章节内容。";
    updateChapterNavButtons(null, []);
    updateChapterSaveState();
    return;
  }

  const chapterList = state.chapterListCache[item.bookName] || item.chapterFiles || [];
  const currentValue = getSelectedChapterFileName();

  select.innerHTML = "";
  if (!chapterList.length) {
    const option = document.createElement("option");
    option.value = "";
    option.textContent = state.chapterListLoadingBook === item.bookName
      ? "正在读取章节列表..."
      : "当前项目还没有可浏览的章节";
    select.appendChild(option);
    panel.value = "当前项目还没有生成可预览的章节内容。";
    if (state.chapterListLoadingBook !== item.bookName && !state.chapterListCache[item.bookName]) {
      loadChapterList(item);
    }
    updateChapterNavButtons(item, []);
    updateChapterSaveState();
    return;
  }

  const placeholder = document.createElement("option");
  placeholder.value = "";
  placeholder.textContent = "请选择章节";
  select.appendChild(placeholder);

  chapterList.forEach((chapter) => {
    const option = document.createElement("option");
    option.value = chapter.fileName;
    option.textContent = `${chapter.fileName} · ${chapter.title || chapter.fileName}`;
    select.appendChild(option);
  });

  const effectiveValue = chapterList.some((chapter) => chapter.fileName === currentValue)
    ? currentValue
    : chapterList[0].fileName;
  select.value = effectiveValue;
  updateChapterNavButtons(item, chapterList);

  const contentKey = `${item.bookName}:${effectiveValue}`;
  const cachedContent = effectiveValue ? state.chapterContentCache[contentKey] : "";

  if (!effectiveValue) {
    panel.value = "请选择一个章节后再查看内容。";
    updateChapterSaveState();
    return;
  }

  if (cachedContent) {
    panel.value = cachedContent;
    updateChapterSaveState();
    return;
  }

  panel.value = state.chapterContentLoadingKey === contentKey
    ? "正在读取章节内容，请稍候..."
    : "点“显示章节”后，这里会显示对应章节的正文。";
  updateChapterSaveState();
}

async function loadChapterList(item) {
  if (!item) {
    return;
  }

  state.chapterListLoadingBook = item.bookName;
  renderChapterBrowser(item);

  try {
    const result = await api(`/api/chapters?bookName=${encodeURIComponent(item.bookName)}`);
    state.chapterListCache[item.bookName] = Array.isArray(result.chapters) ? result.chapters : [];
  } catch (error) {
    state.chapterListCache[item.bookName] = [];
    const panel = $("#chapter-preview");
    if (panel) {
      panel.value = `读取章节列表失败：${error.message}`;
      updateChapterSaveState();
    }
  } finally {
    state.chapterListLoadingBook = "";
    renderChapterBrowser(item);
  }
}

async function showCurrentChapter() {
  const panel = $("#chapter-preview");
  const bookName = requireBookName();
  const fileName = getSelectedChapterFileName();

  if (!fileName) {
    panel.value = "请先选择一个章节。";
    return;
  }

  const cacheKey = `${bookName}:${fileName}`;
  state.chapterContentLoadingKey = cacheKey;
  panel.value = "正在读取章节内容，请稍候...";

  try {
    const result = await api(`/api/chapter?bookName=${encodeURIComponent(bookName)}&fileName=${encodeURIComponent(fileName)}`);
    state.chapterContentCache[cacheKey] = result.content || "当前章节没有可显示的内容。";
    panel.value = state.chapterContentCache[cacheKey];
  } catch (error) {
    panel.value = `读取章节失败：${error.message}`;
  } finally {
    state.chapterContentLoadingKey = "";
    updateChapterSaveState();
  }
}

async function saveCurrentChapter() {
  const panel = $("#chapter-preview");
  const bookName = requireBookName();
  const fileName = getSelectedChapterFileName();

  if (!fileName) {
    throw new Error("请先选择一个章节。");
  }

  const content = panel.value || "";
  const result = await api("/api/chapter", {
    method: "POST",
    body: JSON.stringify({
      bookName,
      fileName,
      content
    })
  });

  const cacheKey = `${bookName}:${fileName}`;
  state.chapterContentCache[cacheKey] = result.content || content;
  panel.value = state.chapterContentCache[cacheKey];
  updateChapterSaveState();
  setStatusBadge("已保存", "success");
  setLog(`章节已保存到 ${bookName} 的 ${fileName}`);
}

async function loadPreflightReport(item) {
  if (!item) {
    return;
  }

  state.preflightLoadingBook = item.bookName;
  renderPreflightReport(item);

  try {
    const result = await api(`/api/edit-report?bookName=${encodeURIComponent(item.bookName)}&t=${Date.now()}`);
    state.preflightCache[item.bookName] = {
      reportText: result.reportText || "",
      reportJson: result.reportJson || item.editReport || null
    };
  } catch (error) {
    state.preflightCache[item.bookName] = {
      reportText: `读取检查报告失败：${error.message}`,
      reportJson: item.editReport || null
    };
  } finally {
    state.preflightLoadingBook = "";
    renderPreflightReport(item);
  }
}

async function showCurrentTocPreview() {
  const panel = $("#toc-preview");
  const bookName = requireBookName();
  panel.value = "正在读取目录，请稍候...";

  try {
    const result = await api(`/api/toc?bookName=${encodeURIComponent(bookName)}`);
    panel.value = result.tocContent || "当前项目还没有可显示的目录内容。";

    const selected = state.workspaces.find((item) => item.bookName === bookName);
    if (selected) {
      selected.hasToc = true;
      selected.tocContent = result.tocContent || "";
    }
  } catch (error) {
    panel.value = error.message === "toc.md not found."
      ? "当前项目还没有生成 toc.md。"
      : error.message === "Not found"
        ? "当前浏览器连接的还是旧版 Web 服务。请关闭并重新启动 SageWrite Web UI 后再试。"
        : `读取目录失败：${error.message}`;
  }
}

async function saveCurrentToc() {
  const panel = $("#toc-preview");
  const bookName = requireBookName();
  const tocContent = panel.value || "";

  await api("/api/toc", {
    method: "POST",
    body: JSON.stringify({
      bookName,
      tocContent
    })
  });

  const selected = state.workspaces.find((item) => item.bookName === bookName);
  if (selected) {
    selected.hasToc = true;
    selected.tocContent = tocContent;
  }

  setStatusBadge("已保存", "success");
  setLog(`目录已保存到 ${bookName} 的 toc.md`);
}

function renderRunDetail(item, selectedRun) {
  if (!selectedRun) {
    return '<div class="run-detail-empty">还没有可查看的运行详情。</div>';
  }

  const detailJson = escapeHtml(JSON.stringify(selectedRun.data || {}, null, 2));
  const outputFileName = selectedRun?.data?.outputFileName || "";
  const outputCacheKey = outputFileName ? `${item.bookName}:${outputFileName}` : "";
  const outputText = outputFileName ? state.runOutputCache[outputCacheKey] : "";
  const isOutputLoading = outputCacheKey && state.runOutputLoadingKey === outputCacheKey;

  return `
    <div class="run-detail-header">
      <strong>${escapeHtml(selectedRun.step || "-")}</strong>
      <span>${escapeHtml(selectedRun.state || "-")}</span>
    </div>
    <div class="run-detail-meta">${escapeHtml(selectedRun.timestamp || selectedRun.time || "-")}</div>
    <div class="run-detail-message">${escapeHtml(selectedRun.message || "无附加说明")}</div>
    <details class="run-detail-section">
      <summary>运行数据 JSON</summary>
      <pre class="run-detail-data">${detailJson}</pre>
    </details>
    <div class="run-output-block">
      <div class="run-output-title">完整终端输出</div>
      ${
        outputFileName
          ? `<pre class="run-detail-output">${
            isOutputLoading
              ? "正在读取归档输出..."
              : escapeHtml(outputText || "暂时还没有读取到归档输出。")
          }</pre>`
          : '<div class="run-detail-empty">这条记录没有归档完整终端输出。</div>'
      }
    </div>
  `;
}

function renderProjectStatus(item) {
  const panel = $("#project-status");

  if (!item) {
    panel.innerHTML = '<div class="status-empty">选择一个 BookName 后，这里会显示项目状态。</div>';
    return;
  }

  const recentRuns = item.recentRuns || [];
  const status = item.status || {};
  const lastRun = status.last_run || recentRuns[recentRuns.length - 1] || {};
  const lastError = status.last_error || {};
  const current = status.current || {};
  const selectedRun = recentRuns.find((run) => {
    const key = `${run.timestamp || run.time || ""}-${run.step || ""}-${run.source || "engine"}`;
    return key === state.selectedRunKey;
  }) || recentRuns[recentRuns.length - 1] || null;

  if (selectedRun) {
    state.selectedRunKey = `${selectedRun.timestamp || selectedRun.time || ""}-${selectedRun.step || ""}-${selectedRun.source || "engine"}`;
  }

  panel.innerHTML = `
    <div class="status-item">
      <span>工作区路径</span>
      <strong>${escapeHtml(item.workspacePath)}</strong>
    </div>
    <div class="status-item">
      <span>当前状态</span>
      <strong>${current.step ? `${escapeHtml(current.step)} / ${escapeHtml(current.state)}` : "暂无运行"}</strong>
    </div>
    <div class="status-item">
      <span>最近一次运行</span>
      <strong>${lastRun.step ? `${escapeHtml(lastRun.step)} / ${escapeHtml(lastRun.state || "-")}` : "暂无"}</strong>
      <em>${escapeHtml(lastRun.message || "")}</em>
    </div>
    <div class="status-item">
      <span>最近一次错误</span>
      <strong>${lastError.step ? escapeHtml(lastError.step) : "无"}</strong>
      <em>${escapeHtml(lastError.message || "")}</em>
    </div>
    <div class="status-item">
      <span>目录文件</span>
      <strong>${item.hasToc ? "toc.md 已生成" : "toc.md 未生成"}</strong>
      <em>${item.hasExpandedToc ? "toc2.md 已生成" : "toc2.md 未生成"}</em>
    </div>
    <div class="status-item">
      <span>章节和输出</span>
      <strong>${item.chapterCount || 0} 个章节文件</strong>
      <em>${item.outputFiles.length || 0} 个输出文档 · ${(item.publishLanguages || []).length} 个上架语言包</em>
    </div>
    <div class="status-item wide">
      <span>最近运行记录</span>
      <strong>${recentRuns.length ? "" : "暂无记录"}</strong>
      <div class="run-browser">
        <div class="run-list">
          ${recentRuns.map((run) => {
            const runKey = `${run.timestamp || run.time || ""}-${run.step || ""}-${run.source || "engine"}`;
            const active = selectedRun && runKey === state.selectedRunKey;
            return `
              <button
                type="button"
                class="run-item ${active ? "active" : ""}"
                data-run-key="${escapeHtml(runKey)}"
              >
                <b>${escapeHtml(run.timestamp || run.time || "-")}</b>
                <span>${escapeHtml(run.step || "-")} / ${escapeHtml(run.state || "-")}</span>
                <em>${escapeHtml(run.message || "")}</em>
              </button>
            `;
          }).join("")}
        </div>
        <div class="run-detail">
          ${renderRunDetail(item, selectedRun)}
        </div>
      </div>
    </div>
  `;

  panel.querySelectorAll("[data-run-key]").forEach((button) => {
    button.addEventListener("click", () => {
      state.selectedRunKey = button.dataset.runKey || "";
      renderProjectStatus(item);
    });
  });

  const outputFileName = selectedRun?.data?.outputFileName || "";
  const outputCacheKey = outputFileName ? `${item.bookName}:${outputFileName}` : "";
  if (selectedRun && outputFileName && !state.runOutputCache[outputCacheKey] && state.runOutputLoadingKey !== outputCacheKey) {
    loadRunOutput(item.bookName, outputFileName, item);
  }
}

function getNextProjectStep(item) {
  if (!item) {
    return "先选择项目";
  }
  if (!item.hasToc) {
    return "运行 02 生成目录";
  }
  if (!item.hasExpandedToc) {
    return "运行 02b 扩展小节";
  }
  if (!item.chapterCount) {
    return "运行 03 写章节";
  }
  if (!(item.outputFiles || []).length) {
    return "运行 05 构建文档";
  }
  if (!(item.publishLanguages || []).length) {
    return "运行 09 生成上架包";
  }
  return "审校上架材料";
}

function renderProjectSummary(item) {
  const title = $("#project-summary-title");
  const meta = $("#project-summary-meta");
  const current = $("#project-summary-current");
  const toc = $("#project-summary-toc");
  const output = $("#project-summary-output");
  const next = $("#project-summary-next");

  if (!title || !meta || !current || !toc || !output || !next) {
    return;
  }

  if (!item) {
    title.textContent = "尚未选择项目";
    meta.textContent = "选择一个 BookName 后，这里会显示当前项目的关键进度。";
    current.textContent = "暂无运行";
    toc.textContent = "未选择";
    output.textContent = "-";
    next.textContent = "先选择项目";
    return;
  }

  const recentRuns = item.recentRuns || [];
  const status = item.status || {};
  const currentStatus = status.current || {};
  const lastRun = status.last_run || recentRuns[recentRuns.length - 1] || {};
  const outputLanguages = item.outputLanguages || [];
  const publishLanguages = item.publishLanguages || [];

  title.textContent = item.bookName || "未命名项目";
  meta.textContent = item.workspacePath || "当前项目没有可显示的工作区路径。";
  current.textContent = currentStatus.step
    ? `${currentStatus.step} / ${currentStatus.state || "-"}`
    : lastRun.step
      ? `${lastRun.step} / ${lastRun.state || "-"}`
      : "暂无运行";
  toc.textContent = `${item.hasToc ? "toc.md" : "未生成目录"} / ${item.hasExpandedToc ? "toc2.md" : "未扩展"}`;
  output.textContent = `${item.chapterCount || 0} 章 · ${(item.outputFiles || []).length} 输出 · ${outputLanguages.length ? outputLanguages.join(", ") : "无输出语言"}`;
  next.textContent = `${getNextProjectStep(item)}${publishLanguages.length ? ` · 已有上架语言 ${publishLanguages.join(", ")}` : ""}`;
}

async function loadRunOutput(bookName, fileName, item) {
  const cacheKey = `${bookName}:${fileName}`;
  state.runOutputLoadingKey = cacheKey;
  renderProjectStatus(item);

  try {
    const result = await api(`/api/run-output?bookName=${encodeURIComponent(bookName)}&fileName=${encodeURIComponent(fileName)}`);
    state.runOutputCache[cacheKey] = result.content || "";
  } catch (error) {
    state.runOutputCache[cacheKey] = `[加载失败] ${error.message}`;
  } finally {
    state.runOutputLoadingKey = "";
    renderProjectStatus(item);
  }
}

function renderBuildOutputs(item) {
  const panel = $("#build-output-list");
  if (!panel) {
    return;
  }

  if (!item) {
    panel.innerHTML = '<div class="build-output-empty">选择一个 BookName 后，这里会显示生成的 DOCX / EPUB / PDF 文件。</div>';
    return;
  }

  const outputFiles = item.outputFiles || [];
  if (!outputFiles.length) {
    panel.innerHTML = '<div class="build-output-empty">当前项目还没有生成可查看的 DOCX / EPUB / PDF 文件。</div>';
    return;
  }

  const getFolderLabel = (folderKey) => {
    if (!folderKey) {
      return "位于 04_output 目录";
    }
    return `位于 04_output/${escapeHtml(folderKey)} 目录`;
  };

  const groups = new Map();
  outputFiles.forEach((fileName) => {
    const normalized = String(fileName || "").replaceAll("\\", "/");
    const parts = normalized.split("/");
    const folderKey = parts.length <= 1 ? "" : parts.slice(0, -1).join("/");
    const baseName = parts.at(-1) || normalized;
    if (!groups.has(folderKey)) {
      groups.set(folderKey, []);
    }
    groups.get(folderKey).push({
      originalPath: fileName,
      baseName
    });
  });

  const groupedRows = Array.from(groups.entries())
    .sort(([left], [right]) => left.localeCompare(right, "zh-Hans-CN"))
    .map(([folderKey, files]) => {
      const sortedFiles = files.sort((left, right) => left.baseName.localeCompare(right.baseName, "zh-Hans-CN"));
      return `
    <div class="build-output-item">
      <div class="build-output-meta">
        <strong>${sortedFiles.map((entry) => escapeHtml(entry.baseName)).join(" · ")}</strong>
        <span>${getFolderLabel(folderKey)}</span>
      </div>
      <button class="ghost-button build-open-button" type="button" data-output-folder-file="${escapeHtml(sortedFiles[0].originalPath)}">打开生成文件夹</button>
    </div>`;
    });

  panel.innerHTML = groupedRows.join("");
}

async function loadPublishArtifacts(item, language = getPublishLanguage()) {
  if (!item) {
    return;
  }

  const cacheKey = `${item.bookName}:${language}`;
  state.publishLoadingKey = cacheKey;
  renderPublishPanel(item);

  try {
    const result = await api(`/api/publish?bookName=${encodeURIComponent(item.bookName)}&language=${encodeURIComponent(language)}&t=${Date.now()}`);
    state.publishCache[cacheKey] = result.publish || null;
  } catch (error) {
    state.publishCache[cacheKey] = {
      exists: false,
      language,
      availableLanguages: [],
      root: "",
      rootFiles: [],
      metadataMarkdown: `读取上架数据失败：${error.message}`,
      reportText: "",
      platforms: {}
    };
  } finally {
    state.publishLoadingKey = "";
    renderPublishPanel(item);
  }
}

function formatPublishSourceSummary(item, publish, language) {
  if (!item || !publish?.metadataJson) {
    return "选择一个 BookName 后，这里会显示当前语言版本的生成来源、输出文件和发布目录。";
  }

  const metadata = publish.metadataJson || {};
  const sourceFiles = metadata.source_files || {};
  const sourceLines = [
    `当前语种：${getLanguageLabel(language)}（${language}）`,
    `04 输出来源：${sourceFiles.epub || sourceFiles.pdf || sourceFiles.docx || "尚未生成"}`,
    `封面来源：${sourceFiles.cover || "尚未生成"}`,
    `09 发布目录：${publish.root || `09_publish/${language}`}`,
    `平台包目录：${Object.entries(publish.platforms || {}).filter(([, data]) => data?.exists).map(([name]) => name).join(" / ") || "尚未生成"}`
  ];

  return sourceLines.map((line) => `<div>${escapeHtml(line)}</div>`).join("");
}

function renderPublishOpenPaths(item, publish, language = getPublishLanguage(), platform = getPublishPreviewPlatform()) {
  const rootPanel = $("#publish-root-path");
  const platformPanel = $("#publish-platform-path");
  if (!rootPanel || !platformPanel) {
    return;
  }

  if (!item) {
    rootPanel.textContent = "选择一个 BookName 后，这里会显示语言目录的真实路径。";
    platformPanel.textContent = "选择平台后，这里会显示平台目录的真实路径。";
    rootPanel.dataset.path = "";
    platformPanel.dataset.path = "";
    return;
  }

  const rootPath = getPublishRootAbsolutePath(item, language);
  const platformPath = getPublishPlatformAbsolutePath(item, language, platform);

  rootPanel.textContent = rootPath || "当前无法解析语言目录路径。";
  platformPanel.textContent = platformPath || "当前无法解析平台目录路径。";
  rootPanel.dataset.path = rootPath;
  platformPanel.dataset.path = platformPath;
}

async function openPublishRootFolder() {
  const result = await api("/api/open-publish-folder", {
    method: "POST",
    body: JSON.stringify({
      bookName: requireBookName(),
      language: getPublishLanguage()
    })
  });
  handleOpenTargetResult(result, `已打开 09_publish/${getPublishLanguage()} 目录。`);
}

async function openPublishPlatformFolder() {
  const result = await api("/api/open-publish-folder", {
    method: "POST",
    body: JSON.stringify({
      bookName: requireBookName(),
      language: getPublishLanguage(),
      platform: getPublishPreviewPlatform()
    })
  });
  handleOpenTargetResult(result, `已打开 ${getPublishPreviewPlatform()} 平台目录。`);
}

async function openPublishPlatformFolderFor(platformName) {
  const result = await api("/api/open-publish-folder", {
    method: "POST",
    body: JSON.stringify({
      bookName: requireBookName(),
      language: getPublishLanguage(),
      platform: platformName
    })
  });
  handleOpenTargetResult(result, `已打开 ${getPublishPlatformLabel(platformName)} 平台目录。`);
}

function findPublishPlatformFile(platformData, predicate) {
  const files = Array.isArray(platformData?.files) ? platformData.files : [];
  return files.find((fileName) => {
    try {
      return predicate(String(fileName || ""));
    } catch {
      return false;
    }
  }) || "";
}

function resolvePublishAssetTarget(platformName, action, item, publish) {
  const label = getPublishPlatformLabel(platformName);
  if (!item) {
    throw new Error("请先选择一个 BookName。");
  }

  if (action === "folder") {
    return { kind: "folder", platform: platformName, fileName: "", label: `${label} 平台目录` };
  }

  const platformData = publish?.platforms?.[platformName] || null;
  const checklistName = findPublishPlatformFile(platformData, (fileName) => /checklist/i.test(fileName) && /\.md$/i.test(fileName));
  const metadataName = findPublishPlatformFile(platformData, (fileName) => /metadata/i.test(fileName) && /\.(json|md)$/i.test(fileName));
  const epubName = findPublishPlatformFile(platformData, (fileName) => /\.epub$/i.test(fileName));
  const coverName = findPublishPlatformFile(platformData, (fileName) => /^cover\.(png|jpg|jpeg|webp|pdf)$/i.test(fileName) || /cover\.(png|jpg|jpeg|webp|pdf)$/i.test(fileName));
  const descriptionTextName = findPublishPlatformFile(platformData, (fileName) => /amazon_description\.txt$/i.test(fileName));
  const descriptionHtmlName = findPublishPlatformFile(platformData, (fileName) => /amazon_description\.html$/i.test(fileName));

  if (action === "epub") {
    if (!epubName) {
      throw new Error(`${label} 平台目录里还没有 epub 文件。`);
    }
    return { kind: "file", platform: platformName, fileName: epubName, label: `${label} epub` };
  }

  if (action === "cover") {
    if (!coverName) {
      throw new Error(`${label} 平台目录里还没有 cover 文件。`);
    }
    return { kind: "file", platform: platformName, fileName: coverName, label: `${label} cover` };
  }

  if (action === "meta") {
    if (checklistName) {
      return { kind: "file", platform: platformName, fileName: checklistName, label: `${label} checklist` };
    }
    if (metadataName) {
      return { kind: "file", platform: platformName, fileName: metadataName, label: `${label} metadata` };
    }
    return { kind: "file", platform: "", fileName: "publish_metadata.md", label: "publish metadata" };
  }

  if (action === "descText") {
    if (!descriptionTextName) {
      throw new Error(`${label} 平台目录里还没有 amazon_description.txt。`);
    }
    return { kind: "file", platform: platformName, fileName: descriptionTextName, label: `${label} description txt` };
  }

  if (action === "descHtml") {
    if (!descriptionHtmlName) {
      throw new Error(`${label} 平台目录里还没有 amazon_description.html。`);
    }
    return { kind: "file", platform: platformName, fileName: descriptionHtmlName, label: `${label} description html` };
  }

  throw new Error("未知的平台文件操作。");
}

async function openPublishAsset(platformName, action) {
  const item = getSelectedWorkspaceItem();
  const publish = item ? state.publishCache[getPublishCacheKey(item.bookName, getPublishLanguage())] || null : null;
  const target = resolvePublishAssetTarget(platformName, action, item, publish);

  if (target.kind === "folder") {
    await openPublishPlatformFolderFor(target.platform);
    return;
  }

  const result = await api("/api/open-publish-file", {
    method: "POST",
    body: JSON.stringify({
      bookName: requireBookName(),
      language: getPublishLanguage(),
      platform: target.platform,
      fileName: target.fileName
    })
  });
  handleOpenTargetResult(result, `已打开 ${target.label}。`);
}

async function saveAmazonDescription() {
  const item = getSelectedWorkspaceItem();
  if (!item) {
    throw new Error("请先选择一个 BookName。");
  }

  const editor = $("#amazon-description-editor");
  if (!editor) {
    throw new Error("Amazon Description 编辑器不存在。");
  }

  const descriptionText = String(editor.value || "").trim();
  if (!descriptionText) {
    throw new Error("请先粘贴 Amazon 介绍文案。");
  }

  updateAmazonDescriptionStatus("正在保存 Amazon Description...");
  const result = await api("/api/amazon-description", {
    method: "POST",
    body: JSON.stringify({
      bookName: item.bookName,
      language: getPublishLanguage(),
      descriptionText
    })
  });

  await loadPublishArtifacts(item, getPublishLanguage());
  updateAmazonDescriptionStatus([
    `已保存 TXT + HTML（${getPublishLanguage()}）`,
    `TXT：${result.textPath || result.textFileName || "-"}`,
    `HTML：${result.htmlPath || result.htmlFileName || "-"}`,
    `源稿：${result.sourceMarkdownPath || result.sourceMarkdownFileName || "-"}`
  ].join("\n"));
  setStatusBadge("成功", "success");
  setLog([
    "Amazon Description 已保存。",
    `TXT 文件名: ${result.textFileName || "amazon_description.txt"}`,
    `TXT 路径: ${result.textFullPath || result.textPath || "-"}`,
    `HTML 文件名: ${result.htmlFileName || "amazon_description.html"}`,
    `HTML 路径: ${result.htmlFullPath || result.htmlPath || "-"}`,
    `源稿文件名: ${result.sourceMarkdownFileName || "amazon_description.md"}`,
    `源稿路径: ${result.sourceMarkdownFullPath || result.sourceMarkdownPath || "-"}`
  ].join("\n"));
}

function formatRecommendedCategoriesHtml(recommended) {
  const selectedMap = getPublishSelectedCategories(state.publishEditorKey);
  const activePlatform = getPublishPreviewPlatform();
  const platforms = [activePlatform || "amazon"];
  const cards = platforms.map((platformName) => {
    const entries = Array.isArray(recommended?.[platformName]) ? recommended[platformName] : [];
    const label = platformName === "amazon"
      ? "Amazon"
      : platformName === "apple"
        ? "Apple Books"
        : platformName === "google"
          ? "Google Play Books"
          : "Kobo";

    const listHtml = entries.length
      ? entries.map((entry) => `
          <div class="publish-category-item">
            <strong>${escapeHtml(String(entry.priority || ""))}</strong>
            <div>
              <div class="publish-category-path">${escapeHtml(entry.path || "")}</div>
              <span>${escapeHtml(entry.note || "")}</span>
            </div>
            <button
              type="button"
              class="ghost-button publish-category-select-button ${selectedMap[platformName] === entry.path ? "is-selected" : ""}"
              data-publish-category-platform="${escapeHtml(platformName)}"
              data-publish-category-path="${escapeHtml(entry.path || "")}"
            >
              ${selectedMap[platformName] === entry.path ? "已选默认" : "设为默认"}
            </button>
          </div>
        `).join("")
      : '<div class="build-output-empty">当前还没有推荐分类。</div>';

    return `
      <details class="publish-platform-review-card" data-publish-review-platform="${escapeHtml(platformName)}" ${isPublishRecommendedCardOpen(platformName) ? "open" : ""}>
        <summary>
          <span class="publish-platform-review-title">${escapeHtml(label)}</span>
          <span class="publish-platform-review-meta">${entries.length ? `${entries.length} 条建议` : "暂无建议"}</span>
        </summary>
        <div class="publish-platform-review-body">
          <div class="publish-platform-review-tip">系统已根据当前书稿内容自动推导该平台建议分类，人工可在提交前核对是否需要微调。</div>
          ${listHtml}
        </div>
      </details>
    `;
  }).join("");

  return cards || '<div class="build-output-empty">当前还没有推荐分类。</div>';
}

function renderPublishInsights(item, publish, language) {
  const note = $("#publish-review-note");
  const sourcePanel = $("#publish-source-summary");
  const categoriesPanel = $("#publish-recommended-categories");
  if (!note || !sourcePanel || !categoriesPanel) {
    return;
  }

  if (!item) {
    note.textContent = "09 的元数据应由系统根据当前语种书稿自动生成，人工主要负责审校与少量微调。";
    sourcePanel.innerHTML = "选择一个 BookName 后，这里会显示当前语言版本的生成来源、输出文件和发布目录。";
    categoriesPanel.innerHTML = "运行 09-publish.ps1 后，这里会显示 Amazon / Apple / Google / Kobo 的推荐分类路径。";
    renderPublishOpenPaths(null, null, language);
    return;
  }

  const sourceLanguages = getWorkspacePublishLanguages(item, publish);
  note.textContent = `系统会根据 ${sourceLanguages.map((code) => `${getLanguageLabel(code)}（${code}）`).join("、")} 这些语种版本自动生成上架元数据；当前正在审校的是 ${getLanguageLabel(language)}（${language}）版本。`;

  if (!publish?.metadataJson) {
    sourcePanel.innerHTML = `<div>当前语种：${escapeHtml(getLanguageLabel(language))}（${escapeHtml(language)}）</div><div>尚未生成 09 元数据，请先运行 09-publish.ps1。</div>`;
    categoriesPanel.innerHTML = '<div class="build-output-empty">当前语言还没有推荐分类。</div>';
    renderPublishOpenPaths(item, publish, language);
    return;
  }

  sourcePanel.innerHTML = formatPublishSourceSummary(item, publish, language);
  renderPublishOpenPaths(item, publish, language);
  categoriesPanel.innerHTML = formatRecommendedCategoriesHtml(
    publish.metadataJson.platform_recommended_categories || publish.metadataJson.discovery?.platform_recommended_categories || {}
  );

  categoriesPanel.querySelectorAll("[data-publish-category-platform]").forEach((button) => {
    button.addEventListener("click", () => {
      const cacheKey = state.publishEditorKey || getPublishCacheKey(item.bookName, language);
      const selected = {
        ...getPublishSelectedCategories(cacheKey),
        [button.dataset.publishCategoryPlatform || ""]: button.dataset.publishCategoryPath || ""
      };
      state.publishSelectedCategories[cacheKey] = selected;
      state.publishEditorDirty = true;
      updatePublishEditorStatus();
      renderPublishInsights(item, publish, language);
      schedulePublishAutoSave();
    });
  });

  categoriesPanel.querySelectorAll("[data-publish-review-platform]").forEach((details) => {
    details.addEventListener("toggle", () => {
      setPublishRecommendedCardState(details.dataset.publishReviewPlatform || "", details.open);
    });
  });
}

function setPublishEditorFields(metadataMarkdown, metadata, cacheKey, force = false) {
  if (typeof metadataMarkdown !== "string") {
    return;
  }

  if (!force && state.publishEditorKey === cacheKey && state.publishEditorDirty) {
    return;
  }

  setFormValue("#publish-metadata-editor", metadataMarkdown);

  state.publishEditorKey = cacheKey;
  setPublishSelectedCategories(cacheKey, metadata);
  state.publishEditorDirty = false;
  updatePublishEditorStatus();
}

function getPublishEditorPayload() {
  return {
    metadataMarkdown: $("#publish-metadata-editor")?.value || "",
    selectedPlatformCategories: getPublishSelectedCategories(state.publishEditorKey)
  };
}

async function savePublishMetadata() {
  const bookName = requireBookName();
  const language = getPublishLanguage();
  const payload = {
    bookName,
    language,
    ...getPublishEditorPayload()
  };

  const result = await api("/api/publish-metadata", {
    method: "POST",
    body: JSON.stringify(payload)
  });

  const cacheKey = `${bookName}:${language}`;
  state.publishCache[cacheKey] = result.publish || null;
  state.publishEditorKey = cacheKey;
  setPublishSelectedCategories(cacheKey, result.publish?.metadataJson || {});
  state.publishEditorDirty = false;
  state.publishLastSavedAt = formatTimeLabel();
  updatePublishEditorStatus();

  const selected = getSelectedWorkspaceItem();
  renderPublishPanel(selected);
  flashPublishPreview(`已刷新 ${getLanguageLabel(language)}（${language}）版本的右侧预览`);
  return { bookName, language };
}

async function savePublishMetadataWithFeedback(mode = "manual") {
  state.publishSaveInFlight = true;
  showPublishSaveFeedback("saving", mode === "manual" ? "正在保存当前人工微调..." : "检测到修改，正在自动保存...", true);
  updatePublishEditorStatus();

  try {
    const result = await savePublishMetadata();
    showPublishSaveFeedback(
      "success",
      mode === "manual"
        ? `已保存 ${getLanguageLabel(result.language)}（${result.language}）版本的 09 元数据。`
        : `已自动保存 ${getLanguageLabel(result.language)}（${result.language}）版本的 09 元数据。`
    );
    if (mode === "manual") {
      setStatusBadge("已保存", "success");
      setLog(`09 的 ${result.language} 语言元数据人工微调已保存，并同步刷新该语种的平台上架包。`);
    }
    return result;
  } catch (error) {
    showPublishSaveFeedback("error", `保存失败：${error.message}`, false);
    throw error;
  } finally {
    state.publishSaveInFlight = false;
    updatePublishEditorStatus();
  }
}

function schedulePublishAutoSave() {
  clearPublishAutoSaveTimer();
  state.publishAutoSaveTimer = setTimeout(async () => {
    if (!state.publishEditorDirty || state.publishSaveInFlight) {
      return;
    }

    try {
      await savePublishMetadataWithFeedback("auto");
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  }, 1200);
}

function renderPublishFiles(bookName, language, platformName, platformData) {
  const panel = $("#publish-file-list");
  const summary = $("#publish-file-summary");
  if (!panel) {
    return;
  }

  if (!platformData || !platformData.exists) {
    panel.innerHTML = "";
    if (summary) {
      summary.textContent = "当前平台文件 0 个";
    }
    return;
  }

  const files = platformData.files || [];
  if (!files.length) {
    panel.innerHTML = "";
    if (summary) {
      summary.textContent = `当前平台文件 0 个 · ${platformData.folder || ""}`.trim();
    }
    return;
  }

  if (summary) {
    summary.textContent = `当前平台文件 ${files.length} 个 · ${platformData.folder || `09_publish/${language}/${platformName}`}`;
  }
  panel.innerHTML = "";
}

function getPublishPlatformStatus(platformName, item, publish) {
  const label = getPublishPlatformLabel(platformName);
  if (!item) {
    return {
      chips: [
        { label: "平台包", value: "待选择", tone: "neutral" },
        { label: "元数据", value: "待选择", tone: "neutral" },
        { label: "文案", value: "待选择", tone: "neutral" },
        { label: "文件", value: "0", tone: "neutral" }
      ],
      nextStep: "先选择一个 BookName，然后这里会显示当前平台的准备情况。"
    };
  }

  if (!publish) {
    return {
      chips: [
        { label: "平台包", value: "读取中", tone: "warn" },
        { label: "元数据", value: "读取中", tone: "warn" },
        { label: "文案", value: "读取中", tone: "warn" },
        { label: "文件", value: "…", tone: "neutral" }
      ],
      nextStep: "正在读取 09 上架数据；如果长时间没有结果，可以先运行 09-publish.ps1。"
    };
  }

  const metadataReady = Boolean(publish.metadataJson || publish.metadataMarkdown);
  const platformData = publish.platforms?.[platformName] || null;
  const fileCount = Array.isArray(platformData?.files) ? platformData.files.length : 0;
  const pkg = platformData?.packageJson || {};
  const descriptionReady = Boolean((platformData?.descriptionText || pkg.book_details?.description || "").trim());
  const keywordsReady = Boolean((platformData?.keywordsText || "").trim() || (Array.isArray(pkg.book_details?.keywords) && pkg.book_details.keywords.length));
  const packageReady = Boolean(platformData?.exists && pkg.package_ready);
  const packageExists = Boolean(platformData?.exists && platformData?.packageJson);
  const checks = pkg.quality_checks || {};
  const missingItems = [];

  if (checks.has_manuscript === false || checks.has_book === false) {
    missingItems.push("书稿");
  }
  if (checks.has_cover === false) {
    missingItems.push("封面");
  }
  if (checks.has_metadata === false) {
    missingItems.push("元数据");
  }

  let nextStep = "";
  if (platformName === "kobo" && !platformData?.exists) {
    nextStep = "当前 09-publish.ps1 还没有自动生成 Kobo 平台包；现在可以先准备入口链接、元数据策略和人工提交流程。";
  } else if (!platformData?.exists) {
    nextStep = `先运行 09-publish.ps1 生成 ${label} 平台包。`;
  } else if (!packageExists) {
    nextStep = `${label} 目录已存在，但还没有 package 文件；建议重新运行 09-publish.ps1。`;
  } else if (!packageReady && missingItems.length) {
    nextStep = `先补齐${missingItems.join("、")}，再进入 ${label} 发布入口。`;
  } else if (!packageReady) {
    nextStep = `${label} 平台包已生成，但还有检查项待确认；建议先核对 checklist、描述文案和关键词。`;
  } else {
    nextStep = `${label} 平台包已就绪，可以进入发布入口继续人工发布。`;
  }

  return {
    chips: [
      { label: "平台包", value: packageReady ? "就绪" : packageExists ? "草稿" : "未生成", tone: packageReady ? "good" : packageExists ? "warn" : "neutral" },
      { label: "元数据", value: metadataReady ? "已生成" : "未生成", tone: metadataReady ? "good" : "warn" },
      { label: "文案", value: descriptionReady ? "已生成" : "待补", tone: descriptionReady ? "good" : "warn" },
      { label: "关键词", value: keywordsReady ? "已生成" : "待补", tone: keywordsReady ? "good" : "warn" },
      { label: "文件数", value: String(fileCount), tone: fileCount > 0 ? "good" : "neutral" }
    ],
    nextStep
  };
}

function renderPublishWorkbenchStatuses(item, publish) {
  ["amazon", "google", "apple", "kobo"].forEach((platformName) => {
    const panel = document.querySelector(`[data-publish-platform-status="${platformName}"]`);
    if (!panel) {
      return;
    }

    const status = getPublishPlatformStatus(platformName, item, publish);
    panel.innerHTML = `
      <div class="cover-report-title">${escapeHtml(getPublishPlatformLabel(platformName))} 平台状态</div>
      <div class="publish-platform-status-grid">
        ${status.chips.map((chip) => `
          <div class="publish-platform-status-chip is-${escapeHtml(chip.tone || "neutral")}">
            <span>${escapeHtml(chip.label || "")}</span>
            <strong>${escapeHtml(chip.value || "")}</strong>
          </div>
        `).join("")}
      </div>
      <div class="publish-platform-status-next"><strong>建议下一步：</strong>${escapeHtml(status.nextStep || "继续检查平台包。")}</div>
    `;
  });
}

function renderPublishPlatformDetail(language, platformName, platformData, rawText) {
  const rawPanel = $("#publish-platform-preview");
  const folderLabel = $("#publish-platform-folder");
  const statsPanel = $("#publish-platform-stats");
  const cardsPanel = $("#publish-platform-cards");
  const rawToggle = document.querySelector(".publish-raw-toggle");

  if (!rawPanel || !folderLabel || !statsPanel || !cardsPanel) {
    return;
  }

  if (rawToggle) {
    rawToggle.open = isPublishRawToggleOpen();
  }

  rawPanel.value = rawText || "选择平台后，这里会显示对应平台的提交清单。";

  if (!platformData || !platformData.exists) {
    folderLabel.textContent = `当前语言还没有 ${platformName} 平台目录。`;
    statsPanel.innerHTML = '<div class="build-output-empty">当前平台尚未生成。</div>';
    cardsPanel.innerHTML = '<div class="build-output-empty">当前平台还没有可显示的 package / checklist / description / keywords。</div>';
    return;
  }

  const pkg = platformData.packageJson || {};
  const details = pkg.book_details || {};
  const checks = pkg.quality_checks || {};
  const assets = pkg.upload_assets || {};
  const keywords = Array.isArray(details.keywords) ? details.keywords : [];
  const categories = Array.isArray(details.categories) ? details.categories : [];
  const description = (platformData.descriptionText || details.description || "").trim();

  folderLabel.textContent = platformData.folder || `09_publish/${language}/${platformName}`;

  const statItems = [
    { label: "状态", value: pkg.package_ready ? "Ready" : "Draft" },
    { label: "类型", value: pkg.submission_type || "ebook" },
    { label: "文件", value: String((platformData.files || []).length) },
    { label: "关键词", value: String(checks.keyword_box_count || keywords.length || 0) },
    { label: "分类", value: String(checks.category_count || categories.length || 0) }
  ];

  statsPanel.innerHTML = statItems.map((item) => `
    <div class="publish-platform-stat">
      <span>${escapeHtml(item.label)}</span>
      <strong>${escapeHtml(item.value)}</strong>
    </div>
  `).join("");

  const qualityList = Object.entries(checks)
    .filter(([key]) => key.startsWith("has_"))
    .map(([key, value]) => `<li>${escapeHtml(key.replace(/^has_/, "").replaceAll("_", " "))}: ${value ? "yes" : "no"}</li>`)
    .join("");

  const assetList = Object.entries(assets)
    .filter(([, value]) => value)
    .map(([key, value]) => `<li>${escapeHtml(key)}: ${escapeHtml(value)}</li>`)
    .join("");

  const keywordList = keywords.length
    ? `<ul>${keywords.map((entry) => `<li>${escapeHtml(entry)}</li>`).join("")}</ul>`
    : '<div>当前没有关键词。</div>';

  const categoryList = categories.length
    ? `<ul>${categories.map((entry) => `<li>${escapeHtml(entry)}</li>`).join("")}</ul>`
    : '<div>当前没有分类。</div>';

  cardsPanel.innerHTML = `
    <div class="publish-platform-card">
      <h4>提交包概览</h4>
      <div>Title: ${escapeHtml(details.title || "")}</div>
      <div>Author: ${escapeHtml(details.author || "")}</div>
      <div>Language: ${escapeHtml(details.language || language)}</div>
      <div>Publisher: ${escapeHtml(details.publisher || "")}</div>
    </div>
    <div class="publish-platform-card">
      <h4>上传素材</h4>
      ${assetList ? `<ul>${assetList}</ul>` : "<div>当前没有素材清单。</div>"}
    </div>
    <div class="publish-platform-card">
      <h4>质量检查</h4>
      ${qualityList ? `<ul>${qualityList}</ul>` : "<div>当前没有质量检查结果。</div>"}
    </div>
    <div class="publish-platform-card">
      <h4>商店简介</h4>
      <p>${escapeHtml(description || "当前没有商店简介。").replaceAll("\n", "<br>")}</p>
    </div>
    <div class="publish-platform-card">
      <h4>关键词</h4>
      ${keywordList}
    </div>
    <div class="publish-platform-card">
      <h4>分类</h4>
      ${categoryList}
    </div>
  `;
}

function renderPublishPanel(item) {
  const summary = $("#publish-summary");
  const reportPanel = $("#publish-report-preview");
  const platformPanel = $("#publish-platform-preview");

  if (!summary || !reportPanel || !platformPanel) {
    return;
  }

  if (!item) {
    clearPublishAutoSaveTimer();
    hidePublishSaveFeedback();
    state.publishLastSavedAt = "";
    syncPublishLanguageOptions(null, null, getPublishLanguage());
    summary.textContent = "选择一个 BookName 后，这里会显示 09 上架包。";
    setPublishEditorFields("运行 09-publish.ps1 后，这里会显示可直接审校的 publish_metadata.md。", {}, "", true);
    reportPanel.value = "运行 09-publish.ps1 后，这里会显示 publish_report.md。";
    renderPublishInsights(null, null, getPublishLanguage());
    renderPublishWorkbenchStatuses(null, null);
    renderPublishPlatformDetail(getPublishLanguage(), getPublishPreviewPlatform(), null, "选择平台后，这里会显示对应平台的提交清单。");
    renderPublishFiles("", getPublishLanguage(), getPublishPreviewPlatform(), null);
    return;
  }

  const requestedLanguage = getPublishLanguage();
  let cacheKey = `${item.bookName}:${requestedLanguage}`;
  let publish = state.publishCache[cacheKey] || null;
  syncPublishLanguageOptions(item, publish, requestedLanguage);
  const language = getPublishLanguage();
  const previewPlatform = getPublishPreviewPlatform();
  if (language !== requestedLanguage) {
    cacheKey = `${item.bookName}:${language}`;
    publish = state.publishCache[cacheKey] || null;
  }

  if (!publish) {
    summary.textContent = state.publishLoadingKey === cacheKey
      ? "正在读取 09 上架数据，请稍候..."
      : "当前语言还没有加载 09 上架数据。";
    setPublishEditorFields("正在读取统一出版元数据...", {}, cacheKey, true);
    reportPanel.value = "正在读取 publish_report.md ...";
    renderPublishInsights(item, null, language);
    renderPublishWorkbenchStatuses(item, null);
    renderPublishPlatformDetail(language, previewPlatform, null, "正在读取平台提交清单...");
    renderPublishFiles(item.bookName, language, previewPlatform, null);
    if (state.publishLoadingKey !== cacheKey) {
      loadPublishArtifacts(item, language);
    }
    return;
  }

  const availableLanguages = getWorkspacePublishLanguages(item, publish);
  const platformData = publish.platforms?.[previewPlatform] || null;

  summary.textContent =
    `语言: ${getLanguageLabel(language)}（${language}） · ` +
    `可用语言: ${availableLanguages.length ? availableLanguages.map((code) => `${getLanguageLabel(code)}（${code}）`).join("、") : "暂无"} · ` +
    `publish 根目录: ${publish.exists ? publish.root || `09_publish/${language}` : "尚未生成"} · ` +
    `root files: ${(publish.rootFiles || []).length}`;

  setPublishEditorFields(publish.metadataMarkdown || "当前语言还没有 publish_metadata.md。", publish.metadataJson || {}, cacheKey);
  reportPanel.value = publish.reportText || "当前语言还没有 publish_report.md。";
  renderPublishInsights(item, publish, language);
  renderPublishWorkbenchStatuses(item, publish);

  let rawPlatformText = "";
  if (!platformData || !platformData.exists) {
    rawPlatformText = `当前语言还没有 ${previewPlatform} 平台的上架包。`;
  } else {
    const packageText = platformData.packageJson
      ? JSON.stringify(platformData.packageJson, null, 2)
      : "";
    const checklistText = platformData.checklistText || "";
    const descriptionText = platformData.descriptionText || "";
    const keywordsText = platformData.keywordsText || "";

    rawPlatformText = [
      `# ${previewPlatform} package`,
      "",
      packageText,
      "",
      "# checklist",
      "",
      checklistText,
      "",
      "# description",
      "",
      descriptionText,
      "",
      "# keywords",
      "",
      keywordsText
    ].join("\n").trim();
  }

  renderPublishPlatformDetail(language, previewPlatform, platformData, rawPlatformText);
  renderPublishFiles(item.bookName, language, previewPlatform, platformData);

  const amazonEditor = $("#amazon-description-editor");
  if (amazonEditor) {
    const amazonPlatformData = publish.platforms?.amazon || null;
    amazonEditor.value = amazonPlatformData?.descriptionSourceText || amazonPlatformData?.descriptionText || "";
    updateAmazonDescriptionStatus(
      (amazonPlatformData?.descriptionSourceText || amazonPlatformData?.descriptionText)
        ? "当前已加载 Amazon Description 源稿"
        : "尚未单独保存 Amazon Description"
    );
  }
}

function renderWorkspaceSelection(item) {
  clearPublishAutoSaveTimer();
  hidePublishSaveFeedback();
  clearPublishPreviewRefreshTimer();
  state.publishSaveInFlight = false;
  renderProjectSummary(item);
  renderIntakePreview(item);
  renderProjectStatus(item);
  renderTocPreview(item);
  renderPreflightReport(item);
  renderChapterBrowser(item);
  renderBuildOutputs(item);
  renderPublishPanel(item);
  renderCoverPanel(item);
  renderCoverCopyEditor(item);
  renderFrontmatterEditor(item);
}

function getRoleLabel(role) {
  return role === "admin" ? "管理员" : "普通用户";
}

function getUserStatusLabel(user) {
  return user?.disabled ? "已禁用" : "可使用";
}

function getAuditActionLabel(action) {
  return {
    "auth.login.success": "登录成功",
    "auth.login.failed": "登录失败",
    "auth.login.disabled": "禁用账号登录",
    "auth.logout": "退出登录",
    "user.create": "创建用户",
    "user.update": "修改用户",
    "user.password.reset": "重置密码",
    "account.password.change": "自改密码",
    "billing.adjust": "积分调整",
    "job.start": "任务开始",
    "job.finish": "任务结束",
    "job.cancel": "任务取消"
  }[action] || action || "未知动作";
}

function getAuditStatusLabel(status) {
  return {
    success: "成功",
    failed: "失败",
    running: "运行中",
    cancelled: "已取消"
  }[status] || status || "-";
}

function formatBillingCredits(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) {
    return "0";
  }
  return number.toLocaleString("zh-CN", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 3
  });
}

function formatSignedBillingCredits(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) {
    return "0";
  }
  return `${number > 0 ? "+" : ""}${formatBillingCredits(number)}`;
}

function formatTokenCount(value) {
  const number = Number(value);
  if (!Number.isFinite(number)) {
    return "0";
  }
  return Math.round(number).toLocaleString("zh-CN");
}

function formatUserBillingLine(user) {
  const billing = user?.billing || {};
  return [
    `初始 ${formatBillingCredits(billing.initialCredits)} 分`,
    `已用 ${formatBillingCredits(billing.usedCredits)} 分`,
    `余额 ${formatBillingCredits(billing.balanceCredits)} 分`,
    `token ${formatTokenCount(billing.usedTokens)}`
  ].join(" · ");
}

function formatUserDate(value) {
  if (!value) {
    return "-";
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return String(value);
  }
  return formatKdpReportTimestamp(date);
}

function renderBillingEventList(events, emptyText = "还没有积分流水") {
  if (!Array.isArray(events) || !events.length) {
    return `<div class="workspace-item muted">${escapeHtml(emptyText)}</div>`;
  }
  return events.map((event) => {
    const usage = event.usage || {};
    const isAdjustment = event.eventType === "credit_adjustment" || event.source === "admin_credit_adjustment";
    const label = isAdjustment ? "管理员积分调整" : (event.route || event.source || "LLM 使用");
    const detail = [
      event.bookName ? `BookName：${event.bookName}` : "",
      event.model ? `模型：${event.model}` : "",
      event.jobId ? `Job：${event.jobId}` : "",
      event.adminUsername ? `管理员：${event.adminUsername}` : "",
      event.note ? `备注：${event.note}` : ""
    ].filter(Boolean).join(" · ");
    const billingLine = isAdjustment
      ? `调整：${formatSignedBillingCredits(event.creditDelta)} 分 · 当时余额：${formatBillingCredits(event.balanceCredits)} 分`
      : `扣分：${formatBillingCredits(event.chargedCredits)} 分 · 当时余额：${formatBillingCredits(event.balanceCredits)} 分`;
    return `
      <div class="account-event-item">
        <div class="account-event-head">
          <strong>${escapeHtml(label)}</strong>
          <span>${escapeHtml(formatUserDate(event.createdAt))}</span>
        </div>
        ${isAdjustment ? "" : `<span>token：input ${escapeHtml(formatTokenCount(usage.input_tokens))} · output ${escapeHtml(formatTokenCount(usage.output_tokens))} · total ${escapeHtml(formatTokenCount(usage.total_tokens))}</span>`}
        <span>${escapeHtml(billingLine)}</span>
        ${detail ? `<span>${escapeHtml(detail)}</span>` : ""}
      </div>
    `;
  }).join("");
}

function mergeUserIntoState(nextUser) {
  if (!nextUser?.id) {
    return;
  }
  const index = state.users.findIndex((user) => user.id === nextUser.id);
  if (index >= 0) {
    state.users[index] = nextUser;
  } else {
    state.users.push(nextUser);
  }
}

function setUserAdminFeedback(message = "", kind = "") {
  const feedback = $("#user-admin-feedback");
  if (!feedback) {
    return;
  }
  feedback.textContent = message;
  feedback.dataset.kind = kind;
}

function setAccountFeedback(message = "", kind = "") {
  const feedback = $("#account-feedback");
  if (!feedback) {
    return;
  }
  feedback.textContent = message;
  feedback.dataset.kind = kind;
}

function renderAccountPanel() {
  const panel = $("#account-panel");
  if (!panel) {
    return;
  }

  const isUserMode = state.authMode === "users";
  panel.hidden = !isUserMode;
  const navItem = document.querySelector('[data-flow-target="account"]');
  if (navItem) {
    navItem.hidden = !isUserMode;
  }
  if (!isUserMode) {
    return;
  }

  const accountUser = state.account?.user || state.currentUser || {};
  const billing = state.account?.billing || accountUser.billing || {};
  const summary = $("#account-summary");
  const note = $("#account-note");
  const cards = $("#account-billing-cards");
  const list = $("#account-event-list");

  if (summary) {
    summary.textContent = `${accountUser.username || accountUser.displayName || "当前用户"} · ${getRoleLabel(accountUser.role)}`;
  }
  if (note) {
    note.textContent = state.accountError || `每 ${formatTokenCount(billing.tokensPerCredit || state.billingConfig?.tokensPerCredit || 1000)} token 记 1 分，积分可为负。`;
  }
  if (cards) {
    cards.innerHTML = [
      ["积分余额", `${formatBillingCredits(billing.balanceCredits)} 分`],
      ["已用积分", `${formatBillingCredits(billing.usedCredits)} 分`],
      ["已用 token", formatTokenCount(billing.usedTokens)],
      ["初始积分", `${formatBillingCredits(billing.initialCredits)} 分`]
    ].map(([label, value]) => `
      <div class="account-billing-card">
        <span>${escapeHtml(label)}</span>
        <strong>${escapeHtml(value)}</strong>
      </div>
    `).join("");
  }
  if (!list) {
    return;
  }
  if (state.accountError) {
    list.innerHTML = `<div class="workspace-item muted">${escapeHtml(state.accountError)}</div>`;
    return;
  }
  list.innerHTML = renderBillingEventList(state.accountEvents, "还没有积分流水");
}

function renderAdminUserBillingEvents(userId) {
  const billingState = state.userBillingEvents[userId];
  if (!billingState) {
    return `<div class="user-billing-events" data-user-billing-events="${escapeHtml(userId)}" hidden></div>`;
  }
  if (billingState.loading) {
    return `
      <div class="user-billing-events" data-user-billing-events="${escapeHtml(userId)}">
        <div class="workspace-item muted">正在读取积分流水...</div>
      </div>
    `;
  }
  if (billingState.error) {
    return `
      <div class="user-billing-events" data-user-billing-events="${escapeHtml(userId)}">
        <div class="workspace-item muted">${escapeHtml(billingState.error)}</div>
      </div>
    `;
  }
  return `
    <div class="user-billing-events" data-user-billing-events="${escapeHtml(userId)}">
      ${renderBillingEventList(billingState.events || [], "还没有积分流水")}
    </div>
  `;
}

function renderAdminAuditPanel() {
  const section = $("#admin-audit-section");
  if (!section) {
    return;
  }
  const isUserMode = state.authMode === "users";
  const isAdmin = (state.currentUser || {}).role === "admin";
  section.hidden = !isUserMode || !isAdmin;
  if (section.hidden) {
    return;
  }

  const note = $("#audit-note");
  const list = $("#audit-list");
  if (note) {
    if (state.auditLoading) {
      note.textContent = "正在读取审计日志。";
    } else if (state.auditError) {
      note.textContent = state.auditError;
    } else {
      note.textContent = `已加载 ${state.auditEvents.length} 条审计记录${state.auditPath ? ` · ${state.auditPath}` : ""}`;
    }
  }
  if (!list) {
    return;
  }
  if (state.auditError) {
    list.innerHTML = `<div class="workspace-item muted">${escapeHtml(state.auditError)}</div>`;
    return;
  }
  if (state.auditLoading) {
    list.innerHTML = '<div class="workspace-item muted">正在读取审计日志...</div>';
    return;
  }
  if (!state.auditEvents.length) {
    list.innerHTML = '<div class="workspace-item muted">还没有审计记录</div>';
    return;
  }
  list.innerHTML = state.auditEvents.map((event) => {
    const detail = [
      event.actorUsername ? `操作者：${event.actorUsername}` : "操作者：系统/未登录",
      event.targetUsername ? `目标用户：${event.targetUsername}` : "",
      event.bookName ? `BookName：${event.bookName}` : "",
      event.route ? `流程：${event.route}` : "",
      event.jobId ? `Job：${event.jobId}` : "",
      event.ip ? `IP：${event.ip}` : ""
    ].filter(Boolean).join(" · ");
    const data = event.data && Object.keys(event.data).length
      ? JSON.stringify(event.data)
      : "";
    return `
      <div class="audit-event-item" data-status="${escapeHtml(event.status || "")}">
        <div class="audit-event-head">
          <strong>${escapeHtml(getAuditActionLabel(event.action))}</strong>
          <span>${escapeHtml(formatUserDate(event.createdAt))}</span>
        </div>
        <span>状态：${escapeHtml(getAuditStatusLabel(event.status))}</span>
        ${detail ? `<span>${escapeHtml(detail)}</span>` : ""}
        ${event.message ? `<span>${escapeHtml(event.message)}</span>` : ""}
        ${data ? `<code>${escapeHtml(data)}</code>` : ""}
      </div>
    `;
  }).join("");
}

function renderUserAdminPanel() {
  const panel = $("#user-admin-panel");
  if (!panel) {
    return;
  }

  const isUserMode = state.authMode === "users";
  const navItem = document.querySelector('[data-flow-target="users"]');
  if (navItem) {
    navItem.hidden = !isUserMode;
  }
  panel.hidden = !isUserMode;
  if (!isUserMode) {
    renderAdminAuditPanel();
    return;
  }

  const currentUser = state.currentUser || {};
  const isAdmin = currentUser.role === "admin";
  const summary = $("#user-admin-summary");
  const note = $("#user-admin-note");
  const list = $("#user-list");
  const form = $("#create-user-form");
  const refreshButton = $("#refresh-users");
  const filterNegative = $("#filter-negative-users");

  if (summary) {
    summary.textContent = isAdmin
      ? `当前管理员：${currentUser.username || currentUser.displayName || ""}`
      : `当前用户：${currentUser.username || currentUser.displayName || ""}`;
  }
  if (form) {
    form.hidden = !isAdmin;
  }
  if (refreshButton) {
    refreshButton.disabled = !isAdmin;
  }
  if (filterNegative) {
    filterNegative.disabled = !isAdmin;
    filterNegative.checked = Boolean(state.userFilterNegative);
  }

  if (!isAdmin) {
    if (note) {
      note.textContent = "当前账号不是管理员，不能管理用户。";
    }
    if (list) {
      list.innerHTML = "";
    }
    setUserAdminFeedback("");
    renderAdminAuditPanel();
    return;
  }

  const negativeUsers = state.users.filter((user) => Number(user?.billing?.balanceCredits) < 0);
  const visibleUsers = state.userFilterNegative ? negativeUsers : state.users;
  if (note) {
    note.textContent = state.userAdminError || `用户库已加载：${state.users.length} 个用户，负余额 ${negativeUsers.length} 个。`;
  }
  if (!list) {
    renderAdminAuditPanel();
    return;
  }
  if (state.userAdminError) {
    list.innerHTML = `<div class="workspace-item muted">${escapeHtml(state.userAdminError)}</div>`;
    renderAdminAuditPanel();
    return;
  }
  if (!state.users.length) {
    list.innerHTML = '<div class="workspace-item muted">还没有用户</div>';
    renderAdminAuditPanel();
    return;
  }

  if (!visibleUsers.length) {
    list.innerHTML = '<div class="workspace-item muted">当前筛选下没有用户</div>';
    renderAdminAuditPanel();
    return;
  }

  list.innerHTML = visibleUsers.map((user) => {
    const userId = user.id || "";
    const disabled = Boolean(user.disabled);
    return `
    <div class="user-item${disabled ? " is-disabled" : ""}" data-user-id="${escapeHtml(userId)}">
      <div class="user-item-head">
        <strong>${escapeHtml(user.displayName || user.username || "")}</strong>
        <div class="user-badge-row">
          <span class="user-role-badge">${escapeHtml(getRoleLabel(user.role))}</span>
          <span class="user-status-badge" data-status="${disabled ? "disabled" : "active"}">${escapeHtml(getUserStatusLabel(user))}</span>
        </div>
      </div>
      <span>用户名：${escapeHtml(user.username || "")}</span>
      <span>用户 ID：${escapeHtml(user.id || "")}</span>
      <span>创建时间：${escapeHtml(formatUserDate(user.createdAt))}</span>
      <span>更新时间：${escapeHtml(formatUserDate(user.updatedAt))}</span>
      <span>计费：${escapeHtml(formatUserBillingLine(user))}</span>
      <span>工作区：${escapeHtml(user.workspaceRoot || "")}</span>
      <div class="user-actions">
        <label class="field user-action-field">
          <span>角色</span>
          <select class="user-role-select" data-user-role>
            <option value="user"${user.role === "admin" ? "" : " selected"}>普通用户</option>
            <option value="admin"${user.role === "admin" ? " selected" : ""}>管理员</option>
          </select>
        </label>
        <button class="ghost-button user-update-role" type="button" data-user-id="${escapeHtml(userId)}">修改角色</button>
        <button class="ghost-button user-toggle-disabled" type="button" data-user-id="${escapeHtml(userId)}" data-disabled="${disabled ? "false" : "true"}">${disabled ? "启用用户" : "禁用用户"}</button>
      </div>
      <form class="user-reset-password-form" data-user-id="${escapeHtml(userId)}">
        <label class="field user-password-field">
          <span>新密码</span>
          <input name="password" type="password" autocomplete="new-password" minlength="8" required>
        </label>
        <button class="ghost-button" type="submit">重置密码</button>
      </form>
      <form class="user-billing-adjust-form" data-user-id="${escapeHtml(userId)}">
        <label class="field user-credit-field">
          <span>积分调整</span>
          <input name="creditDelta" type="number" step="0.001" placeholder="+100 或 -25" required>
        </label>
        <label class="field user-credit-note-field">
          <span>备注</span>
          <input name="note" autocomplete="off" maxlength="500" placeholder="充值、扣分或原因">
        </label>
        <button class="ghost-button" type="submit">保存积分调整</button>
        <button class="ghost-button user-view-billing" type="button" data-user-id="${escapeHtml(userId)}">查看流水</button>
      </form>
      ${renderAdminUserBillingEvents(userId)}
    </div>
  `;
  }).join("");
  renderAdminAuditPanel();
}

async function refreshUsers({ quiet = false } = {}) {
  if (state.authMode !== "users") {
    state.users = [];
    state.userAdminError = "";
    renderUserAdminPanel();
    return;
  }

  try {
    const result = await api("/api/users");
    state.users = result?.users || [];
    state.userAdminError = "";
    renderUserAdminPanel();
    if (!quiet) {
      setUserAdminFeedback(`已刷新用户列表：${state.users.length} 个用户。`, "success");
    }
  } catch (error) {
    state.users = [];
    state.userAdminError = error.message || "用户列表读取失败。";
    renderUserAdminPanel();
    if (!quiet) {
      setUserAdminFeedback(state.userAdminError, "error");
    }
  }
}

async function refreshAudit({ quiet = false } = {}) {
  const isAdmin = state.authMode === "users" && (state.currentUser || {}).role === "admin";
  if (!isAdmin) {
    state.auditEvents = [];
    state.auditError = "";
    state.auditPath = "";
    renderAdminAuditPanel();
    return;
  }

  const form = $("#audit-filter-form");
  const data = form ? formToObject(form) : {};
  const params = new URLSearchParams();
  params.set("limit", String(data.limit || 100));
  if (data.action) {
    params.set("action", String(data.action));
  }
  if (data.user) {
    params.set("user", String(data.user).trim());
  }

  state.auditLoading = true;
  state.auditError = "";
  renderAdminAuditPanel();
  try {
    const result = await api(`/api/admin/audit?${params.toString()}`);
    state.auditEvents = result?.events || [];
    state.auditPath = result?.path || "";
    state.auditError = "";
    if (!quiet) {
      setUserAdminFeedback(`已刷新审计日志：${state.auditEvents.length} 条。`, "success");
    }
  } catch (error) {
    state.auditEvents = [];
    state.auditPath = "";
    state.auditError = error.message || "审计日志读取失败。";
    if (!quiet) {
      setUserAdminFeedback(state.auditError, "error");
    }
  } finally {
    state.auditLoading = false;
    renderAdminAuditPanel();
  }
}

async function refreshAccount({ quiet = false } = {}) {
  if (state.authMode !== "users") {
    state.account = null;
    state.accountEvents = [];
    state.accountError = "";
    renderAccountPanel();
    return;
  }

  try {
    const result = await api("/api/account?limit=20");
    state.account = result || null;
    state.accountEvents = result?.events || [];
    state.accountError = "";
    if (result?.user) {
      state.currentUser = result.user;
    }
    renderAccountPanel();
    if (!quiet) {
      setAccountFeedback("个人信息已刷新。", "success");
    }
  } catch (error) {
    state.account = null;
    state.accountEvents = [];
    state.accountError = error.message || "个人信息读取失败。";
    renderAccountPanel();
    if (!quiet) {
      setAccountFeedback(state.accountError, "error");
    }
  }
}

async function changeOwnPasswordFromForm(form) {
  const data = formToObject(form);
  const payload = {
    currentPassword: String(data.currentPassword || ""),
    newPassword: String(data.newPassword || ""),
    confirmPassword: String(data.confirmPassword || "")
  };
  if (payload.newPassword !== payload.confirmPassword) {
    throw new Error("两次输入的新密码不一致。");
  }
  await api("/api/account/password", {
    method: "POST",
    body: JSON.stringify(payload)
  });
  form.reset();
  setAccountFeedback("密码已修改。当前登录会保留，其它旧登录会失效。", "success");
}

async function createUserFromForm(form) {
  const data = formToObject(form);
  const payload = {
    username: String(data.username || "").trim(),
    displayName: String(data.displayName || "").trim(),
    role: String(data.role || "user"),
    password: String(data.password || ""),
    initialCredits: Number(data.initialCredits || state.billingConfig?.defaultInitialCredits || 1000)
  };
  const result = await api("/api/users", {
    method: "POST",
    body: JSON.stringify(payload)
  });
  form.reset();
  const initialCreditsField = form.querySelector('input[name="initialCredits"]');
  if (initialCreditsField && state.billingConfig?.defaultInitialCredits !== undefined) {
    initialCreditsField.value = String(state.billingConfig.defaultInitialCredits);
    delete initialCreditsField.dataset.touched;
  }
  setUserAdminFeedback(`已创建用户：${result?.user?.username || payload.username}`, "success");
  await refreshUsers({ quiet: true });
  await refreshAudit({ quiet: true });
}

async function updateUserFromPanel(userId, updates, successMessage) {
  const result = await api(`/api/users/${encodeURIComponent(userId)}`, {
    method: "PATCH",
    body: JSON.stringify(updates)
  });
  mergeUserIntoState(result?.user);
  renderUserAdminPanel();
  setUserAdminFeedback(successMessage, "success");
  await refreshUsers({ quiet: true });
  await refreshAudit({ quiet: true });
}

async function resetUserPasswordFromForm(form) {
  const userId = form.dataset.userId || "";
  const data = formToObject(form);
  const password = String(data.password || "");
  const result = await api(`/api/users/${encodeURIComponent(userId)}/password`, {
    method: "POST",
    body: JSON.stringify({ password })
  });
  mergeUserIntoState(result?.user);
  form.reset();
  renderUserAdminPanel();
  setUserAdminFeedback(`已重置密码：${result?.user?.username || userId}`, "success");
  await refreshAudit({ quiet: true });
}

async function refreshUserBillingEvents(userId, { quiet = false } = {}) {
  if (!userId) {
    throw new Error("缺少用户 ID。");
  }
  state.userBillingEvents[userId] = {
    ...(state.userBillingEvents[userId] || {}),
    loading: true,
    error: ""
  };
  renderUserAdminPanel();
  try {
    const result = await api(`/api/users/${encodeURIComponent(userId)}/billing?limit=30`);
    mergeUserIntoState(result?.user);
    state.userBillingEvents[userId] = {
      loading: false,
      error: "",
      events: result?.events || []
    };
    renderUserAdminPanel();
    if (!quiet) {
      setUserAdminFeedback(`已读取积分流水：${result?.user?.username || userId}`, "success");
    }
  } catch (error) {
    state.userBillingEvents[userId] = {
      loading: false,
      error: error.message || "积分流水读取失败。",
      events: []
    };
    renderUserAdminPanel();
    throw error;
  }
}

async function adjustUserCreditsFromForm(form) {
  const userId = form.dataset.userId || "";
  const data = formToObject(form);
  const creditDelta = Number(data.creditDelta);
  if (!Number.isFinite(creditDelta) || creditDelta === 0) {
    throw new Error("请填写非 0 的积分调整数。充值填正数，扣分填负数。");
  }
  const result = await api(`/api/users/${encodeURIComponent(userId)}/billing-adjustment`, {
    method: "POST",
    body: JSON.stringify({
      creditDelta,
      note: String(data.note || "").trim()
    })
  });
  mergeUserIntoState(result?.user);
  state.userBillingEvents[userId] = {
    loading: false,
    error: "",
    events: result?.events || []
  };
  form.reset();
  renderUserAdminPanel();
  setUserAdminFeedback(
    `已调整积分：${result?.user?.username || userId} ${formatSignedBillingCredits(creditDelta)} 分，余额 ${formatBillingCredits(result?.billing?.balanceCredits)} 分。`,
    "success"
  );
  await refreshAudit({ quiet: true });
}

function renderWorkspaces(workspaces) {
  state.workspaces = workspaces;
  const wrap = $("#workspace-list");
  wrap.innerHTML = "";

  if (!workspaces.length) {
    wrap.innerHTML = '<div class="workspace-item muted">还没有工作区</div>';
    renderWorkspaceSelection(null);
    return;
  }

  workspaces.forEach((item) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "workspace-item";
    button.innerHTML = `
      <strong>${escapeHtml(item.bookName)}</strong>
      <span>${item.chapterCount} 个章节文件</span>
      <span>${item.outputFiles.length} 个输出文档</span>
      <span>${(item.outputLanguages || []).length ? `输出语言: ${escapeHtml(item.outputLanguages.join(", "))}` : "04 输出语言未检测到"}</span>
      <span>${(item.publishLanguages || []).length ? `09 上架语言: ${escapeHtml(item.publishLanguages.join(", "))}` : "09 上架包未生成"}</span>
    `;
    button.addEventListener("click", () => {
      $("#bookName").value = item.bookName;
      setRememberedBookName(item.bookName);
      state.selectedRunKey = "";
      renderWorkspaceSelection(item);
    });
    wrap.appendChild(button);
  });

  const currentBookName = getBookName();
  const rememberedBookName = getRememberedBookName();
  const preferredBookName = currentBookName || rememberedBookName;
  if (!currentBookName && preferredBookName) {
    $("#bookName").value = preferredBookName;
  }

  const selected = workspaces.find((item) => item.bookName === preferredBookName);
  if (selected) {
    $("#bookName").value = selected.bookName;
    setRememberedBookName(selected.bookName);
  } else if (preferredBookName) {
    setRememberedBookName("");
  }
  renderWorkspaceSelection(selected || null);
}

async function refreshStatus() {
  const status = await api("/api/status");
  state.appMode = status.appMode || "local";
  state.authMode = status.authMode || "off";
  state.currentUser = status.currentUser || null;
  state.billingConfig = status.billing || status.auth?.billing || null;
  $("#workspace-count").textContent = String(status.workspaces.length);
  const currentUserName = $("#current-user-name");
  const currentUserBilling = $("#current-user-billing");
  const currentUserWorkspace = $("#current-user-workspace");
  if (currentUserName) {
    currentUserName.textContent = status.currentUser?.displayName || status.currentUser?.username || "单用户";
  }
  if (currentUserBilling) {
    currentUserBilling.textContent = status.currentUser?.billing
      ? `积分余额：${formatBillingCredits(status.currentUser.billing.balanceCredits)} 分 · 已用：${formatBillingCredits(status.currentUser.billing.usedCredits)} 分`
      : "积分未启用";
  }
  if (currentUserWorkspace) {
    currentUserWorkspace.textContent = status.workspaceParentRoot || "工作区路径未加载";
  }
  const initialCreditsField = document.querySelector('#create-user-form input[name="initialCredits"]');
  if (initialCreditsField && state.billingConfig?.defaultInitialCredits !== undefined && !initialCreditsField.dataset.touched) {
    initialCreditsField.value = String(state.billingConfig.defaultInitialCredits);
  }
  if (!state.account?.user || state.account.user.id !== status.currentUser?.id) {
    state.account = status.currentUser ? { user: status.currentUser, billing: status.currentUser.billing || null } : null;
  }
  renderAccountPanel();
  renderUserAdminPanel();
  setDefaultModelName(getDefaultModelName());
  renderWorkspaces(status.workspaces);
}

async function restoreActiveJob() {
  if (state.currentJobId) {
    return;
  }

  const remembered = getRememberedCurrentJob();
  if (remembered.jobId) {
    try {
      const query = remembered.bookName ? `?bookName=${encodeURIComponent(remembered.bookName)}` : "";
      const job = await api(`/api/jobs/${remembered.jobId}${query}`);
      if (job?.status === "running") {
        state.currentJobId = job.id;
        state.currentJobBookName = job.meta?.bookName || remembered.bookName || "";
        setStatusBadge("运行中", "running");
        setLog(job.output || "已恢复正在运行的任务。");
        updateCancelJobButton(true);
        pollJob(job.id, state.currentJobBookName).catch((error) => {
          setStatusBadge("失败", "failed");
          setLog(error.message);
          clearRememberedCurrentJob(job.id);
          updateCancelJobButton(false);
        });
        return;
      }
      clearRememberedCurrentJob(remembered.jobId);
    } catch {
      clearRememberedCurrentJob(remembered.jobId);
    }
  }

  const bookName = getBookName();
  if (!bookName) {
    return;
  }

  try {
    const result = await api(`/api/jobs/active?bookName=${encodeURIComponent(bookName)}`);
    const job = result?.job;
    if (!job?.id || job.status !== "running") {
      return;
    }
    state.currentJobId = job.id;
    state.currentJobBookName = job.meta?.bookName || bookName;
    rememberCurrentJob(job.id, state.currentJobBookName);
    setStatusBadge("运行中", "running");
    setLog(job.output || "已恢复正在运行的任务。");
    updateCancelJobButton(true);
    pollJob(job.id, state.currentJobBookName).catch((error) => {
      setStatusBadge("失败", "failed");
      setLog(error.message);
      clearRememberedCurrentJob(job.id);
      updateCancelJobButton(false);
    });
  } catch {
    // Active-job recovery is best-effort; the normal status view still works without it.
  }
}

async function pollJob(jobId, bookName = "") {
  if (state.pollTimer) {
    clearTimeout(state.pollTimer);
    state.pollTimer = null;
  }

  const query = bookName ? `?bookName=${encodeURIComponent(bookName)}` : "";
  const job = await api(`/api/jobs/${jobId}${query}`);
  state.currentJobId = job.id;
  state.currentJobBookName = job.meta?.bookName || bookName || "";
  rememberCurrentJob(job.id, state.currentJobBookName);
  setLog(job.output);

  if (job.status === "running") {
    setStatusBadge("运行中", "running");
    updateCancelJobButton(true);
    await new Promise((resolve) => {
      state.pollTimer = setTimeout(resolve, 1200);
    });
    return pollJob(jobId, state.currentJobBookName);
  }

  updateCancelJobButton(false);
  clearRememberedCurrentJob(job.id);
  state.currentJobId = null;
  state.currentJobBookName = "";
  setStatusBadge(
    job.status === "success" ? "成功" : job.status === "cancelled" ? "已停止" : job.status === "lost" ? "任务丢失" : "失败",
    job.status === "success" ? "success" : job.status === "cancelled" ? "idle" : "failed"
  );
  if (job.meta?.route === "edit" && job.meta?.bookName) {
    delete state.preflightCache[job.meta.bookName];
  }
  if (job.meta?.route?.startsWith("cover") && job.meta?.bookName) {
    delete state.coverCache[job.meta.bookName];
    delete state.coverWorkbenchCache[job.meta.bookName];
    delete state.coverCopyCache[job.meta.bookName];
    delete state.frontmatterCache[job.meta.bookName];
  }
  if (job.meta?.route === "publish" && job.meta?.bookName) {
    Object.keys(state.publishCache).forEach((key) => {
      if (key.startsWith(`${job.meta.bookName}:`)) {
        delete state.publishCache[key];
      }
    });
  }
  await refreshStatus();
  if (job.meta?.route === "edit" && job.meta?.bookName) {
    const selected = state.workspaces.find((item) => item.bookName === job.meta.bookName) || null;
    if (selected) {
      loadPreflightReport(selected);
    }
  }
  if (job.meta?.route?.startsWith("cover") && job.meta?.bookName) {
    const selected = state.workspaces.find((item) => item.bookName === job.meta.bookName) || null;
    if (selected) {
      loadCoverArtifacts(selected);
      loadCoverCopy(selected);
      loadFrontmatter(selected);
    }
  }
  if (job.meta?.route === "publish" && job.meta?.bookName) {
    const selected = state.workspaces.find((item) => item.bookName === job.meta.bookName) || null;
    if (selected) {
      loadPublishArtifacts(selected, getPublishLanguage());
    }
  }

  return job;
}

async function run(route, payload) {
  setStatusBadge("提交中", "running");
  setLog("正在启动脚本，请稍候...");
  const result = await api(`/api/run/${route}`, {
    method: "POST",
    body: JSON.stringify(payload)
  });
  state.currentJobId = result.jobId;
  state.currentJobBookName = payload?.bookName || getBookName();
  rememberCurrentJob(result.jobId, state.currentJobBookName);
  updateCancelJobButton(true);
  return await pollJob(result.jobId, state.currentJobBookName);
}

async function cancelCurrentJob() {
  if (!state.currentJobId) {
    return;
  }

  if (state.pollTimer) {
    clearTimeout(state.pollTimer);
    state.pollTimer = null;
  }

  const jobId = state.currentJobId;
  setStatusBadge("停止中", "running");
  setLog("正在停止当前任务，请稍候...");
  updateCancelJobButton(false);

  const result = await api(`/api/jobs/${jobId}/cancel`, {
    method: "POST"
  });

  state.currentJobId = result.job?.id || jobId;
  setLog(result.job?.output || "当前任务已停止。");
  setStatusBadge("已停止", "idle");
  clearRememberedCurrentJob(jobId);
  state.currentJobId = null;
  state.currentJobBookName = "";
  await refreshStatus();
}

function intOrEmpty(value) {
  if (value === undefined || value === null || value === "") {
    return undefined;
  }
  return Number(value);
}

function buildCoverPayload(form) {
  const payload = formToObject(form);
  payload.bookName = requireBookName();
  payload.model = getDefaultModelName();
  payload.subtitle = ($("#cover-copy-subtitle")?.value || "").trim();
  payload.variants = intOrEmpty(payload.variants) || 4;
  return payload;
}

function getCoverEditElements() {
  const selected = getSelectedWorkspaceItem();
  const title = ($(`#cover-form [name="title"]`)?.value || selected?.objectiveData?.title || "").trim();
  const subtitle = ($("#cover-copy-subtitle")?.value || selected?.objectiveData?.subtitle || "").trim();
  const author = ($(`#cover-form [name="author"]`)?.value || selected?.objectiveData?.author || "").trim();
  const publisher = ($("#cover-edit-publisher")?.value || selected?.objectiveData?.publisher || selected?.objectiveData?.imprint || "").trim();
  return { title, subtitle, author, publisher };
}

function buildCoverEditText() {
  const elements = getCoverEditElements();
  return [
    `书名：${elements.title}`,
    `副标题：${elements.subtitle}`,
    `作者：${elements.author}`,
    `出版社：${elements.publisher}`
  ].join("\n");
}

function refreshCoverEditText(force = true) {
  const textField = $("#cover-edit-text");
  if (!textField) {
    return;
  }
  if (!force && textField.value.replace(/书名：|副标题：|作者：|出版社：|\s/g, "")) {
    return;
  }
  textField.value = buildCoverEditText();
}

async function runCoverImageEdit() {
  const form = $("#cover-form");
  if (!form) {
    throw new Error("Cover form not found.");
  }
  refreshCoverEditText(false);

  const payload = buildCoverPayload(form);
  const elements = getCoverEditElements();
  payload.nextEdition = payload.nextEdition || payload.edition || "ebook";
  payload.title = elements.title;
  payload.subtitle = elements.subtitle;
  payload.author = elements.author;
  payload.publisher = elements.publisher;
  payload.coverText = ($("#cover-edit-text")?.value || buildCoverEditText()).trim();
  payload.imageModel = ($("#cover-edit-image-model")?.value || "gpt-image-1.5").trim() || "gpt-image-1.5";
  const workbench = state.coverWorkbenchCache[payload.bookName] || {};
  payload.inputFile = workbench.selectedImportFile || workbench.latestImportFile || "";

  if (!payload.title) {
    throw new Error("请先填写书名。");
  }
  if (!payload.coverText) {
    throw new Error("请先填写封面文字。");
  }
  if (!payload.inputFile) {
    throw new Error("请先保存或选择一张底图。");
  }

  const job = await run("cover-next-image-edit", payload);
  if (job?.status !== "success") {
    throw new Error("图形模型修图失败。");
  }
  delete state.coverWorkbenchCache[payload.bookName];
}

async function generateCoverMidjourneyPrompt() {
  const form = $("#cover-form");
  if (!form) {
    throw new Error("Cover form not found.");
  }

  const payload = buildCoverPayload(form);
  payload.nextEdition = payload.nextEdition || payload.edition || "ebook";

  const job = await run("cover-midjourney-prompt-ai", payload);
  if (job?.status !== "success") {
    throw new Error("MidJourney prompt model generation failed.");
  }

  const result = await api(
    `/api/cover-midjourney-prompt-result?bookName=${encodeURIComponent(payload.bookName)}&edition=${encodeURIComponent(payload.nextEdition)}&t=${Date.now()}`
  );

  const promptField = $("#cover-midjourney-prompt");
  if (promptField) {
    promptField.value = result.prompt || "";
  }

  const reportJson = result.reportJson || {};
  const usage = reportJson.usage || {};
  const model = reportJson.model || payload.model;
  setStatusBadge("已生成", "success");
  setLog([
    "MidJourney cover-base prompt generated by model.",
    `Script: ${reportJson.script || "08n-midjourney-prompt.ps1"}`,
    `Model: ${model}`,
    `Token usage: input=${usage.input_tokens ?? 0} output=${usage.output_tokens ?? 0} total=${usage.total_tokens ?? 0}`,
    `Report: ${result.paths?.report || "midjourney_prompt_report.md"}`
  ].join("\n"));
  delete state.coverWorkbenchCache[payload.bookName];
}

async function copyCoverMidjourneyPrompt() {
  const prompt = $("#cover-midjourney-prompt")?.value || "";
  if (!prompt.trim()) {
    throw new Error("MidJourney prompt is empty.");
  }
  if (navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(prompt);
  } else {
    const promptField = $("#cover-midjourney-prompt");
    promptField?.focus();
    promptField?.select();
    document.execCommand("copy");
  }
  setStatusBadge("å·²å¤åˆ¶", "success");
  setLog("MidJourney prompt copied.");
}

async function saveCoverMidjourneyPrompt() {
  const bookName = requireBookName();
  const form = $("#cover-form");
  const coverPayload = form ? buildCoverPayload(form) : { nextEdition: "ebook" };
  const prompt = $("#cover-midjourney-prompt")?.value || "";
  if (!prompt.trim()) {
    throw new Error("MidJourney prompt is empty.");
  }

  const result = await api("/api/cover-midjourney-prompt/save", {
    method: "POST",
    body: JSON.stringify({
      bookName,
      prompt,
      edition: coverPayload.nextEdition || coverPayload.edition || "ebook"
    })
  });

  setStatusBadge("å·²ä¿å­˜", "success");
  setLog(`MidJourney prompt saved: ${result.nextPath || result.path || "cover_midjourney_prompt.txt"}`);
  delete state.coverWorkbenchCache[bookName];
}

function formatFileSize(bytes) {
  const value = Number(bytes || 0);
  if (value >= 1024 * 1024) {
    return `${(value / 1024 / 1024).toFixed(1)} MB`;
  }
  if (value >= 1024) {
    return `${(value / 1024).toFixed(1)} KB`;
  }
  return `${value} B`;
}

function readFileAsDataUrl(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result || ""));
    reader.onerror = () => reject(new Error("读取文件失败。"));
    reader.readAsDataURL(file);
  });
}

function renderCoverBaseImportPreview() {
  const preview = $("#cover-base-import-preview");
  const meta = $("#cover-base-import-meta");
  const selected = state.coverBaseImport;
  if (!preview || !meta) {
    return;
  }

  if (!selected) {
    preview.innerHTML = "<span>选择、拖入或粘贴一张外部生成的封面底图</span>";
    meta.textContent = "支持 PNG / JPG / WEBP，保存后进入 08N Imports。";
    return;
  }

  preview.innerHTML = `<img src="${selected.dataUrl}" alt="">`;
  meta.textContent = `${selected.fileName} · ${formatFileSize(selected.size)} · 待保存到 08N Imports`;
}

async function setCoverBaseImportFile(file) {
  if (!file) {
    return;
  }
  if (!/^image\/(png|jpeg|webp)$/.test(file.type || "")) {
    throw new Error("只支持 PNG / JPG / WEBP 底图。");
  }
  if (file.size > 30_000_000) {
    throw new Error("底图文件不能超过 30 MB。");
  }

  const dataUrl = await readFileAsDataUrl(file);
  state.coverBaseImport = {
    fileName: file.name || "external-base-image.png",
    type: file.type,
    size: file.size,
    dataUrl
  };
  renderCoverBaseImportPreview();
  setStatusBadge("已载入", "success");
  setLog("底图已载入预览，点击“保存底图”写入 08N Imports。");
}

async function saveCoverBaseImport() {
  const selected = state.coverBaseImport;
  if (!selected) {
    throw new Error("请先选择、拖入或粘贴一张底图。");
  }

  const form = $("#cover-form");
  const payload = form ? buildCoverPayload(form) : { bookName: requireBookName(), nextEdition: "ebook" };
  payload.nextEdition = payload.nextEdition || payload.edition || "ebook";

  const result = await api("/api/cover-base-image/import", {
    method: "POST",
    body: JSON.stringify({
      bookName: payload.bookName,
      edition: payload.nextEdition,
      fileName: selected.fileName,
      dataUrl: selected.dataUrl
    })
  });

  delete state.coverCache[payload.bookName];
  delete state.coverWorkbenchCache[payload.bookName];
  state.coverBaseImport = null;
  const workspace = state.workspaces.find((item) => item.bookName === payload.bookName) || null;
  if (workspace) {
    await loadCoverArtifacts(workspace);
    await loadCoverWorkbenchState(workspace);
  }

  const meta = $("#cover-base-import-meta");
  if (meta) {
    meta.textContent = `已保存：${result.fileName} · ${formatFileSize(result.size)} · ${result.path}`;
  }
  setStatusBadge("已保存", "success");
  setLog(`外部底图已保存到 08N Imports：${result.fileName}`);
}

async function selectSavedCoverBaseImport(delta) {
  const bookName = requireBookName();
  const item = getSelectedWorkspaceItem();
  if (!item) {
    throw new Error("请先选择一个 BookName。");
  }

  let workbench = state.coverWorkbenchCache[bookName] || null;
  if (!workbench) {
    await loadCoverWorkbenchState(item);
    workbench = state.coverWorkbenchCache[bookName] || null;
  }

  const files = Array.isArray(workbench?.importFiles) ? workbench.importFiles : [];
  if (!files.length) {
    throw new Error("当前还没有已保存的底图。");
  }

  const current = workbench.selectedImportFile || workbench.latestImportFile || files[0];
  const currentIndex = Math.max(0, files.indexOf(current));
  const nextIndex = (currentIndex + delta + files.length) % files.length;
  const selectedImportFile = files[nextIndex];

  const result = await api("/api/cover-workbench-state", {
    method: "POST",
    body: JSON.stringify({
      bookName,
      edition: "ebook",
      selectedImportFile,
      editText: $("#cover-edit-text")?.value || "",
      publisher: $("#cover-edit-publisher")?.value || "",
      imageModel: $("#cover-edit-image-model")?.value || "gpt-image-1.5"
    })
  });

  state.coverBaseImport = null;
  state.coverWorkbenchCache[bookName] = result.workbench || {
    ...workbench,
    selectedImportFile,
    latestImportFile: selectedImportFile
  };
  renderCoverWorkbenchState(item);
  setStatusBadge("已选择", "success");
  setLog(`当前底图：${selectedImportFile}`);
}

function getImageFileFromDragEvent(event) {
  return Array.from(event.dataTransfer?.files || []).find((file) => /^image\//.test(file.type || "")) || null;
}

function getImageFileFromPasteEvent(event) {
  const items = Array.from(event.clipboardData?.items || []);
  const imageItem = items.find((item) => /^image\//.test(item.type || ""));
  return imageItem ? imageItem.getAsFile() : null;
}

async function submitCoverAiRequest() {
  const form = $("#cover-form");
  if (!form) {
    throw new Error("Cover form not found.");
  }

  const requestField = $("#cover-ai-request");
  const responseField = $("#cover-ai-response");
  const userRequest = (requestField?.value || "").trim();
  if (!userRequest) {
    throw new Error("请先输入一段要求。");
  }

  if (responseField) {
    responseField.value = "AI 正在思考，请稍候...";
  }

  const payload = buildCoverPayload(form);
  payload.request = userRequest;
  const job = await run("cover-assist", payload);
  if (job?.status !== "success") {
    throw new Error("AI 助手脚本执行失败。");
  }

  const result = await api(`/api/cover-assistant-result?bookName=${encodeURIComponent(payload.bookName)}&t=${Date.now()}`);

  if (responseField) {
    responseField.value = result.assistantResult?.response || result.responseMarkdown || "";
  }

  setStatusBadge("已生成", "success");
  setLog("AI 助手已返回结果。");
}

function setupForms() {
  mountKdpFixModule();

  $("#project-picker-workbench-shell")?.addEventListener("toggle", (event) => {
    setWorkbenchOpen("#project-picker-workbench-shell", PROJECT_PICKER_WORKBENCH_STORAGE_KEY, Boolean(event.currentTarget?.open));
  });

  $("#project-status-workbench-shell")?.addEventListener("toggle", (event) => {
    setWorkbenchOpen("#project-status-workbench-shell", PROJECT_STATUS_WORKBENCH_STORAGE_KEY, Boolean(event.currentTarget?.open));
  });

  $("#intake-workbench-shell")?.addEventListener("toggle", (event) => {
    setWorkbenchOpen("#intake-workbench-shell", INTAKE_WORKBENCH_STORAGE_KEY, Boolean(event.currentTarget?.open));
  });

  $("#structure-workbench-shell")?.addEventListener("toggle", (event) => {
    setWorkbenchOpen("#structure-workbench-shell", STRUCTURE_WORKBENCH_STORAGE_KEY, Boolean(event.currentTarget?.open));
  });

  $("#expand-workbench-shell")?.addEventListener("toggle", (event) => {
    setWorkbenchOpen("#expand-workbench-shell", EXPAND_WORKBENCH_STORAGE_KEY, Boolean(event.currentTarget?.open));
  });

  $("#write-workbench-shell")?.addEventListener("toggle", (event) => {
    setWorkbenchOpen("#write-workbench-shell", WRITE_WORKBENCH_STORAGE_KEY, Boolean(event.currentTarget?.open));
  });

  $("#translate-workbench-shell")?.addEventListener("toggle", (event) => {
    setWorkbenchOpen("#translate-workbench-shell", TRANSLATE_WORKBENCH_STORAGE_KEY, Boolean(event.currentTarget?.open));
  });

  $("#refine-workbench-shell")?.addEventListener("toggle", (event) => {
    setWorkbenchOpen("#refine-workbench-shell", REFINE_WORKBENCH_STORAGE_KEY, Boolean(event.currentTarget?.open));
  });

  $("#check-workbench-shell")?.addEventListener("toggle", (event) => {
    setWorkbenchOpen("#check-workbench-shell", CHECK_WORKBENCH_STORAGE_KEY, Boolean(event.currentTarget?.open));
  });

  $("#cover-metadata-shell")?.addEventListener("toggle", (event) => {
    if (state.suppressFlowSync) {
      return;
    }
    setWorkbenchOpen("#cover-metadata-shell", COVER_METADATA_WORKBENCH_STORAGE_KEY, Boolean(event.currentTarget?.open));
  });

  $("#cover-visual-shell")?.addEventListener("toggle", (event) => {
    if (state.suppressFlowSync) {
      return;
    }
    setWorkbenchOpen("#cover-visual-shell", COVER_VISUAL_WORKBENCH_STORAGE_KEY, Boolean(event.currentTarget?.open));
  });

  $("#cover-operations-shell")?.addEventListener("toggle", (event) => {
    if (state.suppressFlowSync) {
      return;
    }
    setWorkbenchOpen("#cover-operations-shell", COVER_OPERATIONS_WORKBENCH_STORAGE_KEY, Boolean(event.currentTarget?.open));
  });

  $("#cover-results-shell")?.addEventListener("toggle", (event) => {
    if (state.suppressFlowSync) {
      return;
    }
    setWorkbenchOpen("#cover-results-shell", COVER_RESULTS_WORKBENCH_STORAGE_KEY, Boolean(event.currentTarget?.open));
  });

  $("#cover-kdp-review-shell")?.addEventListener("toggle", (event) => {
    if (state.suppressFlowSync) {
      return;
    }
    setWorkbenchOpen("#cover-kdp-review-shell", COVER_KDP_REVIEW_WORKBENCH_STORAGE_KEY, Boolean(event.currentTarget?.open));
  });

  $("#cover-kdp-fix-shell")?.addEventListener("toggle", (event) => {
    if (state.suppressFlowSync) {
      return;
    }
    setWorkbenchOpen("#cover-kdp-fix-shell", COVER_KDP_FIX_WORKBENCH_STORAGE_KEY, Boolean(event.currentTarget?.open));
  });

  $("#cover-kdp-img-black-shell")?.addEventListener("toggle", (event) => {
    if (state.suppressFlowSync) {
      return;
    }
    setWorkbenchOpen("#cover-kdp-img-black-shell", COVER_KDP_IMG_BLACK_WORKBENCH_STORAGE_KEY, Boolean(event.currentTarget?.open));
  });

  $("#build-workbench-shell")?.addEventListener("toggle", (event) => {
    setBuildWorkbenchOpen(Boolean(event.currentTarget?.open));
  });

  $("#intake-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      const submitterId = event.submitter?.id || "";
      const selectedItem = getSelectedWorkspaceItem();
      const payload = formToObject(event.currentTarget);
      payload.bookName = requireBookName();

      if (submitterId === "intake-create" && selectedItem) {
        throw new Error("这个 BookName 已存在。如果你要修改它，请点“保存项目修改”；如果你要新建，请先换一个新的 BookName。");
      }

      if (submitterId === "intake-save" && !selectedItem) {
        throw new Error("当前 BookName 还不存在。请点“创建项目”来新建。");
      }

      await run("intake", payload);
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#intake-form").addEventListener("input", () => {
    updateIntakeActionState();
  });

  $("#objective-md-editor")?.addEventListener("input", () => {
    const status = $("#objective-md-status");
    if (status && !$("#objective-md-editor")?.disabled) {
      status.textContent = "objective.md 已修改，尚未保存。";
    }
  });

  $("#save-objective-md")?.addEventListener("click", async () => {
    try {
      await saveObjectiveMarkdown();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
      const status = $("#objective-md-status");
      if (status) {
        status.textContent = `保存失败：${error.message}`;
      }
    }
  });

  $("#structure-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      await run("structure", { bookName: requireBookName() });
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#expand-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      const payload = formToObject(event.currentTarget);
      payload.bookName = requireBookName();
      payload.chapter = intOrEmpty(payload.chapter);
      payload.startChapter = intOrEmpty(payload.startChapter);
      payload.endChapter = intOrEmpty(payload.endChapter);
      payload.minSubsections = intOrEmpty(payload.minSubsections);
      payload.maxSubsections = intOrEmpty(payload.maxSubsections);
      await run("expand", payload);
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#write-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      const submitterId = event.submitter?.id || "";
      const isRewriteSubmit = submitterId === "run-write-rewrite";
      const payload = formToObject(event.currentTarget);
      payload.bookName = requireBookName();
      payload.mode = getWriteMode();
      payload.model = (payload.model || getDefaultModelName()).trim();
      payload.chapter = intOrEmpty(payload.chapter);
      payload.startChapter = intOrEmpty(payload.startChapter);
      payload.endChapter = intOrEmpty(payload.endChapter);
      payload.maxTokens = intOrEmpty(payload.maxTokens);
      payload.additionalInstructions = (payload.additionalInstructions || "").trim();

      if (isRewriteSubmit) {
        if (payload.mode !== "chapter") {
          throw new Error("“重写单章并附加说明”只支持单章模式。请先把模式切到“单章”。");
        }
        if (!payload.chapter) {
          throw new Error("请先填写要重写的章节编号。");
        }
        if (!payload.additionalInstructions) {
          throw new Error("请先点击“附加说明”填写重写要求，再点“重写单章并附加说明”。");
        }
        payload.force = true;
      } else {
        payload.additionalInstructions = "";
      }

      await run("write", payload);
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#translate-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      const payload = formToObject(event.currentTarget);
      payload.bookName = requireBookName();
      payload.model = (payload.model || getDefaultModelName()).trim();
      payload.chapter = intOrEmpty(payload.chapter);
      payload.startChapter = intOrEmpty(payload.startChapter);
      payload.endChapter = intOrEmpty(payload.endChapter);

      if (!payload.language) {
        throw new Error("请选择目标语言。");
      }
        if (payload.mode === "chapter" && payload.chapter === undefined) {
          throw new Error("单章翻译需要填写章节编号。");
        }
      if (payload.mode === "range" && (!payload.startChapter || !payload.endChapter)) {
        throw new Error("区间翻译需要同时填写开始和结束章节。");
      }

      await run("translate", payload);
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#refine-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      const payload = formToObject(event.currentTarget);
      payload.bookName = requireBookName();
      payload.model = (payload.model || getDefaultModelName()).trim();
      payload.chapter = intOrEmpty(payload.chapter);
      payload.startChapter = intOrEmpty(payload.startChapter);
      payload.endChapter = intOrEmpty(payload.endChapter);

      if (!payload.language) {
        throw new Error("请选择目标语言。");
      }
      if (!payload.model) {
        throw new Error("请填写模型名称。");
      }
      if (payload.mode === "chapter" && !payload.chapter) {
        throw new Error("单章修饰需要填写章节编号。");
      }
      if (payload.mode === "range" && (!payload.startChapter || !payload.endChapter)) {
        throw new Error("区间修饰需要同时填写开始和结束章节。");
      }

      await run("refine-translation", payload);
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#default-model-name")?.addEventListener("change", (event) => {
    setDefaultModelName(event.currentTarget?.value || "gpt-5.2");
    setStatusBadge("已保存", "success");
    setLog(`默认模型已切换为 ${getDefaultModelName()}。`);
  });

  $("#default-model-name")?.addEventListener("input", (event) => {
    const value = String(event.currentTarget?.value || "").trim();
    if (value) {
      localStorage.setItem(DEFAULT_MODEL_STORAGE_KEY, value);
    }
  });

  $("#default-model-name")?.addEventListener("blur", (event) => {
    setDefaultModelName(event.currentTarget?.value || "gpt-5.2");
  });

  $("#edit-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      const payload = formToObject(event.currentTarget);
      payload.bookName = requireBookName();
      await run("edit", payload);
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#build-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      const payload = formToObject(event.currentTarget);
      payload.bookName = requireBookName();
      payload.language = payload.language || "zh";
      await run("build", payload);
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#build-simple-button").addEventListener("click", async () => {
    try {
      const payload = formToObject($("#build-form"));
      payload.bookName = requireBookName();
      payload.language = payload.language || "zh";
      await run("build-simple", payload);
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#build-simple-toc-button").addEventListener("click", async () => {
    try {
      const payload = formToObject($("#build-form"));
      payload.bookName = requireBookName();
      payload.language = payload.language || "zh";
      await run("build-simple-toc", payload);
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#build-epub-button").addEventListener("click", async () => {
    try {
      const payload = formToObject($("#build-form"));
      payload.bookName = requireBookName();
      payload.language = payload.language || "zh";
      await run("build-epub", payload);
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#build-pdf-button").addEventListener("click", async () => {
    try {
      const payload = formToObject($("#build-form"));
      payload.bookName = requireBookName();
      payload.language = payload.language || "zh";
      await run("build-pdf", payload);
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#build-print-pdf-button").addEventListener("click", async () => {
    try {
      const payload = formToObject($("#build-form"));
      payload.bookName = requireBookName();
      payload.language = payload.language || "zh";
      await run("build-print-pdf", payload);
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#build-output-list").addEventListener("click", async (event) => {
    const button = event.target.closest("[data-output-folder-file]");
    if (!button) {
      return;
    }

    try {
      const result = await api("/api/open-output-folder", {
        method: "POST",
        body: JSON.stringify({
          bookName: requireBookName(),
          fileName: button.dataset.outputFolderFile || ""
        })
      });
      handleOpenTargetResult(result, `已打开生成文件夹：${button.dataset.outputFolderFile || ""}`);
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#publish-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      const submitterId = event.submitter?.id || "";
      const payload = formToObject(event.currentTarget);
      payload.bookName = requireBookName();
      payload.language = payload.language || "zh";
      payload.platform = payload.platform || "all";
      if (submitterId === "run-publish-submit") {
        if (payload.platform === "all") {
          throw new Error("要提交到平台时，请先把“生成范围”改成一个具体平台。");
        }
        if (payload.platform !== "google") {
          payload.attachChrome = false;
          payload.chromeDebugPort = "";
        } else if (payload.attachChrome) {
          const debugPort = Number(payload.chromeDebugPort || 9222);
          if (!Number.isInteger(debugPort) || debugPort <= 0) {
            throw new Error("Chrome 调试端口必须是一个正整数。");
          }
          payload.chromeDebugPort = debugPort;
        } else {
          payload.chromeDebugPort = "";
        }
        payload.mode = "assist";
        await run("submit", payload);
        return;
      }
      await run("publish", payload);
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#run-publish-amazon-details").addEventListener("click", async () => {
    try {
      const payload = formToObject($("#publish-form"));
      payload.bookName = requireBookName();
      payload.language = payload.language || "zh";
      payload.platform = "amazon";
      payload.mode = "details";
      payload.attachChrome = false;
      payload.chromeDebugPort = "";
      await run("submit", payload);
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#run-publish-amazon-content").addEventListener("click", async () => {
    try {
      const payload = formToObject($("#publish-form"));
      payload.bookName = requireBookName();
      payload.language = payload.language || "zh";
      payload.platform = "amazon";
      payload.mode = "content";
      payload.attachChrome = true;
      payload.chromeDebugPort = Number(payload.chromeDebugPort || 9222);
      await run("submit", payload);
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#publish-editor-form").addEventListener("input", () => {
    state.publishEditorDirty = true;
    updatePublishEditorStatus();
    schedulePublishAutoSave();
  });

  $("#save-publish-metadata").addEventListener("click", async () => {
    try {
      clearPublishAutoSaveTimer();
      await savePublishMetadataWithFeedback("manual");
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#save-amazon-description")?.addEventListener("click", async () => {
    try {
      await saveAmazonDescription();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
      updateAmazonDescriptionStatus(`保存失败：${error.message}`);
    }
  });

  $("#publish-language").addEventListener("change", () => {
    const selected = state.workspaces.find((item) => item.bookName === getBookName()) || null;
    clearPublishAutoSaveTimer();
    hidePublishSaveFeedback();
    state.publishEditorDirty = false;
    state.publishLastSavedAt = "";
    renderPublishPanel(selected);
  });

  $("#publish-preview-platform").addEventListener("change", () => {
    localStorage.setItem(PUBLISH_PREVIEW_PLATFORM_STORAGE_KEY, getPublishPreviewPlatform());
    const selected = state.workspaces.find((item) => item.bookName === getBookName()) || null;
    renderPublishPanel(selected);
  });

  $('#publish-form [name="platform"]').addEventListener("change", () => {
    updatePublishSubmitControls();
  });

  $("#publish-attach-chrome").addEventListener("change", () => {
    updatePublishSubmitControls();
  });

  document.querySelector(".publish-raw-toggle")?.addEventListener("toggle", (event) => {
    setPublishRawToggleOpen(Boolean(event.currentTarget?.open));
  });

  document.querySelectorAll("[data-publish-platform-group]").forEach((panel) => {
    panel.addEventListener("toggle", (event) => {
      const currentPanel = event.currentTarget;
      const platformName = currentPanel?.dataset.publishPlatformGroup || "";
      const isOpen = Boolean(currentPanel?.open);
      setPublishPlatformGroupState(platformName, isOpen);
      if (isOpen && platformName) {
        focusPublishPreviewPlatform(platformName);
      }
    });
  });

  $("#open-publish-root").addEventListener("click", async () => {
    try {
      await openPublishRootFolder();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#open-publish-platform").addEventListener("click", async () => {
    try {
      await openPublishPlatformFolder();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#publish-root-path").addEventListener("click", async () => {
    try {
      await openPublishRootFolder();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#publish-platform-path").addEventListener("click", async () => {
    try {
      await openPublishPlatformFolder();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#copy-publish-root-path").addEventListener("click", async () => {
    try {
      await copyTextToClipboard($("#publish-root-path")?.dataset.path || $("#publish-root-path")?.textContent || "");
      setStatusBadge("已复制", "success");
      setLog("已复制语言目录路径。");
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#copy-publish-platform-path").addEventListener("click", async () => {
    try {
      await copyTextToClipboard($("#publish-platform-path")?.dataset.path || $("#publish-platform-path")?.textContent || "");
      setStatusBadge("已复制", "success");
      setLog("已复制平台目录路径。");
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  document.querySelectorAll("[data-publish-asset-action]").forEach((button) => {
    button.addEventListener("click", async (event) => {
      try {
        const platformName = event.currentTarget?.dataset.publishAssetPlatform || "";
        const action = event.currentTarget?.dataset.publishAssetAction || "";
        await openPublishAsset(platformName, action);
      } catch (error) {
        setStatusBadge("失败", "failed");
        setLog(error.message);
      }
    });
  });

  $("#generate-kobo-account-md")?.addEventListener("click", async () => {
    try {
      const result = await api("/api/generate-kobo-account-md", {
        method: "POST",
        body: JSON.stringify({
          bookName: requireBookName(),
          language: getPublishLanguage()
        })
      });
      handleOpenTargetResult(result, "已生成并打开 Kobo 开户基本情况 MD。");
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#cover-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      const payload = buildCoverPayload(event.currentTarget);
      await run("cover", payload);
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  [
    ["#run-cover-drafts", "cover-drafts", "已开始生成 drafts。"],
    ["#run-cover-layout", "cover-layout", "已开始基于当前草稿生成 layout。"],
    ["#run-cover-mockup", "cover-mockup", "已开始基于当前 layout 生成 mockup。"]
  ].forEach(([selector, route, startMessage]) => {
    $(selector)?.addEventListener("click", async () => {
      try {
        setLog(startMessage);
        const form = $("#cover-form");
        if (!form) {
          throw new Error("Cover form not found.");
        }
        const payload = buildCoverPayload(form);
        await run(route, payload);
      } catch (error) {
        setStatusBadge("失败", "failed");
        setLog(error.message);
      }
    });
  });

  [
    ["#run-cover-next-brief", "cover-next-brief", "08N base brief started."],
    ["#run-cover-next-prompt", "cover-next-prompt", "08N prompt package started."],
    ["#run-cover-next-generate", "cover-next-generate", "08N no-text base image generation started."],
    ["#run-cover-next-review", "cover-next-review", "08N base image review started."],
    ["#run-cover-next-layout", "cover-next-layout", "08N title layout started."],
    ["#run-cover-next-print", "cover-next-print", "08N KDP print spread started."],
    ["#run-cover-next-mockup", "cover-next-mockup", "08N mockup started."],
    ["#run-cover-next-export", "cover-next-export", "08N export started."],
    ["#run-cover-next-all", "cover-next", "08N full next cover flow started."]
  ].forEach(([selector, route, startMessage]) => {
    $(selector)?.addEventListener("click", async () => {
      try {
        setLog(startMessage);
        const form = $("#cover-form");
        if (!form) {
          throw new Error("Cover form not found.");
        }
        const payload = buildCoverPayload(form);
        await run(route, payload);
      } catch (error) {
        setStatusBadge("å¤±è´¥", "failed");
        setLog(error.message);
      }
    });
  });

  $("#toggle-cover-panel").addEventListener("click", () => {
    const panel = document.querySelector(".cover-panel");
    const currentlyExpanded = panel ? !panel.classList.contains("collapsed") : false;
    setCoverPanelExpanded(!currentlyExpanded);
  });

  $("#toggle-check-panel")?.addEventListener("click", () => {
    const panel = document.querySelector(".check-panel");
    const currentlyExpanded = panel ? !panel.classList.contains("collapsed") : false;
    setCheckPanelExpanded(!currentlyExpanded);
  });

  $(".check-panel .panel-header")?.addEventListener("click", (event) => {
    if (event.target?.closest?.("button")) {
      return;
    }
    const panel = document.querySelector(".check-panel");
    const currentlyExpanded = panel ? !panel.classList.contains("collapsed") : false;
    setCheckPanelExpanded(!currentlyExpanded);
  });

  $("#toggle-publish-panel").addEventListener("click", () => {
    const panel = document.querySelector(".publish-panel");
    const currentlyExpanded = panel ? !panel.classList.contains("collapsed") : false;
    setPublishPanelExpanded(!currentlyExpanded);
  });

  $("#toggle-publish-preview-column").addEventListener("click", () => {
    const workbench = document.querySelector(".publish-workbench");
    const currentlyExpanded = workbench ? !workbench.classList.contains("preview-collapsed") : true;
    setPublishPreviewColumnExpanded(!currentlyExpanded);
  });

  $("#save-cover-copy").addEventListener("click", async () => {
    try {
      await saveCoverCopy();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#generate-cover-midjourney-prompt")?.addEventListener("click", async () => {
    try {
      await generateCoverMidjourneyPrompt();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#copy-cover-midjourney-prompt")?.addEventListener("click", async () => {
    try {
      await copyCoverMidjourneyPrompt();
    } catch (error) {
      setStatusBadge("å¤±è´¥", "failed");
      setLog(error.message);
    }
  });

  $("#save-cover-midjourney-prompt")?.addEventListener("click", async () => {
    try {
      await saveCoverMidjourneyPrompt();
    } catch (error) {
      setStatusBadge("å¤±è´¥", "failed");
      setLog(error.message);
    }
  });

  ["#cover-midjourney-prompt", "#cover-ai-request", "#cover-edit-text"].forEach((selector) => {
    const field = $(selector);
    field?.addEventListener("input", () => {
      field.dataset.dirty = "1";
    });
  });

  $("#prev-cover-base-import")?.addEventListener("click", async () => {
    try {
      await selectSavedCoverBaseImport(-1);
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#next-cover-base-import")?.addEventListener("click", async () => {
    try {
      await selectSavedCoverBaseImport(1);
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#select-cover-base-import")?.addEventListener("click", () => {
    $("#cover-base-import-file")?.click();
  });

  $("#cover-base-import-file")?.addEventListener("change", async (event) => {
    try {
      await setCoverBaseImportFile(event.currentTarget?.files?.[0] || null);
      event.currentTarget.value = "";
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#save-cover-base-import")?.addEventListener("click", async () => {
    try {
      await saveCoverBaseImport();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#refresh-cover-edit-text")?.addEventListener("click", () => {
    refreshCoverEditText(true);
    setStatusBadge("已刷新", "success");
    setLog("已把书名、副标题、作者和出版社刷新到封面文字栏。");
  });

  $("#run-cover-image-edit")?.addEventListener("click", async () => {
    try {
      await runCoverImageEdit();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  const baseImportDropzone = $("#cover-base-import-dropzone");
  baseImportDropzone?.addEventListener("dragover", (event) => {
    event.preventDefault();
    baseImportDropzone.classList.add("dragging");
  });
  baseImportDropzone?.addEventListener("dragleave", () => {
    baseImportDropzone.classList.remove("dragging");
  });
  baseImportDropzone?.addEventListener("drop", async (event) => {
    event.preventDefault();
    baseImportDropzone.classList.remove("dragging");
    try {
      await setCoverBaseImportFile(getImageFileFromDragEvent(event));
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });
  baseImportDropzone?.addEventListener("paste", async (event) => {
    try {
      const file = getImageFileFromPasteEvent(event);
      if (!file) {
        return;
      }
      event.preventDefault();
      await setCoverBaseImportFile(file);
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#submit-cover-ai-request")?.addEventListener("click", async () => {
    try {
      const requestField = $("#cover-ai-request");
      if (requestField) {
        requestField.dataset.dirty = "1";
      }
      await submitCoverAiRequest();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
      const responseField = $("#cover-ai-response");
      if (responseField) {
        responseField.value = `请求失败：${error.message}`;
      }
    }
  });

  $("#save-frontmatter").addEventListener("click", async () => {
    try {
      await saveFrontmatter();
    } catch (error) {
      setStatusBadge("å¤±è´¥", "failed");
      setLog(error.message);
    }
  });

  $("#refresh-status").addEventListener("click", async () => {
    try {
      await refreshStatus();
      await refreshAccount({ quiet: true });
      await refreshUsers({ quiet: true });
      await refreshAudit({ quiet: true });
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#refresh-account")?.addEventListener("click", async () => {
    try {
      await refreshAccount();
    } catch (error) {
      setAccountFeedback(error.message, "error");
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#change-password-form")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      await changeOwnPasswordFromForm(event.currentTarget);
      setStatusBadge("密码已修改", "success");
      await refreshAccount({ quiet: true });
      await refreshAudit({ quiet: true });
    } catch (error) {
      setAccountFeedback(error.message, "error");
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#refresh-users")?.addEventListener("click", async () => {
    try {
      await refreshUsers();
      await refreshAudit({ quiet: true });
    } catch (error) {
      setUserAdminFeedback(error.message, "error");
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#audit-filter-form")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      await refreshAudit();
      setStatusBadge("审计已刷新", "success");
    } catch (error) {
      setUserAdminFeedback(error.message, "error");
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#create-user-form")?.addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      await createUserFromForm(event.currentTarget);
      setStatusBadge("用户已创建", "success");
    } catch (error) {
      setUserAdminFeedback(error.message, "error");
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  document.querySelector('#create-user-form input[name="initialCredits"]')?.addEventListener("input", (event) => {
    event.currentTarget.dataset.touched = "true";
  });

  $("#filter-negative-users")?.addEventListener("change", (event) => {
    state.userFilterNegative = Boolean(event.currentTarget.checked);
    renderUserAdminPanel();
  });

  $("#user-list")?.addEventListener("click", async (event) => {
    const roleButton = event.target.closest(".user-update-role");
    const toggleButton = event.target.closest(".user-toggle-disabled");
    const billingButton = event.target.closest(".user-view-billing");
    if (!roleButton && !toggleButton && !billingButton) {
      return;
    }

    try {
      if (billingButton) {
        const userId = billingButton.dataset.userId || "";
        await refreshUserBillingEvents(userId);
        setStatusBadge("流水已加载", "success");
        return;
      }

      if (roleButton) {
        const item = roleButton.closest(".user-item");
        const role = item?.querySelector("[data-user-role]")?.value || "user";
        const userId = roleButton.dataset.userId || "";
        await updateUserFromPanel(userId, { role }, `已修改角色：${getRoleLabel(role)}`);
        setStatusBadge("角色已修改", "success");
        return;
      }

      const userId = toggleButton.dataset.userId || "";
      const disabled = toggleButton.dataset.disabled === "true";
      await updateUserFromPanel(userId, { disabled }, disabled ? "用户已禁用" : "用户已启用");
      setStatusBadge(disabled ? "用户已禁用" : "用户已启用", "success");
    } catch (error) {
      setUserAdminFeedback(error.message, "error");
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#user-list")?.addEventListener("submit", async (event) => {
    const passwordForm = event.target.closest(".user-reset-password-form");
    const billingForm = event.target.closest(".user-billing-adjust-form");
    if (!passwordForm && !billingForm) {
      return;
    }
    event.preventDefault();
    try {
      if (billingForm) {
        await adjustUserCreditsFromForm(billingForm);
        setStatusBadge("积分已调整", "success");
        return;
      }
      await resetUserPasswordFromForm(passwordForm);
      setStatusBadge("密码已重置", "success");
    } catch (error) {
      setUserAdminFeedback(error.message, "error");
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#refresh-health")?.addEventListener("click", async () => {
    try {
      const health = await refreshSystemHealth();
      setStatusBadge(health.summary === "fail" ? "自检失败" : health.summary === "warn" ? "自检警告" : "自检通过", health.summary === "fail" ? "failed" : "success");
      setLog((health.checks || []).map((item) => `${getHealthStatusText(item.status)} ${item.label}: ${item.message}`).join("\n"));
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#cancel-current-job")?.addEventListener("click", async () => {
    try {
      await cancelCurrentJob();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#show-toc").addEventListener("click", async () => {
    try {
      await showCurrentTocPreview();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#save-toc").addEventListener("click", async () => {
    try {
      await saveCurrentToc();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#show-chapter").addEventListener("click", async () => {
    try {
      await showCurrentChapter();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#save-chapter").addEventListener("click", async () => {
    try {
      await saveCurrentChapter();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#chapter-preview").addEventListener("input", () => {
    updateChapterSaveState();
  });

  $("#rewrite-current-chapter").addEventListener("click", () => {
    jumpToRewriteCurrentChapter();
  });

  $("#open-write-notes").addEventListener("click", () => {
    if (getWriteMode() !== "chapter") {
      setStatusBadge("失败", "failed");
      setLog("附加说明目前只在“单章”模式下使用。请先把 03 写章节 的模式切到“单章”。");
      return;
    }
    openWriteNotesModal();
  });

  $("#close-write-notes").addEventListener("click", closeWriteNotesModal);
  $("#save-write-notes").addEventListener("click", saveWriteNotes);

  $("#clear-write-notes").addEventListener("click", () => {
    const editor = $("#write-notes-editor");
    if (editor) {
      editor.value = "";
    }
    const hiddenField = $("#additional-instructions");
    if (hiddenField) {
      hiddenField.value = "";
    }
    setWriteNotesStatus();
  });

  document.querySelectorAll("[data-close-write-notes='true']").forEach((element) => {
    element.addEventListener("click", closeWriteNotesModal);
  });

  $('#write-form [name="mode"]').addEventListener("change", () => {
    if (getWriteMode() !== "chapter") {
      closeWriteNotesModal();
    }
  });

  $("#chapter-prev").addEventListener("click", () => {
    const selected = state.workspaces.find((item) => item.bookName === getBookName());
    selectRelativeChapter(-1, selected || null);
  });

  $("#chapter-next").addEventListener("click", () => {
    const selected = state.workspaces.find((item) => item.bookName === getBookName());
    selectRelativeChapter(1, selected || null);
  });

  $("#chapter-preview-select").addEventListener("change", () => {
    const selected = state.workspaces.find((item) => item.bookName === getBookName());
    const chapterList = selected ? (state.chapterListCache[selected.bookName] || selected.chapterFiles || []) : [];
    updateChapterNavButtons(selected || null, chapterList);
    updateChapterSaveState();
  });

  $("#bookName").addEventListener("input", () => {
    setRememberedBookName(getBookName());
    const selected = state.workspaces.find((item) => item.bookName === getBookName());
    state.selectedRunKey = "";
    renderWorkspaceSelection(selected || null);
  });

  $("#select-kdp-pdf")?.addEventListener("click", () => {
    $("#kdp-pdf-file")?.click();
  });

  $("#kdp-pdf-file")?.addEventListener("change", async (event) => {
    const file = event.currentTarget?.files?.[0] || null;
    state.kdpAcceptanceFile = file;
    if (file) {
      const selectedSource = getKdpLocalUploadSourceMetadata(file);
      setKdpSourceMetadata(selectedSource);
      const selectedType = selectedSource?.type || "PDF";
      renderKdpCurrentFileMeta({
        status: "已选择本地文件，等待提交/加载。",
        type: selectedType,
        fileName: selectedSource.fileName,
        path: selectedSource.directory,
        detail: formatFileSize(file.size)
      });
    } else {
      setKdpSourceMetadata(null);
      renderKdpCurrentFileMeta();
    }
    if (file && getKdpFileTypeLabel(file.name, file.type === "image/png" ? "PNG" : "") === "PNG") {
      try {
        setStatusBadge("保存中", "running");
        await submitKdpAcceptancePng(file);
      } catch (error) {
        setStatusBadge("失败", "failed");
        setLog(error.message);
      }
      return;
    }
    if (file) {
      return;
    }
    const selected = getSelectedWorkspaceItem();
    const acceptance = selected
      ? (state.coverCache[selected.bookName]?.kdpAcceptance || selected.coverArtifacts?.kdpAcceptance || null)
      : null;
    renderKdpAcceptancePanel(selected || null, acceptance);
  });

  ["#kdp-page-count", "#kdp-paper-type"].forEach((selector) => {
    const field = $(selector);
    field?.addEventListener("input", () => {
      updateKdpGuidePreview();
      state.kdpPdf.spec = getCurrentKdpGuideSpec();
      applyKdpLineVariables($("#kdp-pdf-overlay"), state.kdpPdf.spec);
    });
    field?.addEventListener("change", () => {
      updateKdpGuidePreview();
      state.kdpPdf.spec = getCurrentKdpGuideSpec();
      applyKdpLineVariables($("#kdp-pdf-overlay"), state.kdpPdf.spec);
    });
  });

  $("#kdp-pdf-zoom-out")?.addEventListener("click", async () => {
    try {
      await zoomKdpPdf(-0.15);
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#kdp-pdf-zoom-in")?.addEventListener("click", async () => {
    try {
      await zoomKdpPdf(0.15);
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#kdp-pdf-fit")?.addEventListener("click", async () => {
    try {
      await fitKdpPdfToWidth();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#kdp-pdf-actual")?.addEventListener("click", async () => {
    try {
      await setKdpPdfActualSize();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#kdp-ocr-text")?.addEventListener("click", async () => {
    try {
      await recognizeKdpTextRegions();
    } catch (error) {
      $("#kdp-ocr-text")?.removeAttribute("disabled");
      setStatusBadge("失败", "failed");
      setLog(error.message);
      setKdpPdfViewerStatus("OCR 失败");
    }
  });

  $("#kdp-llm-text")?.addEventListener("click", async () => {
    try {
      await recognizeKdpTextRegionsWithLlm();
    } catch (error) {
      $("#kdp-llm-text")?.removeAttribute("disabled");
      setStatusBadge("失败", "failed");
      appendLog(`LLM text-region inspection failed: ${error.message}`);
      setKdpPdfViewerStatus("LLM 识别失败");
    }
  });

  $("#kdp-generate-fix-report")?.addEventListener("click", async () => {
    const button = $("#kdp-generate-fix-report");
    try {
      button?.setAttribute("disabled", "true");
      await generateKdpFixReport();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    } finally {
      button?.removeAttribute("disabled");
    }
  });

  $("#kdp-generate-fix-prompt")?.addEventListener("click", () => {
    try {
      generateKdpFixCommandPrompt();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#kdp-img-black-load-source")?.addEventListener("click", () => {
    try {
      loadKdpImgBlackSourceToWorkarea();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  [
    "#kdp-img-black-crop-x",
    "#kdp-img-black-crop-y",
    "#kdp-img-black-crop-width",
    "#kdp-img-black-crop-height",
    "#kdp-img-black-resize-percent",
    "#kdp-img-black-composite-x",
    "#kdp-img-black-composite-y"
  ].forEach((selector) => {
    $(selector)?.addEventListener("input", () => persistKdpImgBlackUiState());
  });

  $("#kdp-img-black-crop-source")?.addEventListener("click", async () => {
    const button = $("#kdp-img-black-crop-source");
    try {
      button?.setAttribute("disabled", "true");
      await cropKdpImgBlackSourceRegion();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    } finally {
      button?.removeAttribute("disabled");
    }
  });

  $("#kdp-img-black-resize-source")?.addEventListener("click", async () => {
    const button = $("#kdp-img-black-resize-source");
    try {
      button?.setAttribute("disabled", "true");
      await resizeKdpImgBlackCropImage();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    } finally {
      button?.removeAttribute("disabled");
    }
  });

  $("#kdp-img-black-fill-preset")?.addEventListener("change", () => {
    const preset = $("#kdp-img-black-fill-preset")?.value || "";
    const colorField = $("#kdp-img-black-fill-color");
    if (colorField && preset && preset !== "custom") {
      colorField.value = preset;
    }
    persistKdpImgBlackUiState({ immediate: true });
  });

  $("#kdp-img-black-fill-mode")?.addEventListener("change", () => {
    persistKdpImgBlackUiState({ immediate: true });
  });

  $("#kdp-img-black-fill-color")?.addEventListener("input", () => {
    const preset = $("#kdp-img-black-fill-preset");
    if (preset) preset.value = "custom";
    persistKdpImgBlackUiState();
  });

  $("#kdp-img-black-fill-source")?.addEventListener("click", async () => {
    const button = $("#kdp-img-black-fill-source");
    try {
      button?.setAttribute("disabled", "true");
      await fillKdpImgBlackSourceRegion();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    } finally {
      button?.removeAttribute("disabled");
    }
  });

  $("#kdp-img-black-composite-source")?.addEventListener("click", async () => {
    const button = $("#kdp-img-black-composite-source");
    try {
      button?.setAttribute("disabled", "true");
      await compositeKdpImgBlackImages();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    } finally {
      button?.removeAttribute("disabled");
    }
  });

  $("#kdp-img-black-png-to-pdf")?.addEventListener("click", async () => {
    const button = $("#kdp-img-black-png-to-pdf");
    try {
      button?.setAttribute("disabled", "true");
      await convertKdpImgBlackCompositePngToPdf();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    } finally {
      button?.removeAttribute("disabled");
    }
  });

  $("#kdp-generate-imagemagick-instructions")?.addEventListener("click", () => {
    try {
      generateKdpImageMagickInstructions();
    } catch (error) {
      setStatusBadge("å¤±è´¥", "failed");
      setLog(error.message);
    }
  });

  $("#kdp-prepare-fix-workbench")?.addEventListener("click", async () => {
    const button = $("#kdp-prepare-fix-workbench");
    try {
      button?.setAttribute("disabled", "true");
      await prepareKdpFixWorkbench();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    } finally {
      button?.removeAttribute("disabled");
    }
  });

  $("#kdp-run-fix-workbench")?.addEventListener("click", async () => {
    const button = $("#kdp-run-fix-workbench");
    try {
      button?.setAttribute("disabled", "true");
      await runKdpFixWorkbench();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    } finally {
      button?.removeAttribute("disabled");
    }
  });

  $("#kdp-run-imagemagick-fix")?.addEventListener("click", async () => {
    const button = $("#kdp-run-imagemagick-fix");
    try {
      button?.setAttribute("disabled", "true");
      await runKdpImageMagickFixWorkbench();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    } finally {
      button?.removeAttribute("disabled");
    }
  });

  $("#kdp-submit-fixed-output")?.addEventListener("click", async () => {
    const button = $("#kdp-submit-fixed-output");
    try {
      button?.setAttribute("disabled", "true");
      await submitKdpFixedOutputForAcceptance();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    } finally {
      button?.removeAttribute("disabled");
    }
  });

  $("#submit-kdp-pdf")?.addEventListener("click", async () => {
    try {
      await submitKdpAcceptancePdf();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#open-kdp-acceptance-folder")?.addEventListener("click", async () => {
    try {
      await openKdpAcceptanceDirectoryAndList();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#kdp-acceptance-file-list")?.addEventListener("click", async (event) => {
    const button = event.target?.closest?.("[data-kdp-file]");
    if (!button) return;
    try {
      await useKdpAcceptanceDirectoryFile(button.dataset.kdpFile || "", button.dataset.kdpType || "");
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  [
    ["#open-cover-drafts", "drafts"],
    ["#open-cover-layout", "layout"],
    ["#open-cover-mockup", "mockup"],
    ["#open-cover-final", "final"]
  ].forEach(([selector, section]) => {
    const button = document.querySelector(selector);
    if (!button) {
      return;
    }
    button.addEventListener("click", async () => {
      try {
        const bookName = requireBookName();
        const result = await api("/api/open-cover-folder", {
          method: "POST",
          body: JSON.stringify({ bookName, section })
        });
        handleOpenTargetResult(result, `已打开封面目录：${section}`);
      } catch (error) {
        setStatusBadge("失败", "failed");
        setLog(error.message);
      }
    });
  });

  [
    ["#open-cover-next-imports", "next-imports"],
    ["#open-cover-next-layout", "next-layout"],
    ["#open-cover-next-print-spread", "next-print-spread"],
    ["#open-cover-next-mockup", "next-mockup"],
    ["#open-cover-next-final", "next-final"]
  ].forEach(([selector, section]) => {
    const button = document.querySelector(selector);
    if (!button) {
      return;
    }
    button.addEventListener("click", async () => {
      try {
        const bookName = requireBookName();
        const result = await api("/api/open-cover-folder", {
          method: "POST",
          body: JSON.stringify({ bookName, section })
        });
        handleOpenTargetResult(result, `已打开封面目录：${section}`);
      } catch (error) {
        setStatusBadge("失败", "failed");
        setLog(error.message);
      }
    });
  });
}

async function init() {
initWorkbenchState("#project-picker-workbench-shell", PROJECT_PICKER_WORKBENCH_STORAGE_KEY, true);
initWorkbenchState("#project-status-workbench-shell", PROJECT_STATUS_WORKBENCH_STORAGE_KEY);
initWorkbenchState("#account-workbench-shell", ACCOUNT_WORKBENCH_STORAGE_KEY);
initWorkbenchState("#user-admin-workbench-shell", USER_ADMIN_WORKBENCH_STORAGE_KEY);
initWorkbenchState("#intake-workbench-shell", INTAKE_WORKBENCH_STORAGE_KEY);
initWorkbenchState("#structure-workbench-shell", STRUCTURE_WORKBENCH_STORAGE_KEY);
initWorkbenchState("#expand-workbench-shell", EXPAND_WORKBENCH_STORAGE_KEY);
initWorkbenchState("#write-workbench-shell", WRITE_WORKBENCH_STORAGE_KEY);
initWorkbenchState("#translate-workbench-shell", TRANSLATE_WORKBENCH_STORAGE_KEY);
initWorkbenchState("#refine-workbench-shell", REFINE_WORKBENCH_STORAGE_KEY);
initWorkbenchState("#check-workbench-shell", CHECK_WORKBENCH_STORAGE_KEY);
initWorkbenchState("#cover-metadata-shell", COVER_METADATA_WORKBENCH_STORAGE_KEY);
initWorkbenchState("#cover-visual-shell", COVER_VISUAL_WORKBENCH_STORAGE_KEY);
initWorkbenchState("#cover-operations-shell", COVER_OPERATIONS_WORKBENCH_STORAGE_KEY);
initWorkbenchState("#cover-results-shell", COVER_RESULTS_WORKBENCH_STORAGE_KEY);
initWorkbenchState("#cover-kdp-review-shell", COVER_KDP_REVIEW_WORKBENCH_STORAGE_KEY);
initWorkbenchState("#cover-kdp-fix-shell", COVER_KDP_FIX_WORKBENCH_STORAGE_KEY);
initWorkbenchState("#cover-kdp-img-black-shell", COVER_KDP_IMG_BLACK_WORKBENCH_STORAGE_KEY);
initCheckPanelState();
initCoverPanelState();
initBuildWorkbenchState();
initPublishPanelState();
initPublishPreviewColumnState();
initPublishUiState();
setDefaultModelName(getStoredDefaultModelName());
updateCancelJobButton(false);
  setupForms();
  initFlowNavigation();
  setWriteNotesStatus();
  try {
    await refreshStatus();
    await refreshAccount({ quiet: true });
    await refreshUsers({ quiet: true });
    await refreshAudit({ quiet: true });
    try {
      await refreshSystemHealth();
    } catch {
      // Health failures are rendered in the health card; they should not block the workbench.
    }
    await restoreActiveJob();
  } catch (error) {
    setStatusBadge("失败", "failed");
    setLog(error.message);
  }
}

init();
