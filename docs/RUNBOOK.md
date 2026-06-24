# RUNBOOK.md

# Project Run Rules for Codex

本文件是写给 Codex 的项目执行规则。
Codex 在修改本项目代码时，必须优先遵守本文件。

本项目的目标是：

1. 在本地完成代码修改。
2. 使用统一入口运行和测试项目。
3. 通过 Git push 将代码推送到远端仓库。
4. 控制服务器自动拉取新代码、执行、记录日志。
5. 禁止手动 scp、手动 ssh 登录服务器改代码、泄露密码或私钥。

------

## 1. 核心原则

Codex 必须遵守以下原则：

1. 不要猜测项目入口。

2. 不要临时拼接 scp、ssh、sudo 等高风险命令。

3. 本地运行统一使用：

   ```bash
   bash run.sh
   ```

4. 本地测试统一使用：

   ```bash
   python3 -m pytest -q
   ```

5. 本地验证通过后，推送到远端：

   ```bash
   git add -A && git commit -m "描述修改内容" && git push
   ```

6. 控制服务器会自动拉取新 commit 并执行，无需 Codex 手动触发。

7. 不要把服务器密码、SSH 私钥、API key、token、cookie 写入代码、日志或回答中。

------

## 2. 当前项目结构

```text
project/
  main.py
  run.sh
  Makefile
  requirements.txt
  src/
  tests/
  scripts/
    bootstrap_new_machine.sh  新机器一键配置脚本
    server_pull_run.sh        控制服务器常驻轮询守护进程
    server_pull_once.sh       控制服务器 cron 单次轮询
    server_push_log.sh        控制服务器日志回传（可选）
  docs/
    CLAUDE.md / AGENTS.md / RUNBOOK.md  项目执行规则
    NEW_MACHINE_SETUP.md                 新机器环境配置指南
    *.docx                               部署流程记录等
  tools/
    generate_docx.py          生成 docx 文档
  .gitignore
```

各文件职责如下：

```text
main.py                      项目主入口
src/                         业务代码目录
tests/                       测试代码目录
run.sh                       本地统一启动脚本
Makefile                     统一 run/test/pull-daemon/pull-once 命令
scripts/bootstrap_new_machine.sh   新机器一键配置脚本
scripts/server_pull_run.sh         控制服务器轮询守护进程（带超时/重试/日志回传）
scripts/server_pull_once.sh        控制服务器 cron 单次轮询（带超时/重试/日志回传）
scripts/server_push_log.sh         控制服务器日志回传脚本（可选组件）
docs/                         项目文档（规则/指南/流程记录）
tools/                        辅助工具脚本
requirements.txt             Python 依赖列表
RUNBOOK.md                   Codex 执行规则（本文件）
```

------

## 3. 本地运行规则

### 3.1 默认启动命令

Codex 修改代码后，必须先运行：

```bash
bash run.sh
```

`run.sh` 是本项目的统一启动入口。
不要绕过 `run.sh` 直接猜测复杂命令。

------

### 3.2 默认测试命令

如果项目中存在 `tests/` 目录，Codex 修改代码后必须运行：

```bash
python3 -m pytest -q
```

如果测试失败，Codex 应根据报错修改代码，然后重新运行测试。

------

### 3.3 Makefile 命令

如果需要使用 `Makefile`，允许使用：

```bash
make run
make test
```

其中：

```text
make run   等价于 bash run.sh
make test  等价于 python3 -m pytest -q
```

不要新增危险的 Makefile 目标，例如自动执行 `sudo`、`rm -rf`、`curl | bash` 等。

------

## 4. 远程执行规则（Git 拉取模型）

本项目采用 **Git 拉取模型**：控制服务器通过定时轮询远端仓库，发现新 commit 后自动拉取并执行。

### 4.1 架构

```
Windows / Codex（开发机）              控制服务器
  1. 修改代码                             1. 定时 git fetch
  2. bash run.sh                          2. 检测到新 commit → git merge --ff-only
  3. python3 -m pytest -q                 3. bash run.sh
  4. git commit && git push               4. python3 -m pytest -q
         |                                5. 写入 ~/codex_pull_logs/latest.log
         v                                       ^
    GitHub / Gitee 仓库 ─────────────────────────┘
```

