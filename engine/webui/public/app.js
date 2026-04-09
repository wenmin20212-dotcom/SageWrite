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
  coverCopyCache: {},
  coverCopyLoadingBook: "",
  frontmatterCache: {},
  frontmatterLoadingBook: "",
  chapterListCache: {},
  chapterContentCache: {},
  chapterListLoadingBook: "",
  chapterContentLoadingKey: ""
};

const COVER_PANEL_STORAGE_KEY = "sagewrite-cover-panel-expanded";

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
  form.querySelectorAll('input[type="checkbox"]').forEach((input) => {
    obj[input.name] = input.checked;
  });
  return obj;
}

function setStatusBadge(text, kind = "idle") {
  const badge = $("#job-badge");
  badge.textContent = text;
  badge.dataset.kind = kind;
}

function setLog(text) {
  $("#log-output").textContent = text || "这里会显示 PowerShell 输出。";
}

function getBookName() {
  return $("#bookName").value.trim();
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

function initCoverPanelState() {
  const stored = localStorage.getItem(COVER_PANEL_STORAGE_KEY);
  setCoverPanelExpanded(stored === "1");
}

function getWriteMode() {
  const field = $('#write-form [name="mode"]');
  return field ? field.value : "all";
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
    throw new Error(data.error || "请求失败。");
  }
  return data;
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
  setFormValue('#intake-form [name="author"]', objective.author || "");
  setFormValue('#intake-form [name="audience"]', objective.audience || "");
  setFormValue('#intake-form [name="type"]', objective.type || "");
  setFormValue('#intake-form [name="coreThesis"]', objective.core_thesis || "");
  setFormValue('#intake-form [name="scope"]', objective.scope || "");
  setFormValue('#intake-form [name="style"]', objective.style || "");
  updateIntakeActionState(item);
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
            <button class="ghost-button cover-file-button" type="button" data-cover-section="${escapeHtml(section)}" data-cover-file="${escapeHtml(fileName)}">定位文件</button>
          </div>
        </div>
      </div>
    `;
  }).join("");

  panel.querySelectorAll("[data-cover-file]").forEach((button) => {
    button.addEventListener("click", async () => {
      try {
        const currentBookName = requireBookName();
        await api("/api/reveal-cover-file", {
          method: "POST",
          body: JSON.stringify({
            bookName: currentBookName,
            section: button.dataset.coverSection,
            fileName: button.dataset.coverFile
          })
        });
        setStatusBadge("已定位", "success");
        setLog(`已在资源管理器中定位封面文件：${button.dataset.coverFile}`);
      } catch (error) {
        setStatusBadge("失败", "failed");
        setLog(error.message);
      }
    });
  });
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
    return;
  }

  if (!artifacts) {
    summary.textContent = "当前项目还没有 07_cover 输出。";
    report.value = "当前项目还没有生成 cover_report.md。";
    renderCoverGallerySection("#cover-drafts", item.bookName, "drafts", []);
    renderCoverGallerySection("#cover-layout", item.bookName, "layout", []);
    renderCoverGallerySection("#cover-mockup", item.bookName, "mockup", []);
    renderCoverGallerySection("#cover-final", item.bookName, "final", []);
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
      selectedReviewFiles: [],
      topCandidate: "",
      reportText: `读取封面结果失败：${error.message}`
    };
  } finally {
    state.coverLoadingBook = "";
    renderCoverPanel(item);
  }
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
      <em>${item.outputFiles.length || 0} 个输出文档</em>
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

  const getFolderLabel = (fileName) => {
    const normalized = String(fileName || "").replaceAll("\\", "/");
    const parts = normalized.split("/");
    if (parts.length <= 1) {
      return "位于 04_output 目录";
    }
    return `位于 04_output/${escapeHtml(parts.slice(0, -1).join("/"))} 目录`;
  };

  panel.innerHTML = outputFiles.map((fileName) => `
    <div class="build-output-item">
      <div class="build-output-meta">
        <strong>${escapeHtml(fileName)}</strong>
        <span>${getFolderLabel(fileName)}</span>
      </div>
      <div class="build-output-actions">
        <button
          type="button"
          class="ghost-button build-open-button"
          data-reveal-output="${escapeHtml(fileName)}"
        >
          定位文件
        </button>
        <button
          type="button"
          class="ghost-button build-open-button"
          data-open-folder="${escapeHtml(fileName)}"
        >
          打开文件夹
        </button>
      </div>
    </div>
  `).join("");

  panel.querySelectorAll("[data-reveal-output]").forEach((button) => {
    button.addEventListener("click", async () => {
      try {
        const bookName = requireBookName();
        const fileName = button.dataset.revealOutput || "";
        await api("/api/reveal-output", {
          method: "POST",
          body: JSON.stringify({ bookName, fileName })
        });
        setStatusBadge("已定位", "success");
        setLog(`已在资源管理器中定位文件：${fileName}`);
      } catch (error) {
        setStatusBadge("失败", "failed");
        setLog(error.message);
      }
    });
  });

  panel.querySelectorAll("[data-open-folder]").forEach((button) => {
    button.addEventListener("click", async () => {
      try {
        const bookName = requireBookName();
        const fileName = button.dataset.openFolder || "";
        await api("/api/open-output-folder", {
          method: "POST",
          body: JSON.stringify({ bookName, fileName })
        });
        setStatusBadge("已打开", "success");
        setLog(`已打开输出文件夹，可查看文件：${fileName}`);
      } catch (error) {
        setStatusBadge("失败", "failed");
        setLog(error.message);
      }
    });
  });
}

function renderWorkspaceSelection(item) {
  renderIntakePreview(item);
  renderProjectStatus(item);
  renderTocPreview(item);
  renderPreflightReport(item);
  renderChapterBrowser(item);
  renderBuildOutputs(item);
  renderCoverPanel(item);
  renderCoverCopyEditor(item);
  renderFrontmatterEditor(item);
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
    `;
    button.addEventListener("click", () => {
      $("#bookName").value = item.bookName;
      state.selectedRunKey = "";
      renderWorkspaceSelection(item);
    });
    wrap.appendChild(button);
  });

  const selected = workspaces.find((item) => item.bookName === getBookName());
  renderWorkspaceSelection(selected || null);
}

