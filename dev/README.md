# dev 自动化编排

该目录用于承载 APP 特定场景还原的自动化编排脚本、配置文件、任务模板、运行态目录和本地 Web 控制台。

## 目录结构

- `config/pipeline.config.json`：主配置文件，维护 APP 类型与 Git 分支映射、Agent 定义、构建命令、轮询策略、提交路径等。
- `config/task_template.txt`：下发给 Agent 的任务模板，脚本会按场景动态实例化。
- `frontend/`：本地 Web 控制台静态资源目录，页面用于显示当前任务信息、进度、巡检状态和日志。
- `spec/`：场景 spec 默认输出目录，任务 Prompt 快照也会写到这里。
- `scripts/run_pipeline.py`：主入口。读取场景 JSON，准备分支，下发 Agent，并自动后台启动 Web 控制台。
- `scripts/web_console.py`：本地 Web 服务，提供当前任务状态、日志和终止任务接口。
- `scripts/pipeline_monitor_lib.py`：巡检公共逻辑，供 `run_pipeline.py`、`web_console.py` 和 `monitor_results.py` 复用。
- `scripts/monitor_results.py`：兼容保留的独立巡检脚本，可单独执行一次或循环巡检。
- `mock-data/`：约定的 mock 数据目录。Agent 开发任务需要将模拟数据拆成独立 JSON 文件放到这里。
- `output/`：结果 JSON 输出目录，运行时自动创建。
- `logs/`：运行日志目录，运行时自动创建。
- `state/`：运行状态目录，用于中断恢复、Web 页面展示和后续巡检，运行时自动创建。

## 当前流程

1. 执行 `python dev/scripts/run_pipeline.py --input <scenario.json>`
   启动前会自动清空并重建 `dev/logs`、`dev/mock-data`、`dev/spec`、`dev/state`。
2. 脚本读取场景 JSON 中的 `app` 字段，映射到配置中的基础分支。
3. 脚本同步基础分支，并创建或切换到场景分支，例如 `prod-travel-app-scenario-001`。
4. 脚本基于模板实例化任务，并按配置启动 Agent，例如 `codex.cmd exec --yolo -`。
5. `run_pipeline.py` 自动后台启动本地 Web 控制台。
6. Web 控制台进程内自动启动巡检循环，持续检查结果 JSON、构建状态和推送状态。
7. Agent 完成开发和构建后，将结果 JSON 写入 `dev/output/`。
8. 巡检逻辑识别成功结果后，自动执行 `git add`、`git commit`、`git push`。

## Web 控制台

执行 `run_pipeline.py` 后会自动启动本地 Web 服务，并在日志中输出访问地址，例如：

```text
http://127.0.0.1:8765
```

页面默认聚焦当前一次运行，展示以下信息：

- 当前场景、APP 类型、分支、状态、开始时间、更新时间
- 当前阶段进度
- 巡检状态、最近巡检时间、巡检轮次、说明信息
- Pipeline 日志和 Agent 日志尾部内容
- “终止任务”按钮

点击“终止任务”后会：

- 尝试终止当前 Agent 进程
- 将 runtime 状态标记为 `cancelled`
- 写入 `cancelled_at` 和 `cancel_reason`
- 停止该任务后续巡检

如不希望自动启动 Web 控制台，可使用：

```powershell
python dev/scripts/run_pipeline.py --input scenario1.json --no-web
```

## 中断恢复

- `run_pipeline.py` 每次运行都会在 `dev/state/` 下写入 `*.runtime.json`
- `run_pipeline.py` 启动前会先清理 `dev/logs`、`dev/mock-data`、`dev/spec`、`dev/state`，因此 `--resume` 只适用于同一次运行生命周期内的状态复用，不适用于重新执行脚本后的历史状态恢复
- 如果 Agent 进程仍在运行，再次执行会提示并复用已有状态
- 如果场景已完成或已推送，会直接提示结果并退出
- 如果进程已退出但结果 JSON 未产出，状态会被标记为异常结束，可使用 `--force-retry` 重新下发

## 配置说明

主配置文件使用 JSON，默认只依赖 Python 标准库。

重点配置项：

- `git.app_types`：APP 类型与基础分支映射
- `git.scenario_branch_format`：场景分支命名模板，支持 `{app_segment}`、`{scenario_id}`、`{timestamp}`
- `agent.active`：当前启用的 Agent
- `agent.definitions`：各 Agent 的启动命令模板
- `paths`：输入、日志、状态、输出、mock 数据目录
- `scheduler`：巡检间隔、最大轮次、成功状态值、提交信息模板
- `commit.include_paths`：成功后纳入提交的路径白名单

## 常用命令

```powershell
python dev/scripts/run_pipeline.py --input scenario1.json
python dev/scripts/run_pipeline.py --input scenario1.json --wait
python dev/scripts/run_pipeline.py --input scenario1.json --no-web
python dev/scripts/monitor_results.py --once
python dev/scripts/monitor_results.py --loop
```

## runtime 状态文件

`dev/state/*.runtime.json` 会记录当前任务的运行态。常见字段包括：

- `status`：任务总状态，例如 `initialized`、`git_preparing`、`git_ready`、`agent_running`、`inspection_running`、`pushed`、`build_failed`、`agent_exited_without_result`、`cancelled`
- `agent`：Agent 类型、命令、PID、开始时间、日志路径
- `inspection`：巡检状态、最近检查时间、轮次、说明
- `web`：Web 服务地址、端口、启动时间、进程 PID
- `cancelled_at`、`cancel_reason`：由 Web 页面终止时写入

## 结果 JSON 约定

建议 Agent 成功构建后输出如下字段，结果文件默认落到运行时创建的 `dev/output/`：

```json
{
  "buildStatus": "success",
  "artifactPath": "entry/build/default/outputs/default/entry-default-signed.hap",
  "artifactSizeBytes": 1234567,
  "buildTime": "2026-04-17 10:30:00",
  "scenarioBranch": "prod-travel-app-scenario-001",
  "appType": "travel"
}
```

巡检逻辑会兼容 `buildStatus`、`build_status`、`status` 等字段名，并将 `success/succeeded/ok/passed/true` 视为成功。
