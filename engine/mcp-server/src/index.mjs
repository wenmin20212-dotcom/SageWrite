import fs from 'node:fs/promises';
import path from 'node:path';
import { McpServer } from '@modelcontextprotocol/server';
import { serveStdio } from '@modelcontextprotocol/server/stdio';
import * as z from 'zod/v4';
import { resolveBookRoot, runSageWriteScript, toolResult } from './runner.mjs';

const bookName = z.string().min(1).max(120).describe('SageWrite book project name');
const workspaceRoot = z.string().min(1).optional().describe('Optional parent folder that contains workspace-<bookName>');
const language = z.string().min(2).max(32).default('zh');
const chapterRange = {
  chapter: z.number().int().positive().optional(),
  startChapter: z.number().int().positive().optional(),
  endChapter: z.number().int().positive().optional()
};

function scriptTool(server, name, description, schema, scriptName, mapParameters, timeoutMs) {
  server.registerTool(name, { description, inputSchema: schema }, async (input) => {
    try {
      const result = await runSageWriteScript(scriptName, mapParameters(input), {
        workspaceRoot: input.workspaceRoot,
        timeoutMs
      });
      return toolResult(scriptName, result);
    } catch (error) {
      return {
        content: [{ type: 'text', text: error instanceof Error ? error.message : String(error) }],
        isError: true
      };
    }
  });
}

