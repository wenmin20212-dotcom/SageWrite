# 04Reference3：参考文献复核意见执行器

读取04Reference2导出的`sagewrite.reference_changes` schema_version=1 JSON。支持Preview（默认）和Apply。它不调用模型、不猜测文字建议、不修改正文，仅执行明确批准的既有来源字段修改。

## 1. 从04R2取得计划

04R2每次Record/Report都输出modification_plan.json及独立历史版本。Agent在证据中写明decision.action=modify/no_change/defer及原值、新值、原因。没有结构化决定的旧记录为pending，不能直接执行。

不得手工把导出actions改成与核验证据不同的内容。04R3会对照原始任务、证据哈希和decision。要改变建议，应建立新核验轮次，保留旧证据。

## 2. 预览

在engine目录执行，下列书名、路径均为示例，需替换：

```powershell
.\04Reference3.ps1 -BookName MyBook -PlanPath 'C:\实际工作区\某轮次\modification_plan.json' -Mode Preview
```

默认预览计划中的modify/no_change条目，也可通过`-TaskId T0002,T0003`限定预览。没有任何明确决定则拒绝；不会猜测pending/defer项目。Preview不改书稿，会写独立执行预览报告并调用04R Check。

## 3. 审批后执行

向用户呈现预览，确认要执行的范围。将历史导出复制为独立的approved_plan.json，保留全部actions、expected_files与证据哈希，仅填approval：

```json
{
  "approved": true,
  "approved_by": "实际确认者",
  "approved_at": "2026-09-18T10:00:00+08:00",
  "task_ids": ["T0002", "T0003"]
}
```

不要照抄示例时间或姓名，也不能把Agent自己生成意见当成用户批准。approval是工作流记录，不是身份认证或密码学签名。

```powershell
.\04Reference3.ps1 -BookName MyBook -PlanPath 'C:\实际工作区\某轮次\approved_plan.json' -Mode Apply
```

Apply必须使用approval.task_ids明确列出的范围，不接受TaskId临时扩大范围。范围内只能是modify/no_change，范围外的pending/defer不执行并计入报告。由此可先执行已确认的两项，不要求整书完成核验，但也不宣称整书已审核通过。

## 4. 检查和修改范围

执行前核对书名、schema、任务计划哈希、输入快照、所有正文MD是否新增或变化、任务身份、证据哈希、结构化决定、旧值以及04R一致性。

允许修改url、verification_url、title、publication、year、volume、issue、pages、authors。不接受任意文件路径、命令、verified标记、来源id或正文改写。网址须为HTTPS。重复字段或冲突修改拒绝执行。

修改落在`00_brief/references/reference_state.json`对应source_id上；随后按04R的格式重生成`02_chapters/references.md`。更新verification_url不改变书末显示内容，更新url则同步所有分组中该来源条目的链接。正文标记、编号及正文内容不变。

## 5. 备份、恢复和后续操作

- 备份：`back/reference3_<时间与随机ID>`，保存原始状态、参考文献、已有格式标记及批准计划。
- 报告：`04_output/editorial_audits/reference_executions/<时间与随机ID>/execution.json`及execution.md，记录范围、原新值、检查和备份位置。执行期失败恢复备份并保存JSON失败报告。
- 成功修改后重新运行04R Check；删除旧04F标记以要求重新检查，而不是伪造新审批。
- 不自动生成PDF/EPUB。执行后运行04F Check，通过后再调用05。
- 修改后原复核轮次的输入哈希已过期，后续核验需新建04R2轮次。再次执行旧计划会被拒绝，不重复修改。
- 只有no_change的批准计划不会修改任何书稿文件，也不会失效原格式标记。

程序用reference3.lock阻止两个04R3进程并发，但其他编辑器或旧脚本不遵守此锁，因此操作期间仍禁止并发编辑。异常退出/断电不保证自动恢复；若留下锁文件，先确认没有运行中的执行进程，核对备份和实际文件，再人工恢复。不要自动删除不明锁或覆盖现有稿件。

执行前的参数或版本检查失败直接报错，不生成“成功”报告。不得跳过检查或修改哈希来强行执行。
