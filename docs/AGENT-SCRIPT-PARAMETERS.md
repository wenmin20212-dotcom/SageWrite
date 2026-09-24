# PS1 参数附录

## 2026-09-24 新增入口

以下两项补充在原87个顶层脚本快照之外；原声明仍保留。参数详情与运行约束分别见04Reference2和04Reference3说明。

```powershell
# 04Reference2.ps1
param(
    [Parameter(Mandatory=$true)][string]$BookName,
    [ValidateSet('Plan','Record','Report')][string]$Mode = 'Plan',
    [string]$BookRoot,
    [string]$RunId,
    [string]$EvidencePath
)
# 04Reference3.ps1
param(
    [Parameter(Mandatory=$true)][string]$BookName,
    [Parameter(Mandatory=$true)][string]$PlanPath,
    [ValidateSet('Preview','Apply')][string]$Mode = 'Preview',
    [string]$BookRoot,
    [string[]]$TaskId
)
```

提取日期：2026-09-18。基于 engine 顶层已跟踪的87个PS1文件，使用PowerShell AST只读提取顶层param声明；没有执行这些脚本。声明保留原始参数名、默认值、必填标记和验证集合。公共参数和脚本体内的数据约束不在此表中，实际调用仍需结合[Agent调用手册](AGENT-CALLING-GUIDE.md)与源码。

转发入口04B33、04B34、04C44、04D、04Z1使用目标脚本参数；无param的公共库应点源而不是独立执行。参数声明可用于查询，不是可直接复制执行的业务命令。

## 00-common.ps1

[查看源码](../engine/00-common.ps1)

```powershell
# No top-level param block; inspect wrapper or dot-source library.
```

## 00-layout.ps1

[查看源码](../engine/00-layout.ps1)

```powershell
# No top-level param block; inspect wrapper or dot-source library.
```

## 01-intake.ps1

[查看源码](../engine/01-intake.ps1)

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [Parameter(Mandatory=$true)]
    [string]$Title,

    [string]$Subtitle = "",

    [string]$Author = "",

    [Parameter(Mandatory=$true)]
    [string]$Audience,

    [Parameter(Mandatory=$true)]
    [string]$Type,

    [Parameter(Mandatory=$true)]
    [string]$CoreThesis,

    [Parameter(Mandatory=$true)]
    [string]$Scope,

    [Parameter(Mandatory=$true)]
    [string]$Style
)
```

## 02-structure.ps1

[查看源码](../engine/02-structure.ps1)

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$BookName
)
```

## 02b-expand.ps1

[查看源码](../engine/02b-expand.ps1)

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [int]$Chapter,

    [switch]$All,

    [int]$StartChapter,
    [int]$EndChapter,

    [int]$MinSubsections = 3,
    [int]$MaxSubsections = 5,

    [string]$Model = "gpt-4o-mini"
)
```

## 03-write.ps1

[查看源码](../engine/03-write.ps1)

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [string]$Model = "gpt-5.5",

    [int]$Chapter,

    [int]$StartChapter,
    [int]$EndChapter,

    [int]$MaxTokens = 7000,

    [string]$AdditionalInstructions,

    [switch]$ReferenceGlossary,

    [switch]$Force
)
```

## 03r-refine.ps1

[查看源码](../engine/03r-refine.ps1)

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [Parameter(Mandatory=$true)]
    [string]$Language,

    [string]$Model = "gpt-5.2",

    [int]$Chapter,
    [int]$StartChapter,
    [int]$EndChapter,

    [switch]$All,
    [switch]$Force
)
```

## 03t-translate.ps1

[查看源码](../engine/03t-translate.ps1)

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [Parameter(Mandatory=$true)]
    [string]$Language,

    [string]$Model = "gpt-5.2",

    [int]$MaxOutputTokens = 16000,

    [Nullable[int]]$Chapter,
    [Nullable[int]]$StartChapter,
    [Nullable[int]]$EndChapter,

    [switch]$All,
    [switch]$Force
)
```