### 4.2 Codex 侧的职责

Codex 只需要做三件事 — 本地验证通过后推送到远端：

```bash
bash run.sh                  # 本地跑通
python3 -m pytest -q         # 测试通过
git add -A && git commit -m "描述修改" && git push   # 推送到远端
```

Codex **不需要**：
- 手动触发控制服务器
- SSH 登录控制服务器
- 等待控制服务器执行结果（结果在服务器日志中，用户自行查看）

### 4.3 控制服务器侧的自动化

控制服务器上运行 `scripts/server_pull_run.sh`（常驻守护进程），逻辑如下：

```
while true:
  1. git fetch origin main
  2. 比较 remote_sha vs last_run_sha
     └─ 相同 → 已经测过，跳过 → sleep 30s
     └─ 不同 → 发现新代码！
        ├─ git merge --ff-only origin/main
        ├─ bash run.sh
        ├─ python3 -m pytest -q
        ├─ 记录已执行 commit
        └─ 写日志 → sleep 30s
```

核心脚本特性：

| 特性 | 说明 |
|------|------|
| 执行超时 | `RUN_TIMEOUT`（默认 600s），防止 `run.sh` 或 `pytest` 挂起卡死轮询 |
| 拉取重试 | `FETCH_RETRIES`（默认 3 次），应对 GitHub 临时不可用 |
| 日志回传 | 可选 `LOG_PUSH_REMOTE`，执行后自动将日志推到仓库 `run-logs` 分支 |
| 脚本输出 | 默认 `LOG_PUSH_MODE=run-output`，服务端执行 `bash run.sh` 时同步写入 `$LOG_DIR/latest_run_output.log`，不会为了查看结果重新运行脚本 |
| 固定文件名 | 默认回传到 `run-logs` 分支的 `logs/latest_run_output.log`，便于直接 `git show` 查看 |
| 本机清理 | 控制服务器本机时间戳日志默认保留 14 天（`LOG_RETENTION_DAYS=14`），固定输出文件不清理 |

脚本：

- `scripts/server_pull_run.sh`：常驻守护进程版（`nohup` 后台运行）
- `scripts/server_pull_once.sh`：单次执行版（配合 `cron` 每分钟触发）
- `scripts/server_push_log.sh`：日志回传组件（由上述两个脚本自动调用）

### 4.4 控制服务器一次性配置

```bash
# 1. 生成只读 deploy key
mkdir -p ~/.ssh && chmod 700 ~/.ssh
ssh-keygen -t ed25519 -f ~/.ssh/codex_pull_deploy_key -C "codex-pull-deploy" -N ""
cat ~/.ssh/codex_pull_deploy_key.pub
# 将 .pub 公钥添加到 GitHub/Gitee 仓库的 Deploy keys（只读权限）

# 2. 配置 SSH Host
cat >> ~/.ssh/config <<'EOF'
Host github-codex-pull
  HostName github.com
  User git
  IdentityFile ~/.ssh/codex_pull_deploy_key
  IdentitiesOnly yes
EOF
chmod 600 ~/.ssh/config
ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null || true

# 3. 克隆项目
mkdir -p ~/codex_projects
git clone git@github-codex-pull:OWNER/REPO.git ~/codex_projects/project

# 4. 手动验证
cd ~/codex_projects/project
bash run.sh
python3 -m pytest -q
```

### 4.5 启动自动轮询

```bash
# 方式 A：nohup 常驻守护进程
cd ~/codex_projects/project
chmod +x scripts/server_pull_run.sh
mkdir -p ~/codex_pull_logs
nohup bash scripts/server_pull_run.sh > ~/codex_pull_logs/daemon.out 2>&1 &
echo $! > ~/codex_pull_logs/daemon.pid

# 查看是否运行中
ps aux | grep server_pull_run | grep -v grep

# 方式 B：cron 每分钟触发
crontab -e
# 添加：每分钟执行一次，flock 防止重叠
* * * * * flock -n /tmp/codex_pull.lock bash $HOME/codex_projects/project/scripts/server_pull_once.sh
```

