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

  scriptTool(server, 'sagewrite_format_preflight', 'Check, normalize, or verify manuscript formatting before export.', z.object({
    bookName, workspaceRoot, language,
    mode: z.enum(['Check', 'Normalize', 'Verify']).default('Check'), bookRoot: z.string().optional()
  }), '04F.ps1', (i) => ({ BookName: i.bookName, Mode: i.mode, BookRoot: i.bookRoot, Language: i.language }));

  scriptTool(server, 'sagewrite_build_manuscript', 'Build the final SageWrite manuscript after format verification.', z.object({
    bookName, workspaceRoot, language, autoNumber: z.boolean().default(false)
  }), '05-build.ps1', (i) => ({ BookName: i.bookName, Language: i.language, AutoNumber: i.autoNumber }));

  scriptTool(server, 'sagewrite_export_epub', 'Export the manuscript as EPUB after format verification.', z.object({
    bookName, workspaceRoot, language, autoNumber: z.boolean().default(false)
  }), '05b-epub.ps1', (i) => ({ BookName: i.bookName, Language: i.language, AutoNumber: i.autoNumber }));

  scriptTool(server, 'sagewrite_export_pdf', 'Export the manuscript as PDF, including a cover when present.', z.object({
    bookName, workspaceRoot, language, autoNumber: z.boolean().default(false), outputPath: z.string().optional()
  }), '05c-pdf.ps1', (i) => ({
    BookName: i.bookName, Language: i.language, AutoNumber: i.autoNumber, OutputPath: i.outputPath
  }));

  scriptTool(server, 'sagewrite_cover_assist', 'Create or revise the cover brief and cover-generation instructions.', z.object({
    bookName, workspaceRoot, request: z.string().min(1), title: z.string().optional(),
    subtitle: z.string().optional(), author: z.string().optional(),
    edition: z.enum(['ebook', 'print']).default('ebook'), model: z.string().optional()
  }), '07a-cover-assist.ps1', (i) => ({
    BookName: i.bookName, Request: i.request, Title: i.title, Subtitle: i.subtitle,
    Author: i.author, Edition: i.edition, Model: i.model
  }));

  return server;
}

void serveStdio(createServer);
console.error('SageWrite MCP server running on stdio');