## 04-edit.ps1

[查看源码](../engine/04-edit.ps1)

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,
    [switch]$Strict,
    [switch]$NormalizeSubheadings
)
```

## 04B33.ps1

[查看源码](../engine/04B33.ps1)

```powershell
# No top-level param block; inspect wrapper or dot-source library.
```

## 04B34.ps1

[查看源码](../engine/04B34.ps1)

```powershell
# No top-level param block; inspect wrapper or dot-source library.
```

## 04C44.ps1

[查看源码](../engine/04C44.ps1)

```powershell
# No top-level param block; inspect wrapper or dot-source library.
```

## 04D.ps1

[查看源码](../engine/04D.ps1)

```powershell
# No top-level param block; inspect wrapper or dot-source library.
```

## 04F.ps1

[查看源码](../engine/04F.ps1)

```powershell
param(
    [Parameter(Mandatory=$true)][string]$BookName,
    [ValidateSet('Check','Normalize','Verify')][string]$Mode='Check',
    [string]$BookRoot,
    [string]$Language='zh'
)
```

## 04R.ps1

[查看源码](../engine/04R.ps1)

```powershell
param(
    [Parameter(Mandatory=$true)][string]$BookName,
    [ValidateSet('Plan','Apply','Check')][string]$Mode = 'Plan',
    [ValidateRange(0,999)][int]$StartChapter = 0,
    [ValidateRange(0,999)][int]$EndChapter = 999,
    [string]$PlanPath,
    [string]$BookRoot
)
```

## 04Z1.ps1

[查看源码](../engine/04Z1.ps1)

```powershell
# No top-level param block; inspect wrapper or dot-source library.
```

## 04b-epub.ps1

[查看源码](../engine/04b-epub.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName
)
```

## 04b33-editorial-action-review.ps1

[查看源码](../engine/04b33-editorial-action-review.ps1)

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [string]$Model = "gpt-5.5",

    [int]$Chapter,

    [int]$StartChapter,

    [int]$EndChapter,

    [int]$BatchSize = 5,

    [int]$MaxTokens = 9000,

    [int]$MaxSectionChars = 8500,

    [string]$OutputJsonPath,

    [string]$OutputReportPath,

    [string]$ExternalBriefPath,

    [string]$PreviousReviewPath,

    [string]$ScopeName = "learn_part",

    [switch]$DryRun
)
```

## 04b34-part-budget-statistics.ps1

[查看源码](../engine/04b34-part-budget-statistics.ps1)

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [int]$StartChapter = 1,

    [int]$EndChapter,

    [int]$BudgetMinPerSection = 1600,

    [int]$BudgetMaxPerSection = 2100,

    [string]$ScopeName = "part_budget_statistics"
)
```

## 04c-editorial-loop.ps1

[查看源码](../engine/04c-editorial-loop.ps1)

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [ValidateSet("Constitution", "Developmental", "Consistency", "Reader", "LineEdit", "FullDiagnostic")]
    [string]$Round = "Developmental",

    [string]$EditorModel = "gpt-5.5",

    [string]$AuthorModel = "gpt-5.5",

    [int]$Chapter,

    [int]$StartChapter,

    [int]$EndChapter,

    [int]$MaxInputChars = 120000,

    [int]$MaxOutputTokens = 12000,

    [int]$RewriteMaxTokens = 7000,

    [switch]$DryRun,

    [switch]$NoAuthorPlan,

    [switch]$ApplyRewrite,

    [switch]$Force
)
```

## 04c2-third-party-audit.ps1

[查看源码](../engine/04c2-third-party-audit.ps1)

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [Parameter(Mandatory=$true)]
    [string]$AuditPath,

    [string]$SourceName = "Third-party editorial audit",

    [string]$EditorialRunPath,

    [int]$Chapter,

    [int]$StartChapter,

    [int]$EndChapter,

    [string]$AuthorModel = "gpt-5.5",

    [int]$RewriteMaxTokens = 7000,

    [switch]$NoEditorialLoopReports,

    [switch]$NoExportRevisionPlan,

    [switch]$ApplyRewrite,

    [switch]$Force
)
```

