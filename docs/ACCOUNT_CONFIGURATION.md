# 账号与仓库配置说明

本项目作者自己使用时，默认仓库是 `1563669740/Code-Transfer-Station`；项目也可以交给其他人部署使用。源码不应该绑定任何人的 GitHub 登录状态、服务器密码、SSH 私钥、API token 或本机绝对路径。

## 推荐模型

开发机使用开发者自己的 GitHub 账号通过 HTTPS remote push 代码。控制服务器不登录 GitHub 账号，只使用仓库级别的 SSH Deploy Key 拉取代码。

```text
开发者本机账号 -> git push -> GitHub 仓库
控制服务器 deploy key -> git fetch/pull -> bash run.sh -> pytest
```

## 给别人使用时

1. 作者自己可保持默认 `1563669740/Code-Transfer-Station`；对方 fork 本仓库，或导入到自己的 `OWNER/REPO` 仓库。
2. 新机器运行 bootstrap 时显式指定仓库：

   ```bash
   bash /tmp/bootstrap_new_machine.sh --repo YOUR_OWNER/YOUR_REPO
   ```

3. 脚本会在新机器生成新的 SSH key，并打印 `.pub` 公钥。
4. 对方把公钥添加到自己仓库的 `Settings -> Deploy keys`。
5. 私钥只保存在那台机器的 `~/.ssh/` 下，不复制、不提交、不写入日志。

## 配置分层

可提交到仓库：

- `scripts/bootstrap_new_machine.sh`
- `docs/*.md`
- `.env.example`
- 不含真实密钥的示例配置

不提交到仓库：

- `.env`
- `*.pem`
- `*.key`
- GitHub token
- SSH 私钥
- 服务器密码
- cookie 或其他账号凭据

## 日志回传权限

默认 Deploy Key 应保持只读，不勾选 `Allow write access`。

只有在明确设置 `LOG_PUSH_REMOTE=origin`，并希望控制服务器把运行日志推回同一个代码仓库时，才需要给该 key 写权限。更安全的做法是创建独立日志仓库，并给日志仓库配置单独的写权限 Deploy Key。

## 是否需要源码配置模块

如果未来业务代码需要读取账号无关的运行配置，可以新增类似 `src/config.py` 的模块，只负责读取环境变量并校验缺失项。

不要在 Python 模块、shell 脚本或文档中写入真实账号凭据。部署相关配置优先通过环境变量、命令行参数、本地 HTTPS remote 和服务器本地 SSH 配置传入。