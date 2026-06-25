# 新机器环境配置简版

这份说明来自 `对话记录.docx` 里的实际配置过程。目标是把一台新的 Linux 控制机器配置成：

```text
开发机/Codex 修改并 push -> GitHub -> 控制机器自动 fetch/pull -> bash run.sh -> python3 -m pytest -q
```

## 默认仓库和 OWNER/REPO 怎么理解

本项目作者自己运行时，默认仓库就是：

```text
1563669740/Code-Transfer-Station
```

也就是说，作者部署默认库时可以直接执行：

```bash
bash /tmp/bootstrap_new_machine.sh
```

如果显式执行下面这条命令：

```bash
bash /tmp/bootstrap_new_machine.sh --repo 1563669740/Code-Transfer-Station
```

含义是：控制机器会同步 GitHub 上的 `1563669740/Code-Transfer-Station` 这个原始默认仓库，不会自动同步别人的 fork 或团队仓库。

别人拿到这份代码后，应先 fork 或导入到自己的仓库，然后把所有示例里的 `OWNER/REPO` 改成自己的仓库，例如：

```bash
bash /tmp/bootstrap_new_machine.sh --repo YOUR_OWNER/YOUR_REPO
```

常见配置位置：

- 本地开发机 push 地址默认使用 HTTPS：`git remote set-url origin https://github.com/YOUR_OWNER/YOUR_REPO.git`
- 服务器 bootstrap 一次性参数：`--repo YOUR_OWNER/YOUR_REPO`
- 机器本地默认值：复制 `.env.example` 为 `.env` 后修改 `REPO_SLUG=YOUR_OWNER/YOUR_REPO`

## 本地新电脑先配置什么

本地新电脑是开发机/Codex 所在机器，负责改代码、静态检查、提交并 push。Codex 不允许在本地运行项目业务代码、run.sh 或 pytest；真正的运行和测试交给控制服务器完成。它使用开发者自己的 GitHub 账号，不使用服务器 Deploy Key。

1. 安装 Git。Windows 推荐 Git for Windows；Git Bash 只用于普通 Git/脚本操作，Codex 本地不要执行 `bash run.sh`。
2. 配置提交身份：

   ```bash
   git config --global user.name "你的名字或GitHub用户名"
   git config --global user.email "你的邮箱@example.com"
   ```

3. 关联 GitHub：本项目本地开发默认使用 HTTPS remote。首次 `git push` 时使用 Git Credential Manager / 浏览器登录完成 GitHub 授权；不要把 token 拼进 remote URL。SSH 只是你自己决定改用 `git@github.com:OWNER/REPO.git` 时的可选方案。
4. 克隆项目并安装依赖：

   ```bash
   git clone https://github.com/1563669740/Code-Transfer-Station.git
   cd Code-Transfer-Station
   python -m venv .venv
   # Windows PowerShell
   .\.venv\Scripts\activate
   # Linux / macOS / Git Bash
   source .venv/bin/activate
   python -m pip install -r requirements.txt
   ```

5. 本地检查：

   Codex 本地只做不执行业务代码的检查，例如 `git status`、`git diff`、`rg` 和清单一致性检查。不要在本地执行 `bash run.sh`、`python3 -m pytest -q`、`pytest`、`make run` 或 `make test`。

## Codex 生成代码后的固定后续流程

让 Codex 生成或修改代码时，应明确要求它先阅读 `docs/RUNBOOK.md`，并在生成后继续执行 RUNBOOK 的后续工作：

```text
请先阅读 docs/RUNBOOK.md，按其中规则修改代码。
生成或修改代码后，禁止在本地执行 bash run.sh、python3 -m pytest -q、pytest、make run 或 make test。
如果涉及新的核心业务入口，请同步更新 docs/CURRENT_BUSINESS.json、main.py、src/ 和 tests/，删除旧业务残留。
只做不执行业务代码的静态检查和清单检查，然后 git add -A、git commit、git push；由控制服务器自动拉取后执行 run.sh 和 pytest。
```

## 最少需要什么

新机器需要（Ubuntu 类系统默认通常都有 `python3`）：

- Linux / Ubuntu 类系统
- `python3`（Ubuntu 默认预装，用于下载脚本和后续运行项目）
- `bash`、`apt-get`（系统自带）

**不需要**提前装 `git`、`pip`、`venv`、`curl` — bootstrap 脚本会自动检测并通过 `apt-get` 安装缺失的包。

额外需要：
- 一个只读 GitHub Deploy Key（脚本生成公钥后，你去 GitHub 网页添加）

## 给别人使用时的账号原则

这套工具的代码默认仓库是 `1563669740/Code-Transfer-Station`。作者自己使用时可以保持默认；别人部署时应使用自己的 GitHub 账号、自己的仓库副本，以及新机器上重新生成的 Deploy Key。

推荐流程：