## 04c3-accepted-audit-rewrite.ps1

[查看源码](../engine/04c3-accepted-audit-rewrite.ps1)

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [string]$Model = "gpt-5.5",

    [string]$TocModel,

    [int]$Chapter,

    [int]$StartChapter,

    [int]$EndChapter,

    [int]$MaxTokens = 7000,

    [int]$TocMaxTokens = 32000,

    [int]$MaxExistingChars = 30000,

    [string]$RevisionPlanPath,

    [string]$ExternalBriefPath,

    [string]$MasterReportPath,

    [string]$AdditionalInstructions,

    [switch]$ReferenceGlossary,

    [switch]$SkipTocPreparation,

    [switch]$ForceTocPreparation,

    [switch]$PrepareOnly,

    [switch]$DryRun
)
```

## 04c44-revision-executor.ps1

[查看源码](../engine/04c44-revision-executor.ps1)

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [string]$Model = "gpt-5.5",

    [string]$PlanPath,

    [int]$Chapter,

    [int]$StartChapter,

    [int]$EndChapter,

    [int]$MaxTokens = 8000,

    [int]$MaxExistingChars = 14000,

    [string]$ScopeName = "learn_part",

    [switch]$DryRun
)
```

## 04d-repeat-audit.ps1

[查看源码](../engine/04d-repeat-audit.ps1)

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [int]$StartChapter = 1,

    [int]$EndChapter = 999,

    [int]$MinSentenceLength = 18,

    [int]$DuplicateThreshold = 3,

    [string[]]$StockPatterns = @(
        "真正稀缺",
        "什么值得生成",
        "生成.*更容易",
        "更容易.*生成",
        "内容越容易",
        "生成门槛下降",
        "AI时代生成内容"
    ),

    [string]$ReportName = ""
)
```

## 04f-format-common.ps1

[查看源码](../engine/04f-format-common.ps1)

```powershell
# No top-level param block; inspect wrapper or dot-source library.
```

## 04z1-remove-section-renumber.ps1

[查看源码](../engine/04z1-remove-section-renumber.ps1)

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [Parameter(Mandatory=$true)]
    [ValidateRange(1, 9999)]
    [int]$SectionIndex,

    [string]$ExpectedHeading,

    [int]$EndIndex,

    [string]$ScopeName = "remove_section_renumber",

    [switch]$DryRun
)
```

## 05-build.ps1

[查看源码](../engine/05-build.ps1)

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [string]$Language = "zh",

    [switch]$AutoNumber
)
```

## 05a-simple-docx.ps1

[查看源码](../engine/05a-simple-docx.ps1)

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [string]$Language = "zh",

    [switch]$AutoNumber
)
```

## 05aa-simple-docx-toc.ps1

[查看源码](../engine/05aa-simple-docx-toc.ps1)

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [string]$Language = "zh",

    [switch]$AutoNumber
)
```

## 05b-epub.ps1

[查看源码](../engine/05b-epub.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$Language = "zh",

    [switch]$AutoNumber
)
```

## 05c-pdf.ps1

[查看源码](../engine/05c-pdf.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$Language = "zh",

    [switch]$AutoNumber
)
```

## 05ca-print-docx.ps1

[查看源码](../engine/05ca-print-docx.ps1)

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [string]$Language = "zh",

    [switch]$AutoNumber
)
```

## 05cc-print-pdf.ps1

[查看源码](../engine/05cc-print-pdf.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$Language = "zh",

    [switch]$AutoNumber
)
```

## 06-web.ps1

[查看源码](../engine/06-web.ps1)

```powershell
param(
    [int]$Port,
    [string]$HostName,
    [ValidateSet("local", "cloud")]
    [string]$Mode,
    [ValidateSet("off", "password", "users")]
    [string]$AuthMode,
    [string]$AdminUser,
    [string]$AdminPassword,
    [string]$OpenAIKey,
    [string]$WorkspaceRoot,
    [string]$UsersFile,
    [string]$UserWorkspaceRoot,
    [string]$ConfigPath,
    [switch]$OpenBrowser
)
```

## 07a-cover-assist.ps1

[查看源码](../engine/07a-cover-assist.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [Parameter(Mandatory = $true)]
    [string]$Request,

    [string]$Title,
    [string]$Subtitle,
    [string]$Author,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [string]$Model = "gpt-5.2"
)
```

