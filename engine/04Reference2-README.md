# 04Reference2：参考文献二次核验记录

本程序读取04R已经形成的reference_state.json及书稿，管理Agent复核任务与证据。它不自动上网、不调用模型、不修改正文、不替代04R Check，也不会自动给05签发审批。

## 使用步骤

以下命令在engine执行，BookName替换为实际书名。可用BookRoot显式指定书籍根目录。

```powershell
.\04Reference2.ps1 -BookName MyBook -Mode Plan
```

Plan在书内 `04_output/editorial_audits/reference_rechecks/<RunId>` 新建独立轮次，保存plan.json、原始文件快照、证据模板及progress.jsonl日志。按来源建立书目信息核验任务，按正文中带引用标记的段落建立观点支持核验任务。上下文超出该段落时Agent须阅读快照中的完整小节。它不检测未引用论断，也不证明04R状态本身已通过一致性检查；建议开始前先运行04R Check。

Agent逐条访问真实来源，将模板另存为证据JSON并填写：

- task_id：对应任务，不可虚构；reviewer：核验者。
- checked_at：实际核验时间，建议ISO8601含时区。
- access：full_text、abstract、metadata、unavailable。
- verdict：pass、partial、unsupported、metadata_mismatch、unconfirmed。
- verification_url：实际访问地址；locator：页码、章节、摘要等定位。
- evidence：自己概述的证据，不粘贴大段受版权保护内容。
- limitations：访问限制和证据边界；recommendation：修改建议，无建议也应明确写出。

来源任务核对题名、作者、年份和DOI等；观点任务核对正文的论断是否得到支持。只有书目信息不能判定观点pass/partial，无法访问只能记录unconfirmed。摘要不等于全文，结论只能覆盖实际读到的证据。不得沿用旧verified字段冒充本轮查证。

```powershell
.\04Reference2.ps1 -BookName MyBook -Mode Record -RunId '程序输出的RunId' -EvidencePath '已填写的证据JSON绝对路径'
.\04Reference2.ps1 -BookName MyBook -Mode Report -RunId '程序输出的RunId'
```

每次Record只登记一项，不覆盖已有记录，并立即生成JSON与MD报告。Report随时查看进度，每次生成新文件。状态为incomplete、needs_review或agent_reported_pass；最后一个仅代表Agent全部报告通过，不是程序独立学术认证。发现记录错误时开启新轮次，旧记录保留。

## 边审核边导出修改JSON

Plan创建时即生成全待审计划；每次Record成功以及每次Report都会导出：

- `modification_plan.json`：最新视图，可供后续04R3读取。
- `modification_plan_<export_id>.json`：本次导出的独立历史版本，不覆盖。
- `previous_latest_<export_id>.json`：替换最新视图前的保留副本。

证据JSON新增可选的结构化`decision`。新任务应明确填写；旧记录没有此字段时仍可读取，但其修改决定为pending，不从recommendation自然语言推断修改，也不把pass当成no_change。

```json
{
  "action": "modify",
  "reason": "核验后建议更新来源链接",
  "changes": [
    {
      "field": "url",
      "old_value": "https://example.org/old",
      "new_value": "https://example.org/new",
      "reason": "填写实际核验依据，不使用本示例链接"
    }
  ]
}
```

将上述对象放入完整证据JSON的decision字段，不是把该对象单独交给Record。无需修改时填写`action: no_change`、明确reason和空changes数组；未能判断时填`defer`。pending表示未审或旧证据没有结构化决定，defer表示已记录待解决原因，两者不同。

本版仅允许source任务修改来源字段：url、verification_url、title、publication、year、volume、issue、pages、authors。禁止修改id、verified或执行任意路径；authors必须是非空字符串数组，网址必须为HTTPS。old_value必须与本轮原始来源字段一致，重复字段、原新值相同、越权字段或未确认的证据修改会被拒绝。claim任务本版只能no_change/defer，正文修订不在此JSON自动执行范围内。

导出schema为`sagewrite.reference_changes`，schema_version=1。actions包含任务与来源ID、目标文件及来源选择器、原值/新值/原因、证据路径与SHA256；expected_files绑定本轮输入版本，review_plan_sha256绑定复核任务。counts分别统计modify、no_change、defer、pending。

**每次导出approval.approved都为false**，不能把边审边导出当成边审边执行。[04Reference3](04Reference3-README.md)负责检查版本和原值，读取经用户确认的独立导出副本，按approval.task_ids执行批准范围，忽略no_change并拒绝执行范围内的pending/defer。来源修改后重生成参考文献并进行04R一致性检查；不能直接传给现有04R Apply。

请串行运行同一轮Record/Report。若导出失败但记录已保存，应修复原因后运行Report重新导出，不重复Record。同一轮旧证据不覆盖；需要补充结构化决定时开启新轮次，不伪造新的实际联网核验时间。旧JSON导出本身不会在书稿改变时自动消失，未来执行器必须独立核对expected_files，不能只看文件存在。

## 可观察性与限制

progress.jsonl记录已接受条目与汇总进度，records目录保存逐条证据，report文件列出未完成和异常项。Agent还应向用户说明正在查哪条来源。未通过输入校验的尝试以命令错误返回，不写成已完成记录。

程序绑定目录、参考文献状态及全部正文MD的SHA256；文件改变、缺失或新增MD时拒绝沿用旧轮次。修订正文应交给经审核的04R流程，再建立新轮次。快照与日志是本地可追溯记录，不是防篡改数字签名；不能防止人工直接修改审查目录。

本版仅支持已采用04R的书籍。并行Record不同任务可以保存独立证据，但汇总可能看到不同时间点；推荐串行登记，完成后再Report。Plan期间不要同时编辑书稿。
