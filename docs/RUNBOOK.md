# RUNBOOK.md

# Project Run Rules for Codex

本文件是写给 Codex 的项目执行规则。Codex 在修改本项目代码或文档时，必须优先遵守本文件。

本项目的目标是：

1. 在本地完成代码修改和静态检查。
2. 禁止 Codex 在本地执行项目业务代码、启动入口或测试套件。
3. 通过 Git push 将代码推送到远端仓库。
4. 控制服务器自动拉取新代码、执行、测试并记录日志。
5. 禁止手动 scp、手动 ssh 登录服务器改代码、泄露密码或私钥。

------

## 1. 核心原则

Codex 必须遵守以下原则：

1. 不要猜测项目入口。
2. 不要临时拼接 scp、ssh、sudo 等高风险命令。
3. Codex 本地只能做编辑、阅读、静态检查和清单一致性维护；不得运行项目入口、业务脚本或测试套件。
4. 项目执行统一交给控制服务器。控制服务器拉取新 commit 后，按固定入口执行：

   ```bash
   bash run.sh
   python3 -m pytest -q
   ```

5. 本地修改完成并完成非执行业务代码的检查后，推送到远端：

   ```bash
   git add -A && git commit -m "描述修改内容" && git push
   ```

6. 控制服务器会自动拉取新 commit 并执行，无需 Codex 在本地运行或手动触发服务器。
7. 不要把服务器密码、SSH 私钥、API key、token、cookie 写入代码、日志或回答中。

------

## 2. 本地禁止执行规则

### 2.1 Codex 本地禁止运行项目入口

Codex 修改代码后，不得在本地运行以下命令或等价命令：

```bash
bash run.sh
make run
python main.py
python3 main.py
```

`run.sh` 是控制服务器上的统一启动入口，不是 Codex 本地验证入口。不要绕过 `run.sh` 猜测复杂命令，也不要在本地直接运行 Python 业务入口。

### 2.2 Codex 本地禁止运行测试套件

Codex 不得在本地运行以下命令或等价命令：

```bash
python3 -m pytest -q
python -m pytest -q
pytest
make test
```

测试由控制服务器在拉取新 commit 后自动执行。Codex 可以阅读测试、修改测试、做语法级或文本级检查，但不得通过本地执行测试来验证业务逻辑。

### 2.3 本地允许的非执行检查

Codex 可以在本地执行不启动项目、不跑测试、不调用业务入口的检查，例如：

```bash
git status
git diff
rg "关键字"
```

如果某个检查可能导入或执行业务代码，应视为禁止。文档生成、DOCX 渲染、静态文本检查可以执行，但不得借此运行 `main.py`、`run.sh`、`pytest` 或业务模块入口。

------

## 3. 远程执行规则（Git 拉取模型）

本项目采用 **Git 拉取模型**：控制服务器通过定时轮询远端仓库，发现新 commit 后自动拉取并执行。

```text
Windows / Codex（开发机）              控制服务器
  1. 修改代码                             1. 定时 git fetch
  2. 静态检查/清单检查                     2. 检测到新 commit -> git merge --ff-only
  3. git commit && git push               3. bash run.sh
         |                                4. python3 -m pytest -q
         v                                5. 写入 ~/codex_pull_logs/latest.log
    GitHub / Gitee 仓库  <--------------- 日志回传可选
```

Codex 负责：

1. 阅读 `docs/RUNBOOK.md` 和相关代码。
2. 修改 `docs/CURRENT_BUSINESS.json`、`main.py`、`src/`、`tests/` 等必要文件。
3. 删除旧业务残留，维护当前业务清单一致性。
4. 做不执行业务代码的静态检查。
5. 提交并推送到远端。

Codex 不得：

- 在本地运行 `bash run.sh`。
- 在本地运行 `python3 -m pytest -q`、`pytest` 或 `make test`。
- 手动触发控制服务器。
- SSH 登录控制服务器。
- 等待控制服务器执行结果作为本地验证步骤。