## 08-cover-drafts.ps1

[查看源码](../engine/08-cover-drafts.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [string]$Title,
    [string]$Subtitle,
    [string]$Author,

    [ValidateRange(1, 20)]
    [int]$Variants = 4,

    [ValidateSet("auto", "fast", "full")]
    [string]$Mode = "auto",

    [switch]$Force
)
```

## 08-cover-layout.ps1

[查看源码](../engine/08-cover-layout.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [string]$Title,
    [string]$Subtitle,
    [string]$Author,

    [ValidateSet("auto", "fast", "full")]
    [string]$Mode = "auto",

    [switch]$Force
)
```

## 08-cover-mockup.ps1

[查看源码](../engine/08-cover-mockup.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [ValidateSet("auto", "fast", "full")]
    [string]$Mode = "auto",

    [switch]$Force
)
```

## 08-cover.ps1

[查看源码](../engine/08-cover.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [string]$Title,
    [string]$Subtitle,
    [string]$Author,

    [ValidateRange(1, 20)]
    [int]$Variants = 4,

    [ValidateSet("auto", "fast", "full")]
    [string]$Mode = "auto",

    [switch]$Force,
    [switch]$SkipLayout,
    [switch]$SkipMockup,

    [double]$PrintTrimWidthIn = 6.0,
    [double]$PrintTrimHeightIn = 9.0,
    [double]$PrintBleedIn = 0.125,
    [double]$PrintSpineWidthIn = 0.595,
    [int]$PrintPageCount = 264,
    [int]$PrintDpi = 300
)
```

## 08a-brief.ps1

[查看源码](../engine/08a-brief.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [string]$Title,
    [string]$Subtitle,
    [string]$Author,

    [switch]$Force
)
```

## 08b-strategy.ps1

[查看源码](../engine/08b-strategy.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [ValidateSet("auto", "fast", "full")]
    [string]$Mode = "auto",

    [switch]$Force
)
```

## 08c-generate.ps1

[查看源码](../engine/08c-generate.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [ValidateRange(1, 20)]
    [int]$Variants = 4,

    [ValidateSet("auto", "fast", "full")]
    [string]$Mode = "auto",

    [switch]$Force
)
```

## 08d-review.ps1

[查看源码](../engine/08d-review.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [ValidateSet("auto", "fast", "full")]
    [string]$Mode = "auto",

    [switch]$Force
)
```

## 08e-layout.ps1

[查看源码](../engine/08e-layout.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [string]$Title,
    [string]$Subtitle,
    [string]$Author,

    [ValidateSet("auto", "fast", "full")]
    [string]$Mode = "auto",

    [switch]$Force
)
```

## 08f-mockup.ps1

[查看源码](../engine/08f-mockup.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [ValidateSet("auto", "fast", "full")]
    [string]$Mode = "auto",

    [switch]$Force
)
```

## 08g-copy.ps1

[查看源码](../engine/08g-copy.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [ValidateSet("auto", "fast", "full")]
    [string]$Mode = "auto",

    [switch]$Force
)
```

## 08h-frontmatter.ps1

[查看源码](../engine/08h-frontmatter.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [string]$Title,
    [string]$Subtitle,
    [string]$Author,

    [switch]$Force
)
```

## 08n-base-brief.ps1

[查看源码](../engine/08n-base-brief.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [string]$Title,
    [string]$Subtitle,
    [string]$Author,

    [switch]$Force
)
```

## 08n-base-generate.ps1

[查看源码](../engine/08n-base-generate.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [ValidateRange(1, 20)]
    [int]$Variants = 4,

    [ValidateSet("auto", "fast", "full")]
    [string]$Mode = "auto",

    [switch]$Force
)
```