### 4.5.1 自动弹出运行窗口

控制服务器检测到新 commit 并准备执行时，默认会尝试打开一个桌面 Terminal 窗口，实时跟随本次 `latest.log` 和 `latest_run_output.log`。这样 `bash run.sh` 或测试失败时，错误会直接留在窗口里，便于在 VNC 桌面上查看。

```bash
# 默认开启
POPUP_TERMINAL_ON_RUN=1

# 如果不希望弹窗，只写日志
POPUP_TERMINAL_ON_RUN=0 nohup bash scripts/server_pull_run.sh > ~/codex_pull_logs/daemon.out 2>&1 &
```

该功能要求服务器当前会话有图形桌面环境（例如 VNC 中的 Ubuntu 桌面）和可用终端程序。没有 `DISPLAY` / `WAYLAND_DISPLAY` 或找不到终端程序时，脚本只输出警告并继续执行，不会影响自动运行。
### 4.5.2 日志时间

控制服务器日志、状态文件、产物摘要和日志文件名默认使用北京时间：

```bash
SERVER_TIMEZONE=Asia/Shanghai
```

如需改成其他时区，可在启动 `server_pull_run.sh` 或 `server_pull_once.sh` 前覆盖 `SERVER_TIMEZONE`，例如 `SERVER_TIMEZONE=UTC`。
### 4.5.3 一键同步并执行最新代码

如果需要在控制服务器上手动同步远端最新代码、强制执行一次、并重启后台 daemon，使用：

```bash
cd ~/codex_projects/project
bash scripts/server_sync_latest.sh
```

该脚本会自动完成：停止旧 daemon、拉取 `origin/main`、快进合并、强制运行一次最新 commit、重新启动 daemon、打印当前状态。它默认只会覆盖仓库管理的自动化脚本本地改动；如果发现业务代码存在本地未提交修改，会停止并报错，避免覆盖业务代码。

可选参数：

```bash
# 不覆盖本地自动化脚本改动
bash scripts/server_sync_latest.sh --no-force-scripts

# 只同步代码，不立即执行
bash scripts/server_sync_latest.sh --no-run-once

# 同步并执行，但不重启后台 daemon
bash scripts/server_sync_latest.sh --no-restart-daemon
```
### 4.6 查看执行结果

```bash
# 一屏查看当前状态、daemon 是否在跑、最近日志和最新产物
cd ~/codex_projects/project
bash scripts/server_status.sh

# 实时跟随当前运行过程（推荐排查失败时使用）
cd ~/codex_projects/project
bash scripts/server_status.sh --follow

# 查看完整诊断日志
tail -n 160 ~/codex_pull_logs/latest.log

# 查看本次 run.sh 的原始输出（固定文件名，不会重新执行 run.sh）
cat ~/codex_pull_logs/latest_run_output.log

# 查看历史运行
ls -lh ~/codex_pull_logs | tail
```

### 4.6.1 查看运行产物

如果项目运行时生成 PPT/PPTX、CSV、图片等非文本文件，业务代码应优先写入环境变量 `RUN_ARTIFACT_DIR` 指向的目录。
控制服务器每次执行新 commit 前会固定设置：

```bash
RUN_ARTIFACT_DIR="$LOG_DIR/artifacts/latest"
```

也就是说，最新一次运行的文件始终在：

```bash
$LOG_DIR/artifacts/latest/
```

为了避免旧文件和新文件混在一起，脚本会在每次运行前把旧的 `latest/` 移动到：

```bash
$LOG_DIR/artifacts/archive/<timestamp>_<commit>/
```

`latest_run_output.log` 除了保留 `run.sh` 的文本输出，还会在末尾追加本次产物清单，包含产物目录、汇总时间、文件修改时间、文件大小和文件名，方便快速查阅。

