.PHONY: run test pull-daemon pull-once

run:
	bash run.sh

test:
	python3 -m pytest -q

# 控制服务器 — 启动常驻轮询守护进程
pull-daemon:
	bash scripts/server_pull_run.sh

# 控制服务器 — 单次轮询（配合 cron 使用）
pull-once:
	bash scripts/server_pull_once.sh