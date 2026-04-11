# 09 统一出版元数据总目录

## 一、定位

这份目录用于定义 **09 上架单元的跨平台统一元数据底稿**。

它的目标不是替代 Amazon / Apple / Google 各自的平台包，而是先形成一份：

- 与平台无关
- 可被人工编辑
- 可被脚本自动转换
- 可被多语言版本分别复用

的统一出版元数据主文件。

一句话说：

> **一本书的每一个语种版本，都应先有一份自己的统一出版元数据，再由 09c / 09d / 09e 分别转换成各平台提交包。**

---

## 二、总原则

09 的统一元数据应分成三层：

1. **核心识别层**
   这层定义“这本书是谁、是什么、什么语言、由谁出版”。

2. **营销发现层**
   这层定义“平台如何展示、检索、推荐这本书”。

3. **分发交付层**
   这层定义“提交哪些文件、投放哪些平台、以什么格式发布”。

其中：

- **核心识别层** 是最稳定的
- **营销发现层** 会随着语言、市场、平台策略调整
- **分发交付层** 会随着输出文件和目标平台变化

---

## 三、统一元数据主目录

建议把 09 的统一出版元数据整理为下面 8 组。

### 1. `identification` 识别信息

这是所有平台都需要的最基础信息。

建议字段：

- `book_name`
  书的工程代号
- `language`
  语种代码，如 `zh` / `en` / `ms`
- `language_name`
  语种显示名，如 `Chinese` / `English` / `Malay`
- `title`
  主书名
- `subtitle`
  副标题
- `author`
  作者主名
- `publisher`
  出版主体
- `imprint`
  品牌名 / 出版品牌
- `publication_date`
  计划发布日期
- `edition_type`
  版本类型，如 `digital` / `ebook` / `print`

这是最核心的一层，建议永远保留。

---

### 2. `contributors` 署名与责任信息

这是后续最值得补强的一层。当前 09 里只有 `author`，但正式出版最好单独拆出来。

建议字段：

- `primary_author`
- `contributors`
  贡献者数组，可包含：
  - `role`
  - `name`
  - `sort_order`
- `translator`
- `editor`
- `designer`
- `illustrator`

说明：

- Amazon / Apple / Google 对署名的要求不完全一致
- 所以统一底稿里最好先存“责任者结构”
- 平台脚本再转成各自格式

---

### 3. `rights_metadata` 权利与版权信息

这是所有平台都会用到的正式出版信息。

建议字段：

- `copyright_holder`
- `copyright_year`
- `rights_statement`
- `territory`
- `distribution_rights`
- `license`
- `publisher`
- `imprint`
- `original_language`
- `translation_rights`
- `ai_assistance_disclosure`

当前 09 已实际使用的字段：

- `copyright_holder`
- `copyright_year`
- `rights_statement`
- `territory`
- `distribution_rights`
- `license`
- `publisher`
- `imprint`

---

### 4. `marketing` 营销文案信息

这是平台详情页、封底、腰封、营销摘要会反复使用的部分。

建议字段：

- `tagline`
  宣传语 / 核心短句
- `subtitle`
  副标题
- `short_description`
  短简介
- `long_description`
  长简介
- `cover_hook`
  封面钩子句
- `back_cover_blurb`
  封底文案
- `obi_copy`
  腰封文案
- `author_bio`
  作者简介
- `spine_text`
  书脊文字
- `elevator_pitch`
  一句话卖点
- `selling_points`
  卖点列表

当前 09 已实际使用的字段：

- `tagline`
- `short_description`
- `long_description`
- `cover_hook`
- `back_cover_blurb`
- `obi_copy`
- `author_bio`
- `spine_text`

---

### 5. `discovery` 发现与检索信息

这部分决定平台如何检索、推荐和归类这本书。

建议字段：

- `keywords`
- `categories`
- `platform_recommended_categories`
- `audience`
- `book_type`
- `core_thesis`
- `chapter_count`
- `chapter_titles`
- `search_terms`
- `bisac_like_subjects`
- `market_positioning`

当前 09 已实际使用的字段：

- `keywords`
- `categories`
- `platform_recommended_categories`
- `audience`
- `book_type`
- `core_thesis`
- `chapter_count`
- `chapter_titles`

说明：

- `categories` 建议保存“通用分类”
- `platform_recommended_categories` 保存“平台映射建议”
- 真正提交时由平台脚本各自落地

---

### 6. `distribution` 分发与投放信息

这部分定义发布去哪里、用什么格式。

建议字段：

- `formats`
  如 `EPUB` / `PDF` / `DOCX`
- `primary_format`
- `target_platforms`
  如 `amazon` / `apple` / `google`
- `marketplaces`
  如 `amazon.com`
