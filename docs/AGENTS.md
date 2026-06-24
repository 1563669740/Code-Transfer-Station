# AGENTS.md

## 项目执行规则 — 必须优先遵守

本项目的完整执行规则定义在 **docs/RUNBOOK.md** 中。在修改任何代码之前，必须先理解 RUNBOOK.md 的约束。

## 三条核心命令（不可绕过）

```bash
# 本地运行（修改代码后必须先跑通）
bash run.sh

# 本地测试（必须全部通过）
python3 -m pytest -q

# 推送到远端（本地验证通过后提交推送）
git add -A && git commit -m "描述修改内容" && git push
```

## 远程执行（自动化流程）

本项目的远程执行采用 **Git 拉取模型**：控制服务器通过定时轮询 GitHub/Gitee 仓库，发现新 commit 后自动拉取并执行。

```
Windows / Codex                          控制服务器
  修改代码 → 本地验证 → git push    →    定时 fetch → 发现新commit → pull → run.sh → pytest
                                              │
                                              └── 可选：将执行日志推回仓库 (run-logs 分支)
```

控制服务器上的部署脚本：
- `scripts/server_pull_run.sh` — 常驻守护进程，每 60 秒轮询，带超时保护
- `scripts/server_pull_once.sh` — 单次执行版，配合 cron 使用，带超时保护
- `scripts/server_push_log.sh` — 日志回传脚本，将执行结果推回仓库

## 禁止行为

- ❌ 猜测项目入口 — 统一走 `bash run.sh`
- ❌ 手动 `scp` / `rsync` / `ssh` 登录服务器改代码
- ❌ 把服务器密码、SSH 私钥、API key、token 写入代码或日志
- ❌ 在控制服务器上手改代码（应通过 git push 触发自动拉取）

## 项目结构

```
main.py                   项目主入口（只做入口，不放业务逻辑）
run.sh                    本地统一启动脚本
Makefile                  常用命令快捷方式
requirements.txt          Python 依赖
src/                      业务代码
tests/                    测试代码
scripts/
  bootstrap_new_machine.sh  新机器一键配置脚本
  server_pull_run.sh        控制服务器常驻轮询守护进程
  server_pull_once.sh       控制服务器 cron 单次轮询
  server_push_log.sh        控制服务器日志回传（可选）
docs/                     项目文档
  CLAUDE.md / AGENTS.md / RUNBOOK.md  项目执行规则
  NEW_MACHINE_SETUP.md                 新机器环境配置指南
  *.docx                               部署流程记录等
tools/                    辅助工具脚本
  generate_docx.py          生成 docx 文档
```

## 修改代码后的标准流程

1. 修改 `src/` 或 `tests/` 中的代码
2. 如有新依赖，更新 `requirements.txt`
3. `bash run.sh` — 本地跑通
4. `python3 -m pytest -q` — 测试通过
5. `git add -A && git commit -m "..." && git push` — 推送到远端
6. 控制服务器会在 60 秒内自动拉取并执行，结果写入 `~/codex_pull_logs/latest.log`
7. 如果配置了 `LOG_PUSH_REMOTE`，服务器执行日志也会自动推回仓库的 `run-logs` 分支

## 查看远程执行结果

如果控制服务器配置了日志回传，Codex 可以拉取 run-logs 分支查看结果：

```bash
git fetch origin run-logs && git show origin/run-logs:logs/run_*.log | tail -n 80
```

否则需要用户在控制服务器上通过 VNC 查看 `~/codex_pull_logs/latest.log`。