Python 代码推荐通过 `src.artifacts.get_artifact_dir()` 获取输出目录。本地运行时如果没有设置 `RUN_ARTIFACT_DIR`，默认写入项目下的 `outputs/`，该目录不纳入 Git。

### 4.7 日志回传（可选）

如果希望 Codex 在开发机上也能看到控制服务器的执行结果，可以启用日志回传功能。控制服务器每次执行完成后，自动将日志推送到远端仓库的 `run-logs` 分支。

**方式 A：推送到同一仓库的 run-logs 分支**（简单）

```bash
# 控制服务器启动脚本时设置环境变量
LOG_PUSH_REMOTE=origin nohup bash scripts/server_pull_run.sh > ~/codex_pull_logs/daemon.out 2>&1 &
```

注意：此方式需要代码仓库的 deploy key 具有**写权限**。如果不希望代码仓库 deploy key 有写权限，使用方式 B。

**方式 B：推送到独立日志仓库**（更安全）

```bash
# 1. 创建独立日志仓库（如 project-run-logs），配置单独的 deploy key（写权限）
# 2. 在控制服务器上添加 remote
cd ~/codex_projects/project
git remote add log-repo git@github-log:OWNER/project-run-logs.git

# 3. 启动时指定日志 remote
LOG_PUSH_REMOTE=log-repo nohup bash scripts/server_pull_run.sh > ~/codex_pull_logs/daemon.out 2>&1 &
```

**Codex 查看远端日志：**

```bash
# 拉取 run-logs 分支
git fetch origin run-logs

# 查看服务端真实执行 run.sh 时捕获的最新输出（固定文件名）
git show origin/run-logs:logs/latest_run_output.log
```

日志回传安全性：
- 日志中不包含 `.env`、私钥、token
- 日志仓库/分支与代码分支完全独立，不会污染提交历史
- 推荐使用单独的日志仓库 + 独立 deploy key

------

## 5. 控制服务器尚未配置时的规则

如果控制服务器尚未部署 Git 拉取脚本，Codex 只进行本地验证：

```bash
bash run.sh
python3 -m pytest -q
```

Codex 不应：
1. 尝试手动触发控制服务器。
2. 尝试 ssh 连接任何服务器。
3. 尝试 scp 或 rsync 上传文件。

如果用户要求远程验证但服务器未配置，应提示用户先在控制服务器上执行一次性配置（见 §4.4）。

------

## 6. 禁止操作

Codex 严禁执行或生成以下操作，除非用户明确要求并确认风险：

```bash
sudo ...
rm -rf /
rm -rf ~
rm -rf /*
curl ... | bash
wget ... | bash
chmod -R 777 /
chown -R ...
sshpass ...
```

Codex 也禁止：

1. 手动 scp 文件到服务器。
2. 手动 ssh 登录服务器修改代码。
3. 把 SSH 私钥内容写入项目。
4. 把服务器密码写入项目。
5. 把 API key、token、cookie 写入代码或日志。
6. 在服务器上使用 root 用户运行 Codex 生成的代码。
7. 修改系统目录，例如 `/etc`、`/usr`、`/bin`、`/root`。
8. 清理不属于本项目的远程目录。
9. 在控制服务器上手动修改代码（应通过 git push 触发自动拉取）。

------

## 7. 允许操作

Codex 可以执行以下操作：

### 7.1 本地允许操作

```bash
bash run.sh
python3 -m pytest -q
make run
make test
git add -A && git commit -m "..." && git push
```

### 7.2 控制服务器操作（由用户手动执行，非 Codex）

```bash
# 启动守护进程
nohup bash scripts/server_pull_run.sh > ~/codex_pull_logs/daemon.out 2>&1 &

# 查看日志
tail -n 160 ~/codex_pull_logs/latest.log
```

------

## 8. 代码修改规则

Codex 修改代码时，应遵守以下规则：

