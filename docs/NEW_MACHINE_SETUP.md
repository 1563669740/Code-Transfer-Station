# 新机器环境配置简版

这份说明来自 `对话记录.docx` 里的实际配置过程。目标是把一台新的 Linux 控制机器配置成：

```text
开发机 git push -> GitHub -> 控制机器自动 fetch/pull -> bash run.sh -> python3 -m pytest -q
```

## 最少需要什么

新机器需要（Ubuntu 类系统默认通常都有 `python3`）：

- Linux / Ubuntu 类系统
- `python3`（Ubuntu 默认预装，用于下载脚本和后续运行项目）
- `bash`、`apt-get`（系统自带）

**不需要**提前装 `git`、`pip`、`venv`、`curl` — bootstrap 脚本会自动检测并通过 `apt-get` 安装缺失的包。

额外需要：
- 一个只读 GitHub Deploy Key（脚本生成公钥后，你去 GitHub 网页添加）

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
8. 执行 `bash run.sh`
9. 执行 `python3 -m pytest -q`
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

无论哪种方式，下载后都一样执行：

```bash
bash /tmp/bootstrap_new_machine.sh --repo 1563669740/Code-Transfer-Station
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
- **勾选 `Allow write access`**（日志回传需要写权限，否则服务器执行日志无法推回仓库）

保存后回到终端按 Enter，脚本会继续完成克隆、验证和后台轮询。

## 常用参数

```bash
# 指定仓库
bash /tmp/bootstrap_new_machine.sh --repo 1563669740/Code-Transfer-Station

# 只验证，不启动后台轮询
bash /tmp/bootstrap_new_machine.sh --repo 1563669740/Code-Transfer-Station --no-daemon

# 指定分支和项目目录
bash /tmp/bootstrap_new_machine.sh \
  --repo 1563669740/Code-Transfer-Station \
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
bash /tmp/bootstrap_new_machine.sh --repo 1563669740/Code-Transfer-Station
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

以后只需要在开发机提交并推送：

```bash
bash run.sh
python3 -m pytest -q
git add -A && git commit -m "描述修改内容" && git push
```

控制机器会自动拉取新 commit 并执行，不需要手动 SSH 登录服务器改代码。
