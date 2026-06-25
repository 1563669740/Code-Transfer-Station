# AGENTS.md

## 项目执行规则 — 必须优先遵守

本项目的完整执行规则定义在 **docs/RUNBOOK.md** 中。在修改任何代码之前，必须先理解 RUNBOOK.md 的约束。

## 三条核心规则（不可绕过）

```text
1. Codex 本地禁止运行项目业务代码、run.sh、pytest、make run、make test。
2. Codex 本地只做编辑、阅读、静态检查、清单一致性维护和 Git 提交推送。
3. 控制服务器拉取新 commit 后自动执行 bash run.sh 和 python3 -m pytest -q。
```

## 远程执行（自动化流程）

本项目的远程执行采用 **Git 拉取模型**：控制服务器通过定时轮询 GitHub/Gitee 仓库，发现新 commit 后自动拉取并执行。

```text
Windows / Codex                          控制服务器
  修改代码 -> 静态检查 -> git push   ->    定时 fetch -> 发现新 commit -> pull -> run.sh -> pytest
                                               |
                                               +-- 可选：将执行日志推回仓库 (run-logs 分支)
```

控制服务器上的部署脚本：

- `scripts/server_pull_run.sh` — 常驻守护进程，每 60 秒轮询，带超时保护
- `scripts/server_pull_once.sh` — 单次执行版，配合 cron 使用，带超时保护
- `scripts/server_sync_latest.sh` — 服务器不会自动更新时，在控制服务器上手动同步并执行最新代码
- `scripts/server_push_log.sh` — 日志回传脚本，将执行结果推回仓库

## 禁止行为

- 禁止 Codex 本地执行 `bash run.sh`、`python3 -m pytest -q`、`pytest`、`make run`、`make test`
- 禁止猜测项目入口或绕过服务器执行模型
- 禁止手动 `scp` / `rsync` / `ssh` 登录服务器改代码
- 禁止把服务器密码、SSH 私钥、API key、token 写入代码或日志
- 禁止在控制服务器上手改代码，应通过 git push 触发自动拉取

## 项目结构

```text
main.py                   项目主入口（只做入口，不放业务逻辑）
run.sh                    控制服务器统一启动脚本
Makefile                  常用命令快捷方式（Codex 本地不得执行 run/test 目标）
requirements.txt          Python 依赖
src/                      业务代码
tests/                    测试代码
scripts/
  bootstrap_new_machine.sh  新机器一键配置脚本
  server_pull_run.sh        控制服务器常驻轮询守护进程
  server_pull_once.sh       控制服务器 cron 单次轮询
  server_sync_latest.sh     控制服务器手动同步最新代码脚本
  server_push_log.sh        控制服务器日志回传（可选）
docs/                     项目文档
  CLAUDE.md / AGENTS.md / RUNBOOK.md  项目执行规则
  NEW_MACHINE_SETUP.md                 新机器环境配置指南
  *.docx                               部署流程记录等
tools/                    辅助工具脚本
  generate_docx.py          生成 docx 文档
```

## 修改代码后的标准流程

1. 修改 `src/` 或 `tests/` 中的代码。
2. 如有新依赖，更新 `requirements.txt`。
3. 如涉及新的核心业务入口，同步更新 `docs/CURRENT_BUSINESS.json`、`main.py`、`src/` 和 `tests/`，删除旧业务残留。
4. 只做不执行业务代码的静态检查和文本检查。
5. `git add -A && git commit -m "..." && git push` 推送到远端。
6. 控制服务器会在轮询周期内自动拉取并执行，结果写入 `~/codex_pull_logs/latest.log`。
7. 如果配置了 `LOG_PUSH_REMOTE`，服务器执行日志也会自动推回仓库的 `run-logs` 分支。

## 查看远程执行结果

如果控制服务器配置了日志回传，Codex 可以拉取 run-logs 分支查看结果：

```bash
git fetch origin run-logs && git show origin/run-logs:logs/latest_run_output.log
```

否则需要用户在控制服务器上通过 VNC 或终端查看 `~/codex_pull_logs/latest.log`。