function createServer() {
  const server = new McpServer({ name: 'sagewrite', version: '1.0.0' });

  scriptTool(server, 'sagewrite_workflow_status', 'Inspect book progress locally without an LLM: map TOC units, identify missing drafts, inspect native format fingerprint freshness, and inventory review/reference/export evidence. Default read-only and compact. saveReport writes a unique advisory JSON only; it does not approve or modify manuscripts. Call again after a batch to refresh.', z.object({
    bookName, workspaceRoot, language,
    saveReport: z.boolean().default(false), details: z.boolean().default(false)
  }), 'Get-SageWriteWorkflowStatus.ps1', (i) => ({
    BookName: i.bookName, Language: i.language, SaveReport: i.saveReport, Details: i.details
  }), 120_000);

  server.registerTool('sagewrite_project_status', {
    description: 'Inspect an existing SageWrite project without modifying it.',
    inputSchema: z.object({ bookName, workspaceRoot })
  }, async ({ bookName: name, workspaceRoot: root }) => {
    try {
      const bookRoot = resolveBookRoot(name, root);
      const entries = await fs.readdir(bookRoot, { withFileTypes: true });
      const statusPath = path.join(bookRoot, 'logs', 'status.json');
      let status = null;
      try { status = JSON.parse(await fs.readFile(statusPath, 'utf8')); } catch {}
      const payload = {
        exists: true,
        bookRoot,
        directories: entries.filter((entry) => entry.isDirectory()).map((entry) => entry.name),
        files: entries.filter((entry) => entry.isFile()).map((entry) => entry.name),
        status
      };
      return { content: [{ type: 'text', text: JSON.stringify(payload, null, 2) }], structuredContent: payload };
    } catch (error) {
      const payload = { exists: false, error: error instanceof Error ? error.message : String(error) };
      return { content: [{ type: 'text', text: JSON.stringify(payload, null, 2) }], structuredContent: payload };
    }
  });

  scriptTool(server, 'sagewrite_import_structure', 'Split a large DOCX or Markdown manuscript into one unchanged Markdown file per chapter. No LLM is used. Use Preview before Apply.', z.object({
    bookName, workspaceRoot,
    sourcePath: z.string().min(1),
    mode: z.enum(['Preview', 'Apply']).default('Preview'),
    chapterHeadingLevel: z.number().int().min(1).max(6).default(1),
    chapterPattern: z.string().optional(),
    title: z.string().optional(), subtitle: z.string().optional(), author: z.string().optional(),
    skipFirstHeading: z.boolean().default(false),
    force: z.boolean().default(false)
  }), '01b-import-structure.ps1', (i) => ({
    BookName: i.bookName, SourcePath: i.sourcePath, Mode: i.mode,
    ChapterHeadingLevel: i.chapterHeadingLevel, ChapterPattern: i.chapterPattern,
    Title: i.title, Subtitle: i.subtitle, Author: i.author,
    SkipFirstHeading: i.skipFirstHeading, Force: i.force
  }));

  scriptTool(server, 'sagewrite_initialize_book', 'Create a SageWrite book workspace and objective brief.', z.object({
    bookName, workspaceRoot,
    title: z.string().min(1), subtitle: z.string().default(''), author: z.string().default(''),
    audience: z.string().min(1), type: z.string().min(1), coreThesis: z.string().min(1),
    scope: z.string().min(1), style: z.string().min(1)
  }), '01-intake.ps1', (i) => ({
    BookName: i.bookName, Title: i.title, Subtitle: i.subtitle, Author: i.author,
    Audience: i.audience, Type: i.type, CoreThesis: i.coreThesis, Scope: i.scope, Style: i.style
  }));

  scriptTool(server, 'sagewrite_generate_toc', 'Generate toc.md from the book objective using the configured LLM provider.', z.object({
    bookName, workspaceRoot
  }), '02-structure.ps1', (i) => ({ BookName: i.bookName }));

  scriptTool(server, 'sagewrite_expand_outline', 'Expand one chapter, a chapter range, or all chapters in toc.md.', z.object({
    bookName, workspaceRoot, ...chapterRange,
    all: z.boolean().default(false), minSubsections: z.number().int().min(1).default(3),
    maxSubsections: z.number().int().min(1).default(5), model: z.string().optional()
  }), '02b-expand.ps1', (i) => ({
    BookName: i.bookName, Chapter: i.chapter, StartChapter: i.startChapter, EndChapter: i.endChapter,
    All: i.all, MinSubsections: i.minSubsections, MaxSubsections: i.maxSubsections, Model: i.model
  }));

  scriptTool(server, 'sagewrite_write_chapters', 'Write one chapter or a chapter range using the configured LLM provider.', z.object({
    bookName, workspaceRoot, ...chapterRange,
    maxTokens: z.number().int().positive().default(7000), additionalInstructions: z.string().optional(),
    referenceGlossary: z.boolean().default(false), force: z.boolean().default(false), model: z.string().optional()
  }), '03-write.ps1', (i) => ({
    BookName: i.bookName, Chapter: i.chapter, StartChapter: i.startChapter, EndChapter: i.endChapter,
    MaxTokens: i.maxTokens, AdditionalInstructions: i.additionalInstructions,
    ReferenceGlossary: i.referenceGlossary, Force: i.force, Model: i.model
  }));

  scriptTool(server, 'sagewrite_rewrite_chapters', 'Revise existing chapters under the book writing specification without replacing the source manuscript. Select one chapter, a continuous range, all chapters, or validation only.', z.object({
    bookName, workspaceRoot, ...chapterRange,
    all: z.boolean().default(false), checkOnly: z.boolean().default(false), model: z.string().optional()
  }).refine((i) => {
    if (i.checkOnly || i.all || i.chapter !== undefined) return true;
    return i.startChapter !== undefined && i.endChapter !== undefined && i.startChapter <= i.endChapter;
  }, { message: 'Select chapter, a valid startChapter/endChapter range, all, or checkOnly.' }), '03RW.ps1', (i) => ({
    BookName: i.bookName, Chapter: i.chapter, StartChapter: i.startChapter,
    EndChapter: i.endChapter, All: i.all, CheckOnly: i.checkOnly, Model: i.model
  }));

  scriptTool(server, 'sagewrite_refine_chapters', 'Refine existing chapters in a requested language.', z.object({
    bookName, workspaceRoot, language, ...chapterRange,
    all: z.boolean().default(false), force: z.boolean().default(false), model: z.string().optional()
  }), '03r-refine.ps1', (i) => ({
    BookName: i.bookName, Language: i.language, Chapter: i.chapter,
    StartChapter: i.startChapter, EndChapter: i.endChapter, All: i.all, Force: i.force, Model: i.model
  }));

  scriptTool(server, 'sagewrite_translate_chapters', 'Translate one chapter, a range, or the complete manuscript.', z.object({
    bookName, workspaceRoot, language, ...chapterRange,
    all: z.boolean().default(false), force: z.boolean().default(false),
    maxOutputTokens: z.number().int().positive().default(16000), model: z.string().optional()
  }), '03t-translate.ps1', (i) => ({
    BookName: i.bookName, Language: i.language, Chapter: i.chapter,
    StartChapter: i.startChapter, EndChapter: i.endChapter, All: i.all, Force: i.force,
    MaxOutputTokens: i.maxOutputTokens, Model: i.model
  }));

  scriptTool(server, 'sagewrite_edit_book', 'Run deterministic manuscript editing and heading normalization.', z.object({
    bookName, workspaceRoot, strict: z.boolean().default(false), normalizeSubheadings: z.boolean().default(false)
  }), '04-edit.ps1', (i) => ({
    BookName: i.bookName, Strict: i.strict, NormalizeSubheadings: i.normalizeSubheadings
  }));

  scriptTool(server, 'sagewrite_editorial_action_review', 'Review selected writing units and produce editorial advice plus a machine-readable action plan. This tool does not rewrite manuscript files.', z.object({
    bookName, workspaceRoot, ...chapterRange,
    batchSize: z.number().int().positive().default(5),
    maxTokens: z.number().int().positive().default(9000),
    maxSectionChars: z.number().int().positive().default(8500),
    outputJsonPath: z.string().optional(), outputReportPath: z.string().optional(),
    externalBriefPath: z.string().optional(), previousReviewPath: z.string().optional(),
    scopeName: z.string().min(1).default('learn_part'), model: z.string().optional(),
    dryRun: z.boolean().default(false)
  }), '04B33.ps1', (i) => ({
    BookName: i.bookName, Model: i.model, Chapter: i.chapter,
    StartChapter: i.startChapter, EndChapter: i.endChapter, BatchSize: i.batchSize,
    MaxTokens: i.maxTokens, MaxSectionChars: i.maxSectionChars,
    OutputJsonPath: i.outputJsonPath, OutputReportPath: i.outputReportPath,
    ExternalBriefPath: i.externalBriefPath, PreviousReviewPath: i.previousReviewPath,
    ScopeName: i.scopeName, DryRun: i.dryRun
  }));

  scriptTool(server, 'sagewrite_part_budget_statistics', 'Measure selected writing units against a target length budget and write statistics; no manuscript prose is changed.', z.object({
    bookName, workspaceRoot,
    startChapter: z.number().int().positive().default(1),
    endChapter: z.number().int().positive().optional(),
    budgetMinPerSection: z.number().int().nonnegative().default(1600),
    budgetMaxPerSection: z.number().int().positive().default(2100),
    scopeName: z.string().min(1).default('part_budget_statistics')
  }).refine((i) => i.endChapter === undefined || i.startChapter <= i.endChapter, {
    message: 'startChapter must not exceed endChapter.'
  }).refine((i) => i.budgetMinPerSection <= i.budgetMaxPerSection, {
    message: 'budgetMinPerSection must not exceed budgetMaxPerSection.'
  }), '04B34.ps1', (i) => ({
    BookName: i.bookName, StartChapter: i.startChapter, EndChapter: i.endChapter,
    BudgetMinPerSection: i.budgetMinPerSection, BudgetMaxPerSection: i.budgetMaxPerSection,
    ScopeName: i.scopeName
  }));

  scriptTool(server, 'sagewrite_editorial_loop', 'Run one editorial diagnostic round and optionally generate an author plan or rewrite selected units. applyRewrite modifies manuscript content and requires explicit authorization.', z.object({
    bookName, workspaceRoot, ...chapterRange,
    round: z.enum(['Constitution', 'Developmental', 'Consistency', 'Reader', 'LineEdit', 'FullDiagnostic']).default('Developmental'),
    editorModel: z.string().optional(), authorModel: z.string().optional(),
    maxInputChars: z.number().int().positive().default(120000),
    maxOutputTokens: z.number().int().positive().default(12000),
    rewriteMaxTokens: z.number().int().positive().default(7000),
    dryRun: z.boolean().default(false), noAuthorPlan: z.boolean().default(false),
    applyRewrite: z.boolean().default(false), force: z.boolean().default(false)
  }), '04c-editorial-loop.ps1', (i) => ({
    BookName: i.bookName, Round: i.round, EditorModel: i.editorModel, AuthorModel: i.authorModel,
    Chapter: i.chapter, StartChapter: i.startChapter, EndChapter: i.endChapter,
    MaxInputChars: i.maxInputChars, MaxOutputTokens: i.maxOutputTokens,
    RewriteMaxTokens: i.rewriteMaxTokens, DryRun: i.dryRun, NoAuthorPlan: i.noAuthorPlan,
    ApplyRewrite: i.applyRewrite, Force: i.force
  }));

  scriptTool(server, 'sagewrite_import_third_party_audit', 'Import an external editorial audit and convert it into SageWrite reports and an optional revision plan. applyRewrite modifies manuscript content and requires explicit authorization.', z.object({
    bookName, workspaceRoot, auditPath: z.string().min(1), ...chapterRange,
    sourceName: z.string().min(1).default('Third-party editorial audit'),
    editorialRunPath: z.string().optional(), authorModel: z.string().optional(),
    rewriteMaxTokens: z.number().int().positive().default(7000),
    noEditorialLoopReports: z.boolean().default(false), noExportRevisionPlan: z.boolean().default(false),
    applyRewrite: z.boolean().default(false), force: z.boolean().default(false)
  }), '04c2-third-party-audit.ps1', (i) => ({
    BookName: i.bookName, AuditPath: i.auditPath, SourceName: i.sourceName,
    EditorialRunPath: i.editorialRunPath, Chapter: i.chapter,
    StartChapter: i.startChapter, EndChapter: i.endChapter, AuthorModel: i.authorModel,
    RewriteMaxTokens: i.rewriteMaxTokens, NoEditorialLoopReports: i.noEditorialLoopReports,
    NoExportRevisionPlan: i.noExportRevisionPlan, ApplyRewrite: i.applyRewrite, Force: i.force
  }));

  scriptTool(server, 'sagewrite_accepted_audit_rewrite', 'Prepare and execute a rewrite from an accepted audit plan. Even prepareOnly may update the prepared TOC; use dryRun first and obtain explicit authorization.', z.object({
    bookName, workspaceRoot, ...chapterRange,
    revisionPlanPath: z.string().optional(), externalBriefPath: z.string().optional(),
    masterReportPath: z.string().optional(), additionalInstructions: z.string().optional(),
    model: z.string().optional(), tocModel: z.string().optional(),
    maxTokens: z.number().int().positive().default(7000),
    tocMaxTokens: z.number().int().positive().default(32000),
    maxExistingChars: z.number().int().positive().default(30000),
    referenceGlossary: z.boolean().default(false), skipTocPreparation: z.boolean().default(false),
    forceTocPreparation: z.boolean().default(false), prepareOnly: z.boolean().default(false),
    dryRun: z.boolean().default(false)
  }), '04c3-accepted-audit-rewrite.ps1', (i) => ({
    BookName: i.bookName, Model: i.model, TocModel: i.tocModel,
    Chapter: i.chapter, StartChapter: i.startChapter, EndChapter: i.endChapter,
    MaxTokens: i.maxTokens, TocMaxTokens: i.tocMaxTokens, MaxExistingChars: i.maxExistingChars,
    RevisionPlanPath: i.revisionPlanPath, ExternalBriefPath: i.externalBriefPath,
    MasterReportPath: i.masterReportPath, AdditionalInstructions: i.additionalInstructions,
    ReferenceGlossary: i.referenceGlossary, SkipTocPreparation: i.skipTocPreparation,
    ForceTocPreparation: i.forceTocPreparation, PrepareOnly: i.prepareOnly, DryRun: i.dryRun
  }));

  scriptTool(server, 'sagewrite_execute_revision_plan', 'Apply a reviewed B33 or compatible revision plan to selected writing units. Run dryRun first; a real run modifies manuscript files.', z.object({
    bookName, workspaceRoot, ...chapterRange,
    planPath: z.string().optional(), scopeName: z.string().min(1).default('learn_part'),
    maxTokens: z.number().int().positive().default(8000),
    maxExistingChars: z.number().int().positive().default(14000),
    model: z.string().optional(), dryRun: z.boolean().default(true)
  }), '04C44.ps1', (i) => ({
    BookName: i.bookName, Model: i.model, PlanPath: i.planPath,
    Chapter: i.chapter, StartChapter: i.startChapter, EndChapter: i.endChapter,
    MaxTokens: i.maxTokens, MaxExistingChars: i.maxExistingChars,
    ScopeName: i.scopeName, DryRun: i.dryRun
  }));

  scriptTool(server, 'sagewrite_repeat_audit', 'Find repeated sentences and stock phrases in selected writing units and write an audit report; no prose is deleted.', z.object({
    bookName, workspaceRoot,
    startChapter: z.number().int().positive().default(1),
    endChapter: z.number().int().positive().default(999),
    minSentenceLength: z.number().int().positive().default(18),
    duplicateThreshold: z.number().int().min(2).default(3),
    stockPatterns: z.array(z.string().min(1)).optional(), reportName: z.string().optional()
  }).refine((i) => i.startChapter <= i.endChapter, {
    message: 'startChapter must not exceed endChapter.'
  }), '04D.ps1', (i) => ({
    BookName: i.bookName, StartChapter: i.startChapter, EndChapter: i.endChapter,
    MinSentenceLength: i.minSentenceLength, DuplicateThreshold: i.duplicateThreshold,
    StockPatterns: i.stockPatterns, ReportName: i.reportName
  }));

  scriptTool(server, 'sagewrite_reference_workflow', 'Plan, apply, or check citation-reference updates. Plan does not verify sources; Apply requires independently verified evidence.', z.object({
    bookName, workspaceRoot,
    mode: z.enum(['Plan', 'Apply', 'Check']).default('Plan'),
    startChapter: z.number().int().min(0).max(999).default(0),
    endChapter: z.number().int().min(0).max(999).default(999),
    planPath: z.string().optional(), bookRoot: z.string().optional()
  }).refine((i) => i.startChapter <= i.endChapter, {
    message: 'startChapter must not exceed endChapter.'
  }), '04R.ps1', (i) => ({
    BookName: i.bookName, Mode: i.mode, StartChapter: i.startChapter,
    EndChapter: i.endChapter, PlanPath: i.planPath, BookRoot: i.bookRoot
  }));

  scriptTool(server, 'sagewrite_reference_verification', 'Create a source-verification plan, record supplied evidence, or report verification status. This does not rewrite manuscript prose.', z.object({
    bookName, workspaceRoot,
    mode: z.enum(['Plan', 'Record', 'Report']).default('Plan'),
    bookRoot: z.string().optional(), runId: z.string().optional(), evidencePath: z.string().optional()
  }), '04Reference2.ps1', (i) => ({
    BookName: i.bookName, Mode: i.mode, BookRoot: i.bookRoot,
    RunId: i.runId, EvidencePath: i.evidencePath
  }));

  scriptTool(server, 'sagewrite_apply_reference_changes', 'Preview or apply approved reference metadata and source-field corrections. This does not rewrite narrative prose.', z.object({
    bookName, workspaceRoot, planPath: z.string().min(1),
    mode: z.enum(['Preview', 'Apply']).default('Preview'), bookRoot: z.string().optional(),
    taskIds: z.array(z.string().min(1)).optional()
  }), '04Reference3.ps1', (i) => ({
    BookName: i.bookName, PlanPath: i.planPath, Mode: i.mode,
    BookRoot: i.bookRoot, TaskId: i.taskIds
  }));

  scriptTool(server, 'sagewrite_remove_section', 'Preview or execute deletion of one numbered writing unit and renumber following files. A real run changes structure and requires explicit authorization.', z.object({
    bookName, workspaceRoot,
    sectionIndex: z.number().int().min(1).max(9999), expectedHeading: z.string().optional(),
    endIndex: z.number().int().positive().optional(),
    scopeName: z.string().min(1).default('remove_section_renumber'),
    dryRun: z.boolean().default(true)
  }), '04Z1.ps1', (i) => ({
    BookName: i.bookName, SectionIndex: i.sectionIndex, ExpectedHeading: i.expectedHeading,
    EndIndex: i.endIndex, ScopeName: i.scopeName, DryRun: i.dryRun
  }));

  scriptTool(server, 'sagewrite_format_preflight', 'Check, normalize, or verify manuscript formatting before export.', z.object({
    bookName, workspaceRoot, language,
    mode: z.enum(['Check', 'Normalize', 'Verify']).default('Check'), bookRoot: z.string().optional()
  }), '04F.ps1', (i) => ({ BookName: i.bookName, Mode: i.mode, BookRoot: i.bookRoot, Language: i.language }));

  scriptTool(server, 'sagewrite_build_manuscript', 'Build the final SageWrite manuscript after format verification.', z.object({
    bookName, workspaceRoot, language, autoNumber: z.boolean().default(false)
  }), '05-build.ps1', (i) => ({ BookName: i.bookName, Language: i.language, AutoNumber: i.autoNumber }));

  scriptTool(server, 'sagewrite_build_simple_docx', 'Build a lightweight upload-oriented DOCX without a generated table of contents. This is not equivalent to the formal publication layout.', z.object({
    bookName, workspaceRoot, language, autoNumber: z.boolean().default(false)
  }), '05a-simple-docx.ps1', (i) => ({
    BookName: i.bookName, Language: i.language, AutoNumber: i.autoNumber
  }));

  scriptTool(server, 'sagewrite_build_simple_docx_toc', 'Build a lightweight upload-oriented DOCX with a table of contents. This is not equivalent to the formal publication layout.', z.object({
    bookName, workspaceRoot, language, autoNumber: z.boolean().default(false)
  }), '05aa-simple-docx-toc.ps1', (i) => ({
    BookName: i.bookName, Language: i.language, AutoNumber: i.autoNumber
  }));

  scriptTool(server, 'sagewrite_export_epub', 'Export the manuscript as EPUB after format verification.', z.object({
    bookName, workspaceRoot, language, autoNumber: z.boolean().default(false)
  }), '05b-epub.ps1', (i) => ({ BookName: i.bookName, Language: i.language, AutoNumber: i.autoNumber }));

  server.registerTool('sagewrite_export_pdf', {
    description: 'Export the manuscript as PDF. If the publication cover is missing, automatically prepare cover guidance and return the cover skill/tool handoff instead of creating a coverless PDF.',
    inputSchema: z.object({
      bookName, workspaceRoot, language, autoNumber: z.boolean().default(false),
      outputPath: z.string().optional(), autoPrepareCover: z.boolean().default(true),
      coverRequest: z.string().optional(), model: z.string().optional()
    })
  }, async (input) => {
    try {
      const root = resolveBookRoot(input.bookName, input.workspaceRoot);
      const coverPath = path.join(root, '00_intake', 'cover.png');
      try {
        await fs.access(coverPath);
      } catch {
        if (!input.autoPrepareCover) {
          const payload = { success: false, coverRequired: true, coverPath, nextSkill: 'sagewrite-create-cover' };
          return { content: [{ type: 'text', text: JSON.stringify(payload, null, 2) }], structuredContent: payload, isError: true };
        }
        const request = input.coverRequest || 'Prepare a professional front-cover concept and an image-generation brief based on the approved book objective and TOC. The base image must contain no text; title typography will be added separately.';
        const prepared = await runSageWriteScript('07a-cover-assist.ps1', {
          BookName: input.bookName, Request: request, Edition: 'ebook', Model: input.model
        }, { workspaceRoot: input.workspaceRoot });
        const payload = {
          success: false,
          coverRequired: true,
          coverPreparationStarted: prepared.exitCode === 0 && !prepared.error && !prepared.timedOut,
          coverPath,
          nextSkill: 'sagewrite-create-cover',
          nextTools: ['sagewrite_cover_base_brief', 'sagewrite_cover_base_prompt', 'sagewrite_cover_install'],
          preparation: prepared
        };
        return { content: [{ type: 'text', text: JSON.stringify(payload, null, 2) }], structuredContent: payload, isError: true };
      }
      const result = await runSageWriteScript('05c-pdf.ps1', {
        BookName: input.bookName, Language: input.language, AutoNumber: input.autoNumber,
        OutputPath: input.outputPath
      }, { workspaceRoot: input.workspaceRoot });
      return toolResult('05c-pdf.ps1', result);
    } catch (error) {
      return { content: [{ type: 'text', text: error instanceof Error ? error.message : String(error) }], isError: true };
    }
  });

  scriptTool(server, 'sagewrite_build_print_docx', 'Build the print-layout DOCX after format verification. Use for print pagination and trim-layout review.', z.object({
    bookName, workspaceRoot, language, autoNumber: z.boolean().default(false)
  }), '05ca-print-docx.ps1', (i) => ({
    BookName: i.bookName, Language: i.language, AutoNumber: i.autoNumber
  }));

  scriptTool(server, 'sagewrite_export_print_pdf', 'Build the latest print-layout DOCX and export a print PDF through desktop Microsoft Word.', z.object({
    bookName, workspaceRoot, language, autoNumber: z.boolean().default(false)
  }), '05cc-print-pdf.ps1', (i) => ({
    BookName: i.bookName, Language: i.language, AutoNumber: i.autoNumber
  }));

  scriptTool(server, 'sagewrite_cover_assist', 'Create or revise the cover brief and cover-generation instructions.', z.object({
    bookName, workspaceRoot, request: z.string().min(1), title: z.string().optional(),
    subtitle: z.string().optional(), author: z.string().optional(),
    edition: z.enum(['ebook', 'print']).default('ebook'), model: z.string().optional()
  }), '07a-cover-assist.ps1', (i) => ({
    BookName: i.bookName, Request: i.request, Title: i.title, Subtitle: i.subtitle,
    Author: i.author, Edition: i.edition, Model: i.model
  }));

  scriptTool(server, 'sagewrite_cover_base_brief', 'Create the 08n image-only cover brief from the approved objective and TOC.', z.object({
    bookName, workspaceRoot, edition: z.enum(['ebook', 'print']).default('ebook'),
    title: z.string().optional(), subtitle: z.string().optional(), author: z.string().optional(),
    force: z.boolean().default(false)
  }), '08n-base-brief.ps1', (i) => ({
    BookName: i.bookName, Edition: i.edition, Title: i.title, Subtitle: i.subtitle,
    Author: i.author, Force: i.force
  }));

  scriptTool(server, 'sagewrite_cover_base_prompt', 'Create image-generation prompts for a text-free 08n cover base image.', z.object({
    bookName, workspaceRoot, edition: z.enum(['ebook', 'print']).default('ebook'),
    mode: z.enum(['auto', 'fast', 'full']).default('auto'), force: z.boolean().default(false)
  }), '08n-base-prompt.ps1', (i) => ({
    BookName: i.bookName, Edition: i.edition, Mode: i.mode, Force: i.force
  }));

  scriptTool(server, 'sagewrite_cover_review', 'Review imported 08n base-image candidates and select candidates for typography. Placeholder images are not publication-ready.', z.object({
    bookName, workspaceRoot, edition: z.enum(['ebook', 'print']).default('ebook'),
    mode: z.enum(['auto', 'fast', 'full']).default('auto'), force: z.boolean().default(false)
  }), '08n-base-review.ps1', (i) => ({
    BookName: i.bookName, Edition: i.edition, Mode: i.mode, Force: i.force
  }));

  scriptTool(server, 'sagewrite_cover_layout', 'Add local title, subtitle, and author typography to reviewed 08n base images.', z.object({
    bookName, workspaceRoot, edition: z.enum(['ebook', 'print']).default('ebook'),
    title: z.string().optional(), subtitle: z.string().optional(), author: z.string().optional(),
    mode: z.enum(['auto', 'fast', 'full']).default('auto'), force: z.boolean().default(false)
  }), '08n-title-layout.ps1', (i) => ({
    BookName: i.bookName, Edition: i.edition, Title: i.title, Subtitle: i.subtitle,
    Author: i.author, Mode: i.mode, Force: i.force
  }));

  scriptTool(server, 'sagewrite_cover_image_edit', 'Use the configured OpenAI Images API to edit an imported cover image and add approved cover text. This can incur API usage.', z.object({
    bookName, workspaceRoot, edition: z.enum(['ebook', 'print']).default('ebook'),
    inputFile: z.string().optional(), title: z.string().optional(), subtitle: z.string().optional(),
    author: z.string().optional(), publisher: z.string().optional(), coverText: z.string().optional(),
    imageModel: z.string().default('gpt-image-1.5'), force: z.boolean().default(false)
  }), '08n-image-edit.ps1', (i) => ({
    BookName: i.bookName, Edition: i.edition, InputFile: i.inputFile, Title: i.title,
    Subtitle: i.subtitle, Author: i.author, Publisher: i.publisher, CoverText: i.coverText,
    ImageModel: i.imageModel, Force: i.force
  }));

  scriptTool(server, 'sagewrite_cover_mockup', 'Create a presentation mockup from the approved 08n title layout. A mockup is not a publication cover file.', z.object({
    bookName, workspaceRoot, edition: z.enum(['ebook', 'print']).default('ebook'),
    mode: z.enum(['auto', 'fast', 'full']).default('auto'), force: z.boolean().default(false)
  }), '08n-mockup.ps1', (i) => ({
    BookName: i.bookName, Edition: i.edition, Mode: i.mode, Force: i.force
  }));

  scriptTool(server, 'sagewrite_cover_print_spread', 'Create a print-cover spread from the approved layout and real trim, bleed, spine, page-count, and DPI values.', z.object({
    bookName, workspaceRoot, edition: z.enum(['ebook', 'print']).default('print'),
    printTrimWidthIn: z.number().positive().default(6), printTrimHeightIn: z.number().positive().default(9),
    printBleedIn: z.number().nonnegative().default(0.125), printSpineWidthIn: z.number().nonnegative().default(0.595),
    printPageCount: z.number().int().positive().default(264), printDpi: z.number().int().positive().default(300),
    force: z.boolean().default(false)
  }), '08n-print-spread.ps1', (i) => ({
    BookName: i.bookName, Edition: i.edition, PrintTrimWidthIn: i.printTrimWidthIn,
    PrintTrimHeightIn: i.printTrimHeightIn, PrintBleedIn: i.printBleedIn,
    PrintSpineWidthIn: i.printSpineWidthIn, PrintPageCount: i.printPageCount,
    PrintDpi: i.printDpi, Force: i.force
  }));

  scriptTool(server, 'sagewrite_cover_export', 'Collect approved 08n cover outputs and write the final cover manifest and report.', z.object({
    bookName, workspaceRoot, edition: z.enum(['ebook', 'print']).default('ebook'),
    force: z.boolean().default(false)
  }), '08n-export.ps1', (i) => ({ BookName: i.bookName, Edition: i.edition, Force: i.force }));

  scriptTool(server, 'sagewrite_cover_install', 'Install an explicitly approved cover image as 00_intake/cover.png for stage-05 PDF export. Replacing an existing cover requires force.', z.object({
    bookName, workspaceRoot, sourcePath: z.string().min(1), force: z.boolean().default(false)
  }), '07b-install-cover.ps1', (i) => ({
    BookName: i.bookName, SourcePath: i.sourcePath, Force: i.force
  }));

  return server;
}

void serveStdio(createServer);
console.error('SageWrite MCP server running on stdio');
