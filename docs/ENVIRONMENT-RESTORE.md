# 环境恢复与安装清单

本发布包是程序、说明、配置示例及依赖清单，不是整台Windows的镜像或离线一键环境。不得复制原电脑的API密钥、浏览器登录、Word许可证或用户配置。书籍工作区不在程序包内，需要单独迁移。

## 依赖与本机基线

以下为2026-09-24发布时检测到的版本，不代表最低版本或所有组合均已测试。

| 组件 | 本机基线 / 要求 | 用途 |
| --- | --- | --- |
| Windows PowerShell | 5.1.26100.9444；powershell.exe必须可用 | 多个脚本内部显式调用 |
| PowerShell 7 | 7.6.5，可选入口 | 不能代替缺失的Windows PowerShell |
| Node.js | v24.13.0，附带npm | Web工作台及发布自动化 |
| Python | 3.14.2 | 简版DOCX与测试 |
| Python包 | requirements-docx.txt固定本机版本 | python-docx及其依赖 |
| Pandoc | 3.9 | DOCX、EPUB构建 |
| Microsoft Word | 桌面版，目标设备自行安装、激活 | 当前05c/05cc通过COM导出PDF |
| Git | 2.53.0.windows.1 | 获取代码和版本管理 |
| 中文字体 | 与书籍排版配置一致 | 字体替代会改变换行及页数 |
| ImageMagick | 可选，magick命令 | 部分封面/图片辅助工具 |
| 浏览器及Playwright | 可选；automation/package-lock.json | 发布辅助；目标平台账号需另行授权 |

## 新设备步骤

1. 从本Release下载完整ZIP，或克隆sagewrite-ps1-20260924标签，保留engine和docs同级结构。
2. 按目标功能从官方渠道安装上述依赖，再打开新终端检查PATH。安装器主要写配置，不安装全部依赖。
3. 需要简版DOCX时，创建独立Python环境并安装下方清单；确认调用python的进程已经激活该环境。
4. Web核心package.json无第三方依赖。需要发布自动化时，在engine/automation运行npm ci，使用已有锁文件；浏览器和平台认证另外配置。
5. 用户在目标机器安全配置OPENAI_API_KEY；Agent只检查是否存在，不显示值。设置SAGEWRITE_WORKSPACE_ROOT为可写工作区父目录。环境模板仅说明字段，不会自动被PS1加载。
6. 在engine运行Install-SageWrite-Standalone.ps1 -Mode local -WorkspaceRoot '<实际父目录>' -DryRun；不要在DryRun中传真实密钥或密码，因为它会输出配置。确认后去掉DryRun。默认只监听127.0.0.1，不自动开启远程服务。
7. 按Agent手册在独立测试书籍上初始化、生成一节、审读、核验、04F检查，再导出DOCX/PDF/EPUB。每个阶段报告通过、未测试或阻塞，不能将一次DryRun成功称为全流程验收。

```powershell
# 从仓库根目录执行；仅在需要Python路线时配置
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r docs/requirements-docx.txt
```

PS1的模型调用与Codex会话独立。当前相关脚本使用固定OpenAI Responses端点，部分默认gpt-5.5；需可访问该模型的API权限及配额。不能仅改环境变量就宣称兼容豆包或其他服务商。具体以各脚本param与调用实现为准。

## 配置与安全

- 安全配置变量名示例见[environment.example.psd1](environment.example.psd1)，不含任何凭据，不是自动加载器。
- 安装器生成的engine/sagewrite-web.config.psd1只留本机；网页与PS1必须指向同一工作区父目录。
- GitHub版本包含依赖声明，不含node_modules、Python环境、Word、浏览器个人资料或原书稿。
- 发布前检查源码包及提交范围；环境变量快照、聊天记录、日志和截图不得随包上传。
- 带登录和真实发布的09流程须单独确认，不作为安装验收自动执行。

本次验证不等于在全新Windows电脑上重新安装并跑完00至09全部有副作用流程。