控制服务器脚本：

- `scripts/server_pull_run.sh`：常驻守护进程版。
- `scripts/server_pull_once.sh`：单次执行版，适合 cron。
- `scripts/server_sync_latest.sh`：在控制服务器上手动同步远端最新代码、强制执行一次，并可重启 daemon。
- `scripts/server_push_log.sh`：日志回传组件。

------

## 4. 服务器不会自动更新时

如果逻辑代码已经 push，但服务器没有自动更新，用户应在控制服务器上使用同步脚本：

```bash
cd ~/codex_projects/project
bash scripts/server_sync_latest.sh
```

常用参数：

```bash
bash scripts/server_sync_latest.sh --no-force-scripts
bash scripts/server_sync_latest.sh --no-run-once
bash scripts/server_sync_latest.sh --no-restart-daemon
```

Codex 只能把这类命令写入文档或提示用户执行，不得本地执行，也不得通过 SSH 代替用户执行。

------

## 5. 外部数据规则

如果执行代码需要外部数据，而数据不在项目文件夹里：

1. 不要把本机绝对路径写入代码、文档示例或提交记录。
2. 不要把大数据、隐私数据、密钥文件提交到仓库。
3. 在控制服务器上准备数据目录，并通过环境变量传入，例如 `DATA_DIR=/data/project_inputs`。
4. 在 `.env.example` 或部署文档中写变量名、目录结构和示例值，不写真实敏感路径或真实数据。
5. 业务代码应从环境变量读取路径；缺少数据时给出清晰错误信息，不要回退到开发机路径。
6. 如果数据需要随运行产出保存，输出写入 `RUN_ARTIFACT_DIR`，由服务器脚本统一归档。

------

## 6. 代码修改规则

Codex 修改代码时，应遵守以下规则：

1. `main.py` 只作为项目主入口，并且必须直接指向当前最新核心业务入口。
2. 当前最新核心业务入口、允许保留的 `src/` 文件、允许保留的业务/基础设施测试，必须记录在 `docs/CURRENT_BUSINESS.json`。
3. 每次生成新的核心业务代码时，必须在同一次修改中完成：更新 `docs/CURRENT_BUSINESS.json`、更新 `main.py`、删除旧业务代码文件、删除或替换旧业务测试。
4. `src/` 只保留当前核心业务必需文件和明确登记的通用基础设施文件；历史业务代码不得留在 `src/` 中。
5. `tests/` 只保留当前业务测试和基础设施测试；历史业务测试不得继续保留。
6. 新增依赖时，必须更新 `requirements.txt`。
7. 不要在代码中写死本机绝对路径、服务器路径、密码、token、私钥或 API key。
8. 修改功能后，尽量补充或更新测试，但不要在本地执行测试。

当前业务清单由 `tests/test_current_business_manifest.py` 在控制服务器测试阶段强制校验。

------

## 7. Codex 每次任务的标准流程

```text
1. 理解用户需求。
2. 查看相关文件。
3. 修改代码或文档。
4. 如有必要，更新 requirements.txt。
5. 如有必要，更新 tests/ 和 docs/CURRENT_BUSINESS.json。
6. 做不执行业务代码的静态检查和清单一致性检查。
7. git add -A / commit / push。
8. 告知用户已推送，控制服务器将在轮询周期内自动拉取执行。
9. 总结修改了哪些文件、哪些本地执行被禁止并已跳过、服务器将如何验证。
```

------

## 8. 最重要的规则

```text
Codex 本地禁止运行：bash run.sh / python3 -m pytest -q / make run / make test
控制服务器执行：bash run.sh / python3 -m pytest -q
推送到远端：git add -A && git commit -m "..." && git push
```

不要猜入口。不要本地执行代码。不要手动上传。不要手动登录服务器改代码。不要泄露密码、私钥、API key。
失败后阅读服务器日志，本地修复代码但不执行代码，重新 push 即可。