- `drm_preference`
- `pricing_model`
- `release_mode`
  如 `draft` / `scheduled` / `live`

当前 09 已实际使用的字段：

- `formats`
- `primary_format`
- `target_platforms`

---

### 7. `source_files` 交付源文件信息

这是 09 真正能跑起来的重要工程层字段。

建议字段：

- `cover`
- `epub`
- `pdf`
- `docx`
- `assets`
- `metadata_master`
- `toc`
- `objective`

当前 09 已实际使用的字段：

- `cover`
- `epub`
- `pdf`
- `docx`
- `assets`

说明：

- 这是工程层最关键的一组
- 它不属于出版学意义上的元数据，但属于 SageWrite 的发布元数据

---

### 8. `platform_overrides` 平台专属覆盖项

这组建议新增，但不要和“统一底稿”混在一起。

建议字段：

- `amazon`
  - `primary_marketplace`
  - `adult_only`
  - `contributors`
  - `kdp_keywords`
  - `kdp_categories`
- `apple`
  - `vendor_id`
  - `apple_categories`
  - `audience_code`
- `google`
  - `google_subject_codes`
  - `availability_regions`

原则：

- 默认先读统一底稿
- 只有确实平台特有的字段才放到 `platform_overrides`

---

## 四、当前最适合所有平台发布的“最小通用主目录”

如果只保留一份最有价值、最稳定、最适合跨平台复用的元数据主目录，我建议定成下面这 6 组：

1. `identification`
2. `contributors`
3. `rights_metadata`
4. `marketing`
5. `discovery`
6. `distribution`

再额外附带：

7. `source_files`
8. `platform_overrides`

这就是 09 后续最适合长期稳定演化的统一结构。

---

## 五、建议的标准主文件结构

建议未来把每个语言版本的主文件统一成：

```json
{
  "generated_at": "",
  "book_name": "",
  "language": "",
  "language_name": "",
  "identification": {},
  "contributors": {},
  "rights_metadata": {},
  "marketing": {},
  "discovery": {},
  "distribution": {},
  "source_files": {},
  "platform_overrides": {}
}
```

说明：

- 顶层只保留少量索引字段
- 真正的数据尽量收进分组对象里
- 这样更适合做 Web 编辑界面，也更适合后续扩展

---

## 六、当前 09 已有字段与建议结构的对应关系

### 已经基本稳定的字段

- `title`
- `subtitle`
- `author`
- `publisher`
- `imprint`
- `publication_date`
- `rights`
- `copyright_holder`
- `copyright_year`
- `territory`
- `distribution_rights`
- `edition_type`
- `audience`
- `book_type`
- `style`
- `scope`
- `core_thesis`
- `short_description`
- `long_description`
- `marketing_tagline`
- `cover_hook`
- `back_cover_blurb`
- `obi_copy`
- `author_bio`
- `spine_text`
- `keywords`
- `categories`
- `platform_recommended_categories`
- `formats`

### 建议后续再正式补齐的字段

- `contributors`
- `translator`
- `editor`
- `designer`
- `illustrator`
- `isbn`
- `series`
- `series_number`
- `pricing_model`
- `drm_preference`
- `ai_assistance_disclosure`
- `platform_overrides`

---

## 七、建议的工程落点

建议每个语言版本下都保留一份统一元数据主文件：

```text
09_publish/
  zh/
    publish_metadata.json
    publish_metadata.md
  en/
    publish_metadata.json
    publish_metadata.md
  ms/
    publish_metadata.json
    publish_metadata.md
```

后续如果要再规范一层，可以增加：

```text
09_publish/
  zh/
    publish_metadata_master.json
    publish_metadata_master.md
```

然后：

- `09c-amazon.ps1` 读取它，生成 Amazon 包
- `09d-apple.ps1` 读取它，生成 Apple 包
- `09e-google.ps1` 读取它，生成 Google 包

---

## 八、最终建议

09 的统一发布元数据，建议明确区分成三类：

### A. 核心底稿

这些字段应由人工确认，且尽量稳定：

- 书名
- 副标题
- 作者
- 语言
- 出版主体
- 版权归属
- 长简介
- 关键词
- 通用分类

### B. 平台转换层

这些字段可由脚本根据核心底稿自动派生：

- 平台推荐分类
- 平台关键词格式
- 平台提交包 JSON
- 平台提交清单

### C. 平台专属覆盖层

这些字段只在必要时人工单独修改：

- Amazon 特有设置
- Apple 特有设置
- Google 特有设置

---

## 九、一句话定义

> **09 的统一出版元数据，本质上应是一份“每个语种一本书”的跨平台出版主档案；平台脚本只是把它翻译成 Amazon、Apple、Google 各自需要的提交结构。**