async function refreshStatus() {
  const status = await api("/api/status");
  $("#api-key-status").textContent = status.hasOpenAIKey ? "已配置" : "未配置";
  $("#workspace-count").textContent = String(status.workspaces.length);
  renderWorkspaces(status.workspaces);
}

async function pollJob(jobId) {
  if (state.pollTimer) {
    clearTimeout(state.pollTimer);
  }

  const job = await api(`/api/jobs/${jobId}`);
  state.currentJobId = job.id;
  setLog(job.output);

  if (job.status === "running") {
    setStatusBadge("运行中", "running");
    state.pollTimer = setTimeout(() => pollJob(jobId), 1200);
    return;
  }

  setStatusBadge(job.status === "success" ? "成功" : "失败", job.status === "success" ? "success" : "failed");
  if (job.meta?.route === "edit" && job.meta?.bookName) {
    delete state.preflightCache[job.meta.bookName];
  }
  if (job.meta?.route === "cover" && job.meta?.bookName) {
    delete state.coverCache[job.meta.bookName];
    delete state.coverCopyCache[job.meta.bookName];
    delete state.frontmatterCache[job.meta.bookName];
  }
  await refreshStatus();
  if (job.meta?.route === "edit" && job.meta?.bookName) {
    const selected = state.workspaces.find((item) => item.bookName === job.meta.bookName) || null;
    if (selected) {
      loadPreflightReport(selected);
    }
  }
  if (job.meta?.route === "cover" && job.meta?.bookName) {
    const selected = state.workspaces.find((item) => item.bookName === job.meta.bookName) || null;
    if (selected) {
      loadCoverArtifacts(selected);
      loadCoverCopy(selected);
      loadFrontmatter(selected);
    }
  }
}

async function run(route, payload) {
  setStatusBadge("提交中", "running");
  setLog("正在启动脚本，请稍候...");
  const result = await api(`/api/run/${route}`, {
    method: "POST",
    body: JSON.stringify(payload)
  });
  await pollJob(result.jobId);
}

function intOrEmpty(value) {
  return value ? Number(value) : undefined;
}

function setupForms() {
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
      payload.chapter = intOrEmpty(payload.chapter);
      payload.startChapter = intOrEmpty(payload.startChapter);
      payload.endChapter = intOrEmpty(payload.endChapter);

      if (!payload.language) {
        throw new Error("请选择目标语言。");
      }
      if (payload.mode === "chapter" && !payload.chapter) {
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

  $("#cover-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      const payload = formToObject(event.currentTarget);
      payload.bookName = requireBookName();
      payload.variants = intOrEmpty(payload.variants) || 4;
      await run("cover", payload);
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
    }
  });

  $("#toggle-cover-panel").addEventListener("click", () => {
    const panel = document.querySelector(".cover-panel");
    const currentlyExpanded = panel ? !panel.classList.contains("collapsed") : false;
    setCoverPanelExpanded(!currentlyExpanded);
  });

  $("#save-cover-copy").addEventListener("click", async () => {
    try {
      await saveCoverCopy();
    } catch (error) {
      setStatusBadge("失败", "failed");
      setLog(error.message);
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
    const selected = state.workspaces.find((item) => item.bookName === getBookName());
    state.selectedRunKey = "";
    renderWorkspaceSelection(selected || null);
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
        await api("/api/open-cover-folder", {
          method: "POST",
          body: JSON.stringify({ bookName, section })
        });
        setStatusBadge("已打开", "success");
        setLog(`已打开封面目录：${section}`);
      } catch (error) {
        setStatusBadge("失败", "failed");
        setLog(error.message);
      }
    });
  });
}

async function init() {
  initCoverPanelState();
  setupForms();
  setWriteNotesStatus();
  try {
    await refreshStatus();
  } catch (error) {
    setStatusBadge("失败", "failed");
    setLog(error.message);
  }
}

init();
