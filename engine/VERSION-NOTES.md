# SageWrite 版本说明

## 当前开发分支

当前开发分支已经开始进入 **多用户云系统基础阶段**。

已开始接入：

- `AuthMode = 'users'` 用户账号登录
- JSON 用户库
- 管理员初始账号自动创建
- 当前登录用户工作区隔离
- Web 任务绑定当前用户
- 管理员用户列表和创建用户 API

上一版单用户独立安装版已经用 Git 标签锁定：

```text
sagewrite-single-user-standalone-d926c61
```

## 当前版本定位

标签 `sagewrite-single-user-standalone-d926c61` 对应的是 **单用户本地/个人云独立版**。

这个版本已经具备：

- 本地 Web 控制台入口
- 可配置 Host、Port、工作区根目录
- 密码登录保护
- 单用户个人云部署模式
- Windows 后台自启动任务入口
- 独立安装入口和打包入口

这个版本不作为多用户云系统使用。

当前版本不包含：

- 多用户账号体系
- 用户之间的工作区隔离
- 多租户权限模型
- 多人同时编辑同一项目的锁机制
- 面向外部用户开放注册的 SaaS 能力

## 后续版本方向

从后续版本开始，再进入 **多用户云系统** 阶段。

多用户云系统需要新增：

- 用户账号表
- 用户登录身份与 session 绑定
- 每个用户独立工作区根目录
- 每个任务绑定用户和项目
- 文件 API 按用户隔离
- 项目级权限和并发写入保护
- 管理员后台和用户管理

## 当前版本安装入口

单用户独立版的安装入口是：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-SageWrite-Standalone.ps1
```

本地启动：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-SageWrite-Standalone.ps1 -Mode local -StartNow
```

个人云/Windows 服务器启动：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-SageWrite-Standalone.ps1 -Mode cloud -AdminPassword "change-this-password" -WorkspaceRoot "D:\SageWriteWorkspaces" -InstallAutoStart -TaskTrigger AtStartup -AsSystem -StartNow
```

## 当前版本打包入口

从 Git 当前提交生成独立安装包：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\New-SageWrite-StandalonePackage.ps1
```