## 08n-base-prompt.ps1

[查看源码](../engine/08n-base-prompt.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [ValidateSet("auto", "fast", "full")]
    [string]$Mode = "auto",

    [switch]$Force
)
```

## 08n-base-review.ps1

[查看源码](../engine/08n-base-review.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [ValidateSet("auto", "fast", "full")]
    [string]$Mode = "auto",

    [switch]$Force
)
```

## 08n-common.ps1

[查看源码](../engine/08n-common.ps1)

```powershell
# No top-level param block; inspect wrapper or dot-source library.
```

## 08n-cover.ps1

[查看源码](../engine/08n-cover.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [string]$Title,
    [string]$Subtitle,
    [string]$Author,

    [ValidateRange(1, 20)]
    [int]$Variants = 4,

    [ValidateSet("auto", "fast", "full")]
    [string]$Mode = "auto",

    [switch]$Force,
    [switch]$SkipMockup,
    [switch]$SkipPrintSpread,

    [double]$PrintTrimWidthIn = 6.0,
    [double]$PrintTrimHeightIn = 9.0,
    [double]$PrintBleedIn = 0.125,
    [double]$PrintSpineWidthIn = 0.595,
    [int]$PrintPageCount = 264,
    [int]$PrintDpi = 300
)
```

## 08n-export.ps1

[查看源码](../engine/08n-export.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [switch]$Force
)
```

## 08n-image-edit.ps1

[查看源码](../engine/08n-image-edit.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [string]$InputFile,

    [string]$Title,
    [string]$Subtitle,
    [string]$Author,
    [string]$Publisher,
    [string]$CoverText,

    [string]$ImageModel = "gpt-image-1.5",

    [switch]$Force
)
```

## 08n-midjourney-prompt.ps1

[查看源码](../engine/08n-midjourney-prompt.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [string]$Model = "gpt-5.2",

    [string]$Title,
    [string]$Subtitle,
    [string]$Author,

    [int]$MaxTokens = 1800
)
```

## 08n-mockup.ps1

[查看源码](../engine/08n-mockup.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [ValidateSet("auto", "fast", "full")]
    [string]$Mode = "auto",

    [switch]$Force
)
```

## 08n-print-spread.ps1

[查看源码](../engine/08n-print-spread.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "print",

    [double]$PrintTrimWidthIn = 6.0,
    [double]$PrintTrimHeightIn = 9.0,
    [double]$PrintBleedIn = 0.125,
    [double]$PrintSpineWidthIn = 0.595,
    [int]$PrintPageCount = 264,
    [int]$PrintDpi = 300,

    [switch]$Force
)
```

## 08n-title-layout.ps1

[查看源码](../engine/08n-title-layout.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [string]$Title,
    [string]$Subtitle,
    [string]$Author,

    [ValidateSet("auto", "fast", "full")]
    [string]$Mode = "auto",

    [switch]$Force
)
```

## 08z-export.ps1

[查看源码](../engine/08z-export.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [switch]$SkipLayout,
    [switch]$SkipMockup,
    [switch]$Force,

    [double]$PrintTrimWidthIn = 6.0,
    [double]$PrintTrimHeightIn = 9.0,
    [double]$PrintBleedIn = 0.125,
    [double]$PrintSpineWidthIn = 0.595,
    [int]$PrintPageCount = 264,
    [int]$PrintDpi = 300
)
```

## 09-publish.ps1

[查看源码](../engine/09-publish.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$Language = "zh",

    [ValidateSet("all", "amazon", "apple", "google")]
    [string]$Platform = "all",

    [switch]$Force
)
```

## 09a-collect.ps1

[查看源码](../engine/09a-collect.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$Language = "zh",

    [switch]$Force
)
```

## 09b-metadata.ps1