1. 对方 fork 本仓库，或把代码导入到自己的 `OWNER/REPO` 仓库。
2. 新机器运行 bootstrap 时显式传入自己的仓库：`--repo YOUR_OWNER/YOUR_REPO`。
3. bootstrap 会在新机器上生成一把新的 SSH deploy key。
4. 对方把脚本打印的 `.pub` 公钥添加到自己仓库的 Deploy keys。
5. 私钥只留在那台机器的 `~/.ssh/` 下，不进入源码、不复制给别人、不写入文档或日志。

默认只需要只读 Deploy Key。如果要启用日志回传到代码仓库，才需要给对应 key 写权限，或者更推荐使用独立日志仓库和独立写权限 key。更多原则见 `docs/ACCOUNT_CONFIGURATION.md`。

## 推荐：用脚本自动配置

本项目已提供：

```bash
scripts/bootstrap_new_machine.sh
```

它会自动完成：

1. 检查并安装缺失的 Git / SSH / Python / pip / venv
2. 生成 SSH Deploy Key
3. 打印 GitHub Deploy Key 页面和公钥
4. 等你在 GitHub 网页添加公钥后继续
5. 配置 SSH Host
6. 克隆或更新仓库
7. 创建 `.venv` 并安装 `requirements.txt`
8. 在控制服务器上执行 `bash run.sh`
9. 在控制服务器上执行 `python3 -m pytest -q`
10. 启动 `scripts/server_pull_run.sh` 后台轮询

## 第一次在新机器上怎么跑

因为新机器还没有仓库，第一次需要先把脚本放到服务器上。新机器可能连 `curl` 都没有，但 `python3` 几乎必定有，用它下载最可靠：

```bash
# 用 python3 下载脚本（不依赖 curl/wget）。
# 如果卡住不动，大概率是网络不通（raw.githubusercontent.com 被墙或 DNS 污染）。
# 先测试连通性，不行就换备用方式。
python3 -c "
import urllib.request, ssl, sys

url = 'https://raw.githubusercontent.com/1563669740/Code-Transfer-Station/main/scripts/bootstrap_new_machine.sh'
print(f'Downloading {url} ...')

try:
    # 设置超时，避免无限等待
    ctx = ssl.create_default_context()
    req = urllib.request.Request(url, headers={'User-Agent': 'python-urllib'})
    resp = urllib.request.urlopen(req, timeout=30, context=ctx)
    data = resp.read()
    with open('/tmp/bootstrap_new_machine.sh', 'wb') as f:
        f.write(data)
    print(f'Done. Wrote {len(data)} bytes.')
except Exception as e:
    print(f'Failed: {e}', file=sys.stderr)
    sys.exit(1)
"
```

如果上面卡住或报错，说明这台机器访问不了 raw.githubusercontent.com。换以下方式：

```bash
# 方式 A: 试试 jsDelivr CDN（国内通常更快）
python3 -c "
import urllib.request, ssl, sys
url = 'https://cdn.jsdelivr.net/gh/1563669740/Code-Transfer-Station@main/scripts/bootstrap_new_machine.sh'
print(f'Trying CDN: {url}')
try:
    ctx = ssl.create_default_context()
    req = urllib.request.Request(url, headers={'User-Agent': 'python-urllib'})
    resp = urllib.request.urlopen(req, timeout=30, context=ctx)
    data = resp.read()
    with open('/tmp/bootstrap_new_machine.sh', 'wb') as f:
        f.write(data)
    print(f'Done. Wrote {len(data)} bytes.')
except Exception as e:
    print(f'CDN also failed: {e}', file=sys.stderr)
    sys.exit(1)
"

# 方式 B: 用 curl（如果碰巧有）
curl -fsSL --connect-timeout 10 \
  https://raw.githubusercontent.com/1563669740/Code-Transfer-Station/main/scripts/bootstrap_new_machine.sh \
  -o /tmp/bootstrap_new_machine.sh

# 方式 C: 用 wget（如果碰巧有）
wget -q --timeout=10 \
  https://raw.githubusercontent.com/1563669740/Code-Transfer-Station/main/scripts/bootstrap_new_machine.sh \
  -O /tmp/bootstrap_new_machine.sh
```

如果以上全部不行，就手动把 `scripts/bootstrap_new_machine.sh` 的内容复制粘贴到新机器的 `/tmp/bootstrap_new_machine.sh`。

下载成功后检查并执行：

如果 `python3` 也没有（极少见），任选以下方式之一：

```bash
# 方式 A: 用 curl（如果碰巧有）
curl -fsSL \
  https://raw.githubusercontent.com/1563669740/Code-Transfer-Station/main/scripts/bootstrap_new_machine.sh \
  -o /tmp/bootstrap_new_machine.sh

# 方式 B: 用 wget（如果碰巧有）
wget -q \
  https://raw.githubusercontent.com/1563669740/Code-Transfer-Station/main/scripts/bootstrap_new_machine.sh \
  -O /tmp/bootstrap_new_machine.sh
```

如果三种方式都不行，就把 `scripts/bootstrap_new_machine.sh` 的内容手动复制粘贴到新机器的 `/tmp/bootstrap_new_machine.sh`。

