# dev 自动化编排

该目录用于承载 APP 特定场景还原的自动化编排脚本、配置文件、任务模板和运行态目录。

## 目录结构

- `config/pipeline.config.json`：主配置文件，维护 APP 类型与 Git 分支映射、Agent 定义、构建命令、轮询策略、提交路径等。
- `config/task_template.txt`：下发给 Agent 的任务模板，脚本会按场景动态实例化。
- `scripts/run_pipeline.py`：执行 step1-step3。读取场景 JSON，选择 APP 类型分支，创建场景分支，并下发 Agent 任务。
- `scripts/monitor_results.py`：执行 step4。轮询结果 JSON，判断构建是否成功，然后自动提交并推送分支。
- `mock-data/`：约定的 mock 数据目录。Agent 开发任务需要将模拟数据拆成独立 JSON 文件放到这里。
- `output/`：结果 JSON 输出目录，运行时自动创建。
- `logs/`：运行日志目录，运行时自动创建。
- `state/`：运行状态目录，用于中断恢复和后续巡检，运行时自动创建。

## 典型流程

1. 执行 `python dev/scripts/run_pipeline.py --input scenario1.json`
2. 脚本读取 `scenario1.json` 中的 `app` 字段，映射到配置中的基础分支
3. 脚本拉取远端基础分支并创建场景分支，例如 `prod-travel-app-scenario-001`
4. 脚本基于模板实例化任务，并按配置启动 Agent，例如 `codex exec --yolo "..."`
5. Agent 完成开发和构建后，将结果 JSON 写入运行时自动创建的 `dev/output/`
6. 执行 `python dev/scripts/monitor_results.py --loop`
7. 巡检脚本识别成功结果后自动 `git add`、`git commit`、`git push`

## 中断恢复

- `run_pipeline.py` 每次运行都会在自动创建的 `dev/state/` 下写入 `*.runtime.json`
- 如果 Agent 进程仍在运行，再次执行会直接提示并复用已有状态
- 如果进程已退出但结果 JSON 未产出，状态会被标记为异常结束，可使用 `--force-retry` 重新下发

## 配置说明

主配置文件使用 JSON，默认只依赖 Python 标准库。

重点配置项：

- `git.app_types`：APP 类型与基础分支映射
- `git.scenario_branch_format`：场景分支命名模板
- `agent.active`：当前启用的 Agent
- `agent.definitions`：各 Agent 的启动命令模板
- `paths`：输入、日志、状态、输出、mock 数据目录
- `commit.include_paths`：成功后纳入提交的路径白名单

## 常用命令

```powershell
python dev/scripts/run_pipeline.py --input scenario1.json
python dev/scripts/run_pipeline.py --input scenario1.json --wait
python dev/scripts/monitor_results.py --once
python dev/scripts/monitor_results.py --loop
```

## 结果 JSON 约定

建议 Agent 成功构建后输出如下字段，结果文件默认落到运行时创建的 `dev/output/`：

```json
{
  "buildStatus": "success",
  "artifactPath": "entry/build/default/outputs/default/entry-default-signed.hap",
  "artifactSizeBytes": 1234567,
  "buildTime": "2026-04-17T10:30:00+08:00",
  "scenarioBranch": "prod-travel-app-scenario-001",
  "appType": "travel"
}
```

巡检脚本会兼容 `buildStatus`、`build_status`、`status` 等字段名，并将 `success/succeeded/ok/passed/true` 视为成功。