[查看源码](../engine/09b-metadata.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$Language = "zh",

    [switch]$Force
)
```

## 09c-amazon.ps1

[查看源码](../engine/09c-amazon.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$Language = "zh",

    [switch]$Force
)
```

## 09d-apple.ps1

[查看源码](../engine/09d-apple.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$Language = "zh",

    [switch]$Force
)
```

## 09e-google.ps1

[查看源码](../engine/09e-google.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$Language = "zh",

    [switch]$Force
)
```

## 09f-submit.ps1

[查看源码](../engine/09f-submit.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$Language = "zh",

    [ValidateSet("all", "amazon", "apple", "google")]
    [string]$Platform = "all",

    [ValidateSet("prepare", "draft", "assist", "details", "content")]
    [string]$Mode = "prepare",

    [switch]$AttachChrome,
    [int]$ChromeDebugPort = 9222,

    [switch]$ReuseSession,
    [switch]$Force
)
```

## 09g-amazon-bot.ps1

[查看源码](../engine/09g-amazon-bot.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$Language = "zh",

    [ValidateSet("prepare", "draft", "assist", "details", "content")]
    [string]$Mode = "prepare",

    [Parameter(Mandatory = $true)]
    [string]$RunRoot,

    [switch]$AttachChrome,
    [int]$ChromeDebugPort = 9222,

    [switch]$ReuseSession,
    [switch]$Force
)
```

## 09h-google-bot.ps1

[查看源码](../engine/09h-google-bot.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$Language = "zh",

    [ValidateSet("prepare", "draft", "assist")]
    [string]$Mode = "prepare",

    [Parameter(Mandatory = $true)]
    [string]$RunRoot,

    [switch]$AttachChrome,
    [int]$ChromeDebugPort = 9222,

    [switch]$ReuseSession,
    [switch]$Force
)
```

## 09i-apple-delivery.ps1

[查看源码](../engine/09i-apple-delivery.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$Language = "zh",

    [ValidateSet("prepare", "draft", "assist")]
    [string]$Mode = "prepare",

    [Parameter(Mandatory = $true)]
    [string]$RunRoot,

    [switch]$ReuseSession,
    [switch]$Force
)
```

## Get-SageWrite-WebTask.ps1

[查看源码](../engine/Get-SageWrite-WebTask.ps1)

```powershell
param(
  [string]$TaskName = "SageWrite Web"
)
```

## Install-SageWrite-Standalone.ps1

[查看源码](../engine/Install-SageWrite-Standalone.ps1)

```powershell
param(
  [ValidateSet("local", "cloud")]
  [string]$Mode = "local",
  [string]$HostName,
  [int]$Port = 3210,
  [string]$WorkspaceRoot,
  [string]$AdminPassword,
  [string]$OpenAIKey,
  [switch]$InstallAutoStart,
  [ValidateSet("AtLogon", "AtStartup")]
  [string]$TaskTrigger = "AtLogon",
  [switch]$AsSystem,
  [switch]$StartNow,
  [switch]$Force,
  [switch]$DryRun
)
```

## Install-SageWrite-WebTask.ps1

[查看源码](../engine/Install-SageWrite-WebTask.ps1)

```powershell
param(
  [string]$TaskName = "SageWrite Web",
  [ValidateSet("AtLogon", "AtStartup")]
  [string]$Trigger = "AtLogon",
  [switch]$AsSystem,
  [switch]$RunNow,
  [switch]$Force,
  [switch]$DryRun,
  [string]$ConfigPath
)
```

## New-SageWrite-StandalonePackage.ps1

[查看源码](../engine/New-SageWrite-StandalonePackage.ps1)

```powershell
param(
  [string]$OutputRoot,
  [string]$Ref = "HEAD",
  [string]$VersionName,
  [switch]$Force
)
```

## Run-SageWrite-WebTask.ps1

[查看源码](../engine/Run-SageWrite-WebTask.ps1)

```powershell
param(
  [string]$ConfigPath
)
```

## Start-SageWrite-Web.ps1

