# dev 自动化编排

`dev/` 目录保存自动化脚本、配置、任务模板和 Web 控制台前端。运行态数据不再落在 `dev/`，而是写入每个 `scenarios/scenarioxxx/` 目录。

## 目录

- `config/pipeline.config.json`：主配置，声明 `base_app_root`、`scenarios_root`、`build_root`、Git 分支映射、Agent 和巡检策略
- `config/task_template.txt`：下发给 Agent 的任务模板
- `scripts/run_pipeline.py`：主入口，切换匹配分支、创建或复用 `scenarios/scenarioxxx`
- `scripts/pipeline_monitor_lib.py`：巡检、自动提交、自动推送公共逻辑
- `scripts/monitor_results.py`：独立巡检入口
- `scripts/web_console.py`：仓库级 Web 控制台，支持切换查看 `baseApp` 与多个 scenario
- `frontend/`：Web 控制台静态资源

## 流程

1. 执行 `python dev/scripts/run_pipeline.py --input <scenario.json>`
2. 根据 `scenario.json` 的 `app` 字段匹配基线分支并执行 `git checkout` / `git pull`
3. 创建或复用 `scenarios/scenarioxxx/`
4. 在该目录下准备运行态子目录：
   - `spec/`
   - `mock-data/`
   - `output/`
   - `logs/`
   - `state/`
5. 生成任务 Prompt，启动 Agent
6. 巡检脚本检测 `output/result.json`
7. 成功后按当前场景目录动态 `git add` / `git commit` / `git push` 到当前匹配分支

## Web 控制台

默认访问地址类似：

```text
http://127.0.0.1:8765
```

控制台特性：

- 列出 `baseApp` 与所有 `scenarios/scenarioxxx`
- 切换查看不同 pipeline 的状态、日志和产物
- 对当前选中的 scenario 执行终止
- 下载当前选中的 `.hap` 产物

## 常用命令

```powershell
python dev/scripts/run_pipeline.py --input scenario1.json
python dev/scripts/run_pipeline.py --input scenario1.json --wait
python dev/scripts/run_pipeline.py --input scenario1.json --no-web
python dev/scripts/monitor_results.py --once
python dev/scripts/monitor_results.py --loop
```

## 状态与结果

每个场景目录会保存：

- `state/runtime.json`：运行态
- `output/result.json`：结果 JSON
- `logs/*.log`：流水线与 Agent 日志

建议结果 JSON 至少包含：

```json
{
  "buildStatus": "success",
  "artifactPath": "tmp/scenarios-scenario001/entry/build/default/outputs/default/example.hap",
  "artifactSizeBytes": 1234567,
  "buildTime": "2026-04-22 03:30:00",
  "scenarioBranch": "prod-travel-app",
  "appType": "travel"
}
```