无论哪种方式，下载后都一样执行。作者默认仓库可以不传 `--repo`：

```bash
bash /tmp/bootstrap_new_machine.sh
```

如果要明确指定默认仓库，也可以写成：

```bash
bash /tmp/bootstrap_new_machine.sh --repo 1563669740/Code-Transfer-Station
```

别人部署自己的 fork 或团队仓库时，必须改成自己的 `OWNER/REPO`：

```bash
bash /tmp/bootstrap_new_machine.sh --repo YOUR_OWNER/YOUR_REPO
```

脚本运行到 Deploy Key 步骤时，会打印类似：

```text
Public key:
ssh-ed25519 AAAA... codex-pull-deploy
```

打开：

```text
https://github.com/1563669740/Code-Transfer-Station/settings/keys
```

添加 Deploy Key：

- Title: `server-deploy`
- Key: 粘贴脚本打印的 `ssh-ed25519 ...`
- 默认**不要勾选 `Allow write access`**。只有在你明确设置 `LOG_PUSH_REMOTE=origin`、希望服务器把日志推回同一个仓库时，才需要写权限；更安全的做法是使用独立日志仓库。

保存后回到终端按 Enter，脚本会继续完成克隆、验证和后台轮询。

## 常用参数

```bash
# 作者默认仓库
bash /tmp/bootstrap_new_machine.sh

# 指定自己的仓库
bash /tmp/bootstrap_new_machine.sh --repo YOUR_OWNER/YOUR_REPO

# 只验证，不启动后台轮询
bash /tmp/bootstrap_new_machine.sh --repo YOUR_OWNER/YOUR_REPO --no-daemon

# 指定分支和项目目录
bash /tmp/bootstrap_new_machine.sh \
  --repo YOUR_OWNER/YOUR_REPO \
  --branch main \
  --project-dir "$HOME/codex_projects/project"
```


## 依赖安装卡住怎么办

服务器安装 Python 依赖时会调用 `scripts/install_python_deps.sh`，默认不会无限等待：

- 单个镜像源最多等待 300 秒
- pip 单次网络请求最多等待 30 秒
- 默认依次尝试清华源、阿里云源、官方 PyPI

如果你的服务器访问某个源更快，可以在执行 bootstrap 前指定：

```bash
PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple \
PIP_INSTALL_TIMEOUT=180 \
PIP_NETWORK_TIMEOUT=20 \
bash /tmp/bootstrap_new_machine.sh --repo YOUR_OWNER/YOUR_REPO
```

已经配置好的控制机器也可以用同样环境变量启动轮询脚本：

```bash
PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple \
nohup bash scripts/server_pull_run.sh > ~/codex_pull_logs/daemon.out 2>&1 &
```

## 配置完成后怎么确认

```bash
ps aux | grep server_pull_run | grep -v grep
tail -n 160 ~/codex_pull_logs/latest.log
```

以后只需要在开发机/Codex 修改、做静态检查、提交并推送：

```bash
git status
git diff
git add -A && git commit -m "描述修改内容" && git push
```

控制机器会自动拉取新 commit，并在服务器上执行 `bash run.sh` 和 `python3 -m pytest -q`，不需要手动 SSH 登录服务器改代码。
## 服务器没有自动更新怎么办

如果逻辑代码已经 push，但服务器没有在预期时间内更新，先在控制服务器上查看守护进程和日志：

```bash
ps aux | grep server_pull_run | grep -v grep
tail -n 160 ~/codex_pull_logs/latest.log
```

本项目提供了手动同步脚本。该脚本只能由用户在控制服务器上执行，Codex 不要本地执行，也不要通过 SSH 代替执行：

```bash
cd ~/codex_projects/project
bash scripts/server_sync_latest.sh
```

常用参数：

```bash
# 不覆盖服务器本地自动化脚本改动
bash scripts/server_sync_latest.sh --no-force-scripts

# 只同步最新代码，不立即运行 run.sh/pytest
bash scripts/server_sync_latest.sh --no-run-once

# 同步并运行一次，但不重启后台 daemon
bash scripts/server_sync_latest.sh --no-restart-daemon
```

## 代码需要项目目录外的数据怎么办

如果要执行的业务代码依赖外部数据，但数据不在这个项目文件夹里，按下面原则处理：

1. 不要把本机绝对路径写入代码，例如 `C:\Users\...` 或 `/Users/...`。
2. 不要把大数据、隐私数据、密钥文件提交到仓库。
3. 在控制服务器上准备固定数据目录，例如 `/data/code-transfer-station/input`。
4. 用环境变量告诉程序数据位置，例如 `DATA_DIR=/data/code-transfer-station/input`；只在 `.env.example` 写变量名和示例，不写真实敏感路径。
5. 业务代码缺少数据时应明确报错，提示需要设置哪个环境变量、期望什么目录结构。
6. 运行产物继续写入 `RUN_ARTIFACT_DIR`，由服务器脚本统一归档到 `~/codex_pull_logs/artifacts/latest/`。