1. `main.py` 只作为项目主入口，并且必须直接指向当前最新核心业务入口。
2. 当前最新核心业务入口、允许保留的 `src/` 文件、允许保留的业务/基础设施测试，必须记录在 `docs/CURRENT_BUSINESS.json`。
3. 每次生成新的核心业务代码时，必须在同一次修改中完成：更新 `docs/CURRENT_BUSINESS.json`、更新 `main.py`、删除旧业务代码文件、删除或替换旧业务测试。
4. `src/` 只保留当前核心业务必需文件和明确登记的通用基础设施文件；历史业务代码不得留在 `src/` 中。
5. `tests/` 只保留当前业务测试和基础设施测试；历史业务测试不得继续保留。
6. 业务逻辑优先放到 `src/` 目录。
7. 测试代码放到 `tests/` 目录。
8. 不要把所有逻辑堆在一个文件里。
9. 新增依赖时，必须更新 `requirements.txt`。
10. 不要在代码中写死本机绝对路径。
11. 不要在代码中写死服务器路径。
12. 不要在代码中写死密码、token、私钥或 API key。
13. 修改功能后，尽量补充或更新测试。
14. 如果涉及随机过程，应尽量设置随机种子，保证结果可复现。

当前业务清单由 `tests/test_current_business_manifest.py` 强制校验。如果 `main.py` 未指向清单中的入口，或 `src/` / `tests/` 中残留未登记的历史业务文件，测试必须失败。

------

## 9. 依赖管理规则

如果新增 Python 依赖，必须写入：

```text
requirements.txt
```

不要直接要求用户在全局环境中安装依赖。
不要使用：

```bash
sudo pip install ...
```

推荐使用：

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

------

## 10. 控制服务器执行失败时的处理流程

如果控制服务器最新日志显示执行失败，Codex 应按以下顺序处理：

1. 确认问题是在本地还是远程：先在本地跑 `bash run.sh` 和 `python3 -m pytest -q`。

2. 如果本地通过但服务器失败，可能原因：
   - 服务器环境缺少依赖 → 检查 `requirements.txt`
   - `run.sh` 不可执行 → 确认文件有执行权限并已提交
   - 快进合并冲突 → 服务器上手动 `git reset --hard origin/main`
   - 服务器 Python 版本不兼容

3. 如果是项目代码失败，根据 traceback 修改代码。

4. 修改后重新推送：本地验证通过 → `git push`，服务器会在下一轮轮询自动重试。

不要登录服务器手动改代码。

------

## 11. 长任务规则

如果任务是长时间训练、大规模计算、爬取或编译，控制服务器上的轮询间隔 `INTERVAL_SECONDS` 应适当调大，防止上次任务未完成时新一轮又启动。

守护进程版使用 `flock` 类似的逻辑（脚本内 `INTERVAL_SECONDS` 控制间隔），cron 版使用 `flock -n` 防重叠。

------

## 12. Codex 每次任务的标准流程

```text
1. 理解用户需求。
2. 查看相关文件。
3. 修改代码。
4. 如有必要，更新 requirements.txt。
5. 如有必要，更新 tests/。
6. 本地运行 bash run.sh。
7. 本地运行 python3 -m pytest -q。
8. 测试通过后 git add -A && git commit -m "..." && git push。
9. 告知用户已推送，控制服务器将在 30 秒内自动拉取执行。
10. 最后总结修改了哪些文件、运行了哪些命令、结果是否通过。
```

------

## 13. 成功标准

一次修改任务完成后，至少满足以下条件：

```text
1. 代码已修改完成。
2. bash run.sh 可以运行。
3. python3 -m pytest -q 可以通过。
4. git push 已执行。
5. 没有提交私钥或密码。
6. 没有手动 scp。
7. 没有手动 ssh 登录服务器改代码。
```

------

## 14. 最重要的规则

Codex 必须记住：

```text
本地运行：bash run.sh
本地测试：python3 -m pytest -q
推送到远端：git add -A && git commit -m "..." && git push
```

Codex 不需要关心服务器端如何执行 — 那由控制服务器上的轮询脚本自动完成。

不要猜入口。
不要手动上传。
不要手动登录服务器改代码。
不要泄露密码、私钥、API key。
失败后本地修复，重新 push 即可。