[查看源码](../engine/Start-SageWrite-Web.ps1)

```powershell
param(
  [int]$Port,
  [string]$HostName,
  [ValidateSet("local", "cloud")]
  [string]$Mode,
  [ValidateSet("off", "password", "users")]
  [string]$AuthMode,
  [string]$AdminUser,
  [string]$AdminPassword,
  [string]$OpenAIKey,
  [string]$WorkspaceRoot,
  [string]$UsersFile,
  [string]$UserWorkspaceRoot,
  [string]$ConfigPath
)
```

## Uninstall-SageWrite-WebTask.ps1

[查看源码](../engine/Uninstall-SageWrite-WebTask.ps1)

```powershell
param(
  [string]$TaskName = "SageWrite Web",
  [switch]$Stop
)
```

## clean.ps1

[查看源码](../engine/clean.ps1)

```powershell
param(
    [string]$InputFile,
    [string]$InputDir
)
```

## kdp-acceptance-files.ps1

[查看源码](../engine/kdp-acceptance-files.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("List", "OpenDirectory")]
    [string]$Action = "List"
)
```

## kdp-composite-image-region.ps1

[查看源码](../engine/kdp-composite-image-region.ps1)

```powershell
param(
    [string]$BookName,

    [string]$BaseFile,

    [string]$OverlayFile,

    [string]$BasePath,

    [string]$OverlayPath,

    [Parameter(Mandatory = $true)]
    [int]$X,

    [Parameter(Mandatory = $true)]
    [int]$Y,

    [string]$OutputFile,

    [string]$OutputPath,

    [switch]$Force
)
```

## kdp-crop-image-region.ps1

[查看源码](../engine/kdp-crop-image-region.ps1)

```powershell
param(
    [string]$BookName,

    [string]$SourceFile,

    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [int]$X,

    [Parameter(Mandatory = $true)]
    [int]$Y,

    [Parameter(Mandatory = $true)]
    [int]$Width,

    [Parameter(Mandatory = $true)]
    [int]$Height,

    [string]$OutputFile,

    [string]$OutputPath,

    [switch]$Force
)
```

## kdp-fill-image-region.ps1

[查看源码](../engine/kdp-fill-image-region.ps1)

```powershell
param(
    [string]$BookName,

    [string]$SourceFile,

    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [int]$X,

    [Parameter(Mandatory = $true)]
    [int]$Y,

    [Parameter(Mandatory = $true)]
    [int]$Width,

    [Parameter(Mandatory = $true)]
    [int]$Height,

    [string]$FillColor = "#07121b",

    [ValidateSet("Auto", "Solid")]
    [string]$FillMode = "Auto",

    [string]$OutputFile,

    [string]$OutputPath,

    [switch]$Force
)
```

## kdp-fix-image-edit.ps1

[查看源码](../engine/kdp-fix-image-edit.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$SourceFile,

    [string]$PromptFile,

    [string]$Prompt,

    [string]$ImageModel = "gpt-image-1.5",

    [switch]$Force
)
```

## kdp-imagemagick-fix.ps1

[查看源码](../engine/kdp-imagemagick-fix.ps1)

```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$SourceFile,

    [string]$InputEditFile,

    [string]$InstructionJson,

    [string]$InstructionFile,

    [switch]$Force
)
```

## kdp-png-to-pdf.ps1

[查看源码](../engine/kdp-png-to-pdf.ps1)

```powershell
param(
    [string]$BookName,

    [string]$InputFile,

    [string]$InputPath,

    [string]$OutputFile,

    [string]$OutputPath,

    [switch]$Force
)
```

## kdp-resize-image-region.ps1

[查看源码](../engine/kdp-resize-image-region.ps1)

```powershell
param(
    [string]$BookName,

    [string]$InputFile,

    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [double]$ScalePercent,

    [string]$OutputFile,

    [string]$OutputPath,

    [switch]$Force
)
```

## test-broken.ps1

[查看源码](../engine/test-broken.ps1)

```powershell
param(
    [string]$Name
)
```
