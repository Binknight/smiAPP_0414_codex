# SimApp 仿真 APP 自动化生成系统 — 架构与流程说明

> **版本**: 1.0 | **日期**: 2026-05-05 | **目标平台**: HarmonyOS ArkUI / ArkTS

---

## 目录

1. [系统概述](#1-系统概述)
2. [架构总览](#2-架构总览)
3. [核心流水线流程](#3-核心流水线流程)
4. [Spec 自动化提取](#4-spec-自动化提取)
5. [Skill 调用机制](#5-skill-调用机制)
6. [Agent 适配与可扩展性](#6-agent-适配与可扩展性)
7. [APP 开发流程](#7-app-开发流程)
8. [自验证闭环](#8-自验证闭环)
9. [配置与扩展点](#9-配置与扩展点)
10. [附录](#10-附录)

---

## 1. 系统概述

SimApp 仿真 APP 自动化生成系统是一个 **AI 驱动的端到端流水线**，能够从一个场景描述 JSON 文件出发，自动完成：

1. **Spec 生成** — 基于 Skill 规则从 JSON 中提取场景证据，产出结构化的增量开发 Spec
2. **Agent 开发** — 由 AI Agent（Codex CLI / OpenCode CLI）根据 Spec 在沙箱工作区中实施代码开发
3. **构建验证** — 通过 HarmonyOS hvigor 工具链编译出 HAP 产物
4. **结果交付** — 构建成功自动 Git 提交，Web Console 实时监控全流程

核心设计原则：**输入一个 JSON，输出一个可运行的 HarmonyOS APP 增量补丁**。

### 1.1 技术栈

| 层 | 技术 |
|---|---|
| 目标平台 | HarmonyOS 6.0.2 (API 22) · ArkUI / ArkTS |
| 构建系统 | hvigor · DevEco Studio SDK · PowerShell |
| AI Agent | Codex CLI · OpenCode CLI（可替换） |
| 编排脚本 | Python 3 · subprocess |
| 监控前端 | Vanilla JS · HTTP Server (Python) |

---

## 2. 架构总览

```
┌──────────────┐    ┌─────────────────┐    ┌──────────────────────┐
│ scenario.json│───▶│ run_pipeline.py │───▶│ Skill: spec-gen      │
│ (app+question)│   │ (编排器)         │    │ (证据提取→Spec输出)   │
└──────────────┘    └─────────────────┘    └──────────┬───────────┘
                                                      │
                    ┌─────────────────────────────────┘
                    ▼
┌──────────────────────┐    ┌──────────────────┐    ┌──────────────┐
│ Agent (CLI subprocess)│───▶│ Scenario Workspace│───▶│ Build (HAP)  │
│ 读Spec→改代码→构建     │    │ spec/+mock/+src   │    │ + result.json│
└──────────────────────┘    └──────────────────┘    └──────┬───────┘
                                                           │
                    ┌──────────────────────────────────────┘
                    ▼
┌──────────────────────┐    ┌──────────────────────┐
│ Web Console (:8765)  │    │ Git Auto-Commit      │
│ 实时仪表盘+日志+控制  │    │ feat: automate {...}  │
└──────────────────────┘    └──────────────────────┘
```

详细 SVG 架构图见: [simapp-automation-architecture.svg](./simapp-automation-architecture.svg)

---

## 3. 核心流水线流程

### 3.1 入口命令

```bash
python dev/scripts/run_pipeline.py --input scenario1.json [--wait] [--dry-run] [--no-web]
```

### 3.2 阶段分解

#### Phase 1 — 场景解析 (run_pipeline.py:408-412)

从 JSON 中提取两个关键字段：

| 字段 | 提取方式 | 用途 |
|---|---|---|
| `app` | `scenario_payload.get("app")` → `normalize_app_key()` | 确定 APP 类型，选择基线工程 |
| `question` | `scenario_payload.get("question")` or `scenario_payload.get("prompt")` | 写入运行时状态，Web Console 展示 |

`app` 字段通过 `normalize_app_key()` 在 `pipeline.config.json` 的 `app_types` 中做模糊匹配（支持别名）：

- `"travel"` / `"trip"` / `"tour"` → `travelApp`
- `"explore"` / `"content"` → `exploreApp`
- `"shopping"` / `"shop"` / `"ecom"` → `shoppingApp`
- `"delivery"` / `"waimai"` / `"food"` → `deliveryApp`
- 空或未匹配 → `commonApp`

#### Phase 2 — 工作区初始化 (run_pipeline.py:437-462)

1. 从 `apps/baseline/{appType}/` 拷贝基线工程到 `apps/scenarios/{appType}/scenarioXXX/`
2. 排除 `build`、`.hvigor`、`mock-data`、`output`、`logs`、`state`、`spec` 目录
3. 创建运行时目录结构: `spec/` `mock-data/` `output/` `logs/` `state/`

#### Phase 3 — Prompt 构造 (run_pipeline.py:447-463)

读取 `dev/config/task_template.txt`，将以下变量注入模板：

| 模板变量 | 来源 |
|---|---|
| `{{INPUT_JSON_CONTENT}}` | 整个 JSON 序列化 |
| `{{APP_TYPE}}` | app 解析结果 |
| `{{SCENARIO_ROOT}}` | 场景工作区绝对路径 |
| `{{BASELINE_DIR}}` | 基线来源路径 |
| `{{BUILD_COMMAND}}` | 完整构建命令 |
| `{{MOCK_DATA_DIR}}` | mock 数据目录 |
| `{{RESULT_JSON_PATH}}` | 结果输出路径 |
| `{{SPEC_DIR}}` | Spec 输出目录 |

#### Phase 4 — Agent 下发 (run_pipeline.py:511-525)

Agent 以子进程方式启动，stdout/stderr 重定向到日志文件。支持 stdin 管道模式（Codex CLI）和文件参数模式（OpenCode CLI）。

详见 [第 6 节](#6-agent-适配与可扩展性)。

#### Phase 5 — 监控与交付 (run_pipeline.py:527-548)

- 默认启动 Web Console（`--no-web` 可禁用）
- `--wait` 模式下同步等待 Agent 结束并读取 `result.json` 判定成功/失败
- `monitor_results.py` 可独立轮询所有场景并自动 Git 提交

---

## 4. Spec 自动化提取

### 4.1 Skill 定义

Skill 文件: `skills/simapp-scenario-spec-gen/SKILL.md`

核心能力：将非结构化的场景描述（JSON）转化为结构化的增量开发 Spec。

### 4.2 五步工作流

```
Step 1                Step 2              Step 3              Step 4-5
收集场景证据     →    重建目标场景    →    框架差距分析    →    按模板输出 Spec
│                      │                    │                    │
│ 提取: question       │ 识别: 模块/页面    │ already_implemented │ spec-template.md
│       exception      │       交互流程     │ modify_existing     │ 10 章节固定结构
│       exception_type │       用户目标     │ new_feature         │
│       app            │       前置条件     │ blocked_by_input    │ 自动落盘到
│       flow           │       跳转路径     │                     │ spec/*.spec.md
│       flow_reason    │       异常行为     │ 框架基线参考:       │
│                      │                    │ framework-baseline  │
│ 缺失字段 → 从        │ 标注: 确认/模糊/   │ .md                 │
│ question 推断        │       假设/未知    │                     │
│                      │                    │                     │
│ 分析检查清单:        │ 信息缺口 → 开放    │ 增量方案优先        │
│ scenario-analysis    │ 问题专节           │ 锚定已有文件        │
│ -checklist.md        │                    │                     │
```

### 4.3 JSON 字段映射

#### 直接提取字段

| JSON 字段 | Spec 落点 | 说明 |
|---|---|---|
| `question` | §2.1 原始问题描述 | 自然语言锚点 |
| `question` (兜底) | §4 重建流程 | 当 exception/flow 为空时，从中语义推断 |
| `exception` | §3.1 JSON 证据 → §4.4 重点触发点 | 异常行为描述 |
| `exception_type` | §3.1 → §6.4/§6.5 | 异常分类 → 决定需求归类 |
| `exception_reason` | §3.1 | 异常原因 |
| `app` | §1 目标 App / 业务域 | APP 类型 |
| `flow` | §4 重建后的产品流程 | 交互流程描述 |
| `flow_reason` | §4.3 用户动作与系统响应 | 流程因果 |
| 其他所有字段 | §3.1 JSON 证据 | 实体（城市、订单、商品等） |

#### 置信度分级

基于信息完整度，每个场景被归入三级置信度：

| 置信度 | 条件 | Spec 行为 |
|---|---|---|
| **High** | question + exception + flow 齐全且一致 | 产生产完整的开发任务分解 |
| **Medium** | 部分字段缺失但可从 question 推断 | 生成暂定 Spec，标注假设 |
| **Low** | 信息严重不足 | Spec 聚焦阻塞项和开放问题 |

### 4.4 框架差距分析

对比 `framework-baseline.md` 定义的基线能力：

**基线现状**:
- 只有一个页面 `pages/Index`，无真实业务页面
- 无路由系统（router），无多页面栈管理
- 仅有 `@State` 本地状态，无 ViewModel/Store/网络层
- 无 mock 数据框架，无持久化

**分类规则**:
- **already implemented**: 仅在当前分支确实存在对应页面/路由/交互时标记
- **modify existing**: 现有框架可支撑但需调整（如扩展已有组件）
- **new feature**: 需要新增页面、路由、状态管理、数据层
- **blocked by missing input**: 场景信息不足以做实现决策

> 真实场景下绝大多数需求属于 `new feature` 或 `modify existing`。

### 4.5 Spec 输出模板

最终 Spec 按 `spec-template.md` 的固定 10 章节输出：

```
§1  Spec 元信息 (来源、目标、置信度)
§2  场景摘要 (原始问题、产品摘要、预期行为)
§3  证据清单 (JSON/截图/UTG 证据、信息缺口)
§4  重建后的产品流程 (前置条件、页面序列、交互)
§5  UI/页面设计规格 (页面布局、组件状态、导航规则)
§6  框架差距分析 (已有能力、需修改、需新增、阻塞项)
§7  增量开发计划 (变更文件清单、实现任务、非目标项)
§8  测试策略 (功能测试、UI验证、回归范围)
§9  验收标准
§10 假设与开放问题
```

---

## 5. Skill 调用机制

### 5.1 调用路径

```
Agent 收到 Task Prompt
  │
  ├─ 尝试: 调用 skill "simapp-scenario-spec-gen"
  │   └─ 成功 → Skill 按 SKILL.md 规则执行
  │
  └─ 失败 → 回退: 直接读取 skills/simapp-scenario-spec-gen/SKILL.md
      └─ 按文档规则手动执行整个工作流
```

`task_template.txt` 中的指令:

> 优先使用名为 `simapp-scenario-spec-gen` 的 skill 生成 APP 开发 spec，并将 spec 文件保存到 `{{SPEC_DIR}}`。如果当前运行环境无法发现或调用该 skill，必须直接读取并遵循仓库文件 `skills/simapp-scenario-spec-gen/SKILL.md` 中的完整规则后继续执行，不能因为"找不到 skill"而跳过 spec 生成。

### 5.2 Skill 引用资源

```
skills/simapp-scenario-spec-gen/
├── SKILL.md                              ← 主规则文件
├── agents/openai.yaml                    ← Agent 接口定义
└── references/
    ├── scenario-analysis-checklist.md    ← 场景提取检查清单
    ├── framework-baseline.md             ← 框架基线能力文档
    └── spec-template.md                  ← Spec 输出模板
```

### 5.3 设计要点

- **Skill 规则独立于 Agent**：Skill 是纯文档规则 + 固定流程，不依赖特定 Agent 实现
- **双重保障**：Agent 优先以 Skill 方式调用，不可用时回退到读文档模式
- **模板化输出**：强制使用 `spec-template.md` 结构，保证多次输出格式一致
- **证据驱动**：所有 Spec 内容必须有 JSON/截图/UTG 作为证据来源，不允许编造

---

## 6. Agent 适配与可扩展性

### 6.1 架构设计

Agent 层采用 **配置驱动 + 统一运行时抽象** 的设计，通过 `pipeline.config.json` 注册即可切换或新增 Agent。

### 6.2 Agent 定义 (pipeline.config.json)

```json
{
  "agent": {
    "active": "opencode_cli",
    "definitions": {
      "codex_cli": {
        "display_name": "Codex CLI",
        "command": ["codex.cmd", "exec", "--yolo", "-"],
        "env": {},
        "task_via_stdin": true,
        "runtime_family": "codex",
        "supports_resume": false
      },
      "opencode_cli": {
        "display_name": "OpenCode CLI",
        "command": [
          "opencode.cmd", "run",
          "--model", "{{OPENCODE_MODEL}}",
          "请阅读并完整执行 -f 附加文件中的任务说明。",
          "-f", "{{TASK_PROMPT_FILE}}"
        ],
        "env": {},
        "task_via_stdin": false,
        "runtime_family": "opencode",
        "supports_resume": false
      }
    }
  }
}
```

### 6.3 两种 Prompt 传递模式

#### 模式 A: stdin 管道 (Codex CLI)

```
task_prompt → subprocess.stdin.write() → codex.cmd exec --yolo -
```

```python
process = subprocess.Popen(["codex.cmd", "exec", "--yolo", "-"], stdin=subprocess.PIPE, ...)
process.stdin.write(task_prompt)
process.stdin.close()
```

适用场景: Agent CLI 支持从 stdin 读取任务描述。

#### 模式 B: 文件参数 (OpenCode CLI)

```
task_prompt → write to spec/task_prompt.txt → opencode.cmd run -f <path>
```

```python
task_prompt_path = spec_dir / "task_prompt.txt"
task_prompt_path.write_text(task_prompt)
command = ["opencode.cmd", "run", "-f", str(task_prompt_path), ...]
```

适用场景: Agent CLI 支持通过 `-f` 参数加载任务文件。`{{TASK_PROMPT_FILE}}` 由 `build_prompt_variables()` 在渲染时注入。

### 6.4 运行时环境统一抽象

所有 Agent 共享同一套运行时信息模型（`build_agent_runtime_info()`）：

```python
{
    "workspace": str(repo_root),
    "name": "opencode cli",
    "model": "mlops/qwen35-35b-vl",
    "provider": "...",
    "approval_policy": "...",
    "sandbox_mode": "...",
    "reasoning_effort": "...",
    "reasoning_summary": "...",
    "session_id": "..."
}
```

不同 `runtime_family`（如 `opencode` vs `codex`）有不同的环境变量来源（`OPENCODE_MODEL` vs `CODEX_MODEL`），但所有 Agent 的日志统一写入 `agent-{scenario}-{timestamp}.log`。

### 6.5 扩展新 Agent

只需在 `pipeline.config.json` 的 `agent.definitions` 中新增一个条目：

```json
"my_agent": {
  "display_name": "My Custom Agent",
  "command": ["my-agent", "run", "--task-file", "{{TASK_PROMPT_FILE}}"],
  "env": {
    "MY_AGENT_MODEL": "gpt-5"
  },
  "task_via_stdin": false,
  "runtime_family": "custom",
  "supports_resume": false
}
```

然后将 `agent.active` 切换为 `"my_agent"` 即生效。无需修改任何 Python 代码。

### 6.6 安全边界

Agent 运行时被严格限制在场景工作区内：

```
✅ 可修改: apps/scenarios/{appType}/scenarioXXX/**
❌ 禁止修改: apps/baseline/**, dev/**, build/**, README.md, 根目录其他内容
```

越界修改 → Agent 必须在 `result.json` 中明确写出越界路径，任务标记为失败。

---

## 7. APP 开发流程

### 7.1 基线工程体系

```
apps/baseline/
├── commonApp/       ← 最简骨架: Index.ets + @State 按钮计数
├── exploreApp/      ← 内容APP: 5 页面虚拟屏 + Feed/Search/Publish/Profile
├── travelApp/       ← 出行APP: 9 虚拟屏 + 搜索/预订/支付完整流程
├── shoppingApp/     ← (规划中)
└── deliveryApp/     ← (规划中)
```

每个基线 APP 都是 HarmonyOS ArkUI **单模块工程**，通过虚拟屏幕（`@State currentScreen` + 条件渲染）模拟多页面，而非使用 router。

### 7.2 场景工作区结构

```
apps/scenarios/travel/scenario004/
├── AppScope/app.json5                     ← 基线拷贝
├── build-profile.json5                    ← 基线拷贝 (签名注入)
├── entry/
│   └── src/main/ets/
│       ├── entryability/EntryAbility.ets  ← 基线拷贝
│       ├── pages/Index.ets               ← [Agent 修改] 主要开发目标
│       ├── models/AppModels.ets          ← 基线拷贝 + 可扩展
│       ├── mock/homeMock.ets             ← 基线拷贝
│       ├── mock/searchMock.ets           ← 基线拷贝
│       ├── mock/orderMock.ets            ← 基线拷贝
│       └── mock/inventoryMock.ets        ← 基线拷贝
├── mock-data/                             ← [Agent 新建] 独立 JSON mock
│   └── adPopup.json
├── spec/                                  ← [Agent 新建] Spec 文件
│   ├── scenario4.spec.md
│   └── task_prompt.txt
├── output/                                ← [构建产物] result.json + *.hap
├── logs/                                  ← pipeline 日志 + agent 日志
└── state/                                 ← runtime.json
```

### 7.3 Agent 开发步骤

Agent 收到 Task Prompt 后的典型行为序列：

1. **生成 Spec** — 调用 Skill 或阅读 SKILL.md → 按模板生成 `spec/scenarioN.spec.md`
2. **制定计划** — 基于 Spec 的 §7 增量开发计划确定变更范围
3. **准备 Mock 数据** — 将数据抽离为独立 JSON 文件，存入 `mock-data/`
4. **修改代码** — 以 `entry/src/main/ets/pages/Index.ets` 为主要目标，扩展组件和状态
5. **自检边界** — diff 确认所有修改均在场景目录内，无越界
6. **执行构建** — 调用 `build.ps1 -Target apps/scenarios/{appType}/scenarioXXX/`
7. **输出结果** — 写入 `output/result.json`（成功 / 失败 + 详细信息）

### 7.4 ArkTS 开发模式

当前基线采用 **单文件 Index.ets 虚拟屏架构**：

```typescript
// 典型的场景开发模式 (以 scenario004 红包弹窗为例)
type ScreenKey = 'home' | 'search' | ... | 'adPage';  // 扩展新页面

@Entry
@Component
struct Index {
  @State currentScreen: ScreenKey = 'home';
  @State showAdPopup: boolean = false;  // 新增状态

  @Builder buildAdPopup() { ... }       // 新增组件
  @Builder buildAdPage() { ... }        // 新增页面

  build() {
    if (this.currentScreen === 'adPage') {
      this.buildAdPage();
    } else {
      // 原有页面 + 弹窗叠加
      Stack() {
        this.buildCurrentScreen();
        if (this.showAdPopup) { this.buildAdPopup(); }
      }
    }
  }
}
```

---

## 8. 自验证闭环

### 8.1 闭环流程

```
┌─────────────────────────────────────────────────────────────────┐
│                    自验证闭环 (Closed Loop)                       │
│                                                                  │
│  Spec.md ──▶ 编码实现 ──▶ build.ps1 ──▶ hvigor ──▶ HAP 产物     │
│     ▲                                            │               │
│     │                                            ▼               │
│     │                                    result.json             │
│     │                                      │                     │
│     │              ┌───────────────────────┼───────────────┐     │
│     │              │ 成功                   │ 失败           │     │
│     │              ▼                        ▼               │     │
│     │     Git Commit + Push      Agent 读取错误日志          │     │
│     │     任务完成 ✓             修复代码 → 重新构建 ────────┘     │
│     │                                    (反馈循环)              │
│     └─────────────────────────────────────────────────────────── │
└─────────────────────────────────────────────────────────────────┘
```

### 8.2 构建流程 (build.ps1)

```
build.ps1 -Target apps/scenarios/travel/scenario001
  │
  ├─ 1. 读取 build.config.json (DevEco Studio 路径、SDK 路径、JDK 路径)
  ├─ 2. 创建 Compat SDK Junction (openharmony + hms 链接)
  ├─ 3. 拷贝目标工程到 tmp/ 临时工作区 (排除 build/.hvigor/node_modules)
  ├─ 4. 注入签名配置 (环境变量 OHOS_CERT_PATH → build-profile.json5)
  ├─ 5. 创建 hvigor npm Junction (node_modules/@ohos/hvigor)
  ├─ 6. 设置 DEVECO_SDK_HOME + NODE_PATH
  └─ 7. node hvigor.js assembleHap -p buildMode=debug --no-daemon
       │
       └─ 输出: entry/build/default/outputs/default/*.hap
```

**关键环境变量**:

| 变量 | 用途 |
|---|---|
| `DEVECO_STUDIO_ROOT` | DevEco Studio 安装根目录 |
| `OHOS_CERT_PATH` | 签名证书路径 |
| `OHOS_KEY_ALIAS` | 密钥别名 |
| `OHOS_KEY_PASSWORD` | 密钥密码 |
| `OHOS_PROFILE_PATH` | Provision Profile 路径 |
| `OHOS_STORE_FILE` | 密钥库文件路径 |
| `OHOS_STORE_PASSWORD` | 密钥库密码 |

### 8.3 result.json 规范

构建完成后 Agent 必须写入 `output/result.json`：

**成功时**:
```json
{
  "buildStatus": "success",
  "artifactPath": "entry/build/default/outputs/default/entry-default-unsigned.hap",
  "artifactSizeBytes": 1234567,
  "buildTime": "2026-05-05T14:30:00+08:00",
  "scenarioDir": "apps/scenarios/travel/scenario004",
  "appType": "travel"
}
```

**失败时**:
```json
{
  "buildStatus": "failed",
  "failureTime": "2026-05-05T14:30:00+08:00",
  "errorSummary": "ArkTS 编译错误: ...",
  "lastLogPath": "logs/agent-scenario004-20260505T142500.log",
  "scenarioDir": "apps/scenarios/travel/scenario004",
  "appType": "travel"
}
```

### 8.4 成功判定逻辑

```python
# pipeline_monitor_lib.py / common.py
def detect_build_success(result_payload, success_values):
    status = str(result_payload.get("buildStatus", "")).lower()
    return status in success_values  # ["success", "succeeded", "ok", "passed", "true"]
```

### 8.5 自动 Git 交付

`monitor_results.py` 轮询检测到构建成功后：

1. 读取 `state/runtime.json` 确认状态为 `completed`
2. 执行 `git add` 添加场景工作区的新增/修改文件
3. 执行 `git commit -m "feat: automate {appType}/scenarioXXX"`
4. 执行 `git push`
5. 更新状态为 `pushed`

---

## 9. 配置与扩展点

### 9.1 主配置文件

`dev/config/pipeline.config.json` — 所有扩展都从此文件注入：

| 配置区 | 扩展点 | 说明 |
|---|---|---|
| `app_types` | 新增 APP 类型 | 添加 display_name + aliases + baseline_dir |
| `agent.definitions` | 新增 Agent | 添加 command + env + runtime_family |
| `agent.active` | 切换 Agent | 改为 definitions 中的任意 key |
| `scheduler.success_values` | 自定义成功判定 | 扩展 result.json 的成功状态值列表 |
| `scheduler.commit_message_template` | 自定义提交信息 | 支持 `{pipeline_key}` 变量 |
| `build.command` | 自定义构建命令 | 替换构建入口脚本 |

### 9.2 扩展新 APP 基线类型

1. 在 `apps/baseline/` 下创建新 APP 目录（如 `shoppingApp/`）
2. 实现基线 Index.ets + mock 数据 + models
3. 在 `pipeline.config.json` 的 `app_types` 中注册：
   ```json
   "shopping": {
     "display_name": "购物类APP",
     "aliases": ["shopping", "shop", "ecom", "mall"],
     "baseline_dir": "apps/baseline/shoppingApp"
   }
   ```
4. JSON 中输入 `"app": "shopping"` 即可路由到该基线

### 9.3 扩展新 Skill

1. 在 `skills/` 下创建新 Skill 目录（如 `simapp-ui-review`）
2. 编写 `SKILL.md`，定义工作流和输出规则
3. 在 `task_template.txt` 中添加调用指令
4. Agent 即可在新场景中使用该 Skill

---

## 10. 附录

### 10.1 关键文件索引

| 文件 | 角色 |
|---|---|
| `dev/scripts/run_pipeline.py` | 流水线主入口，编排全部阶段 |
| `dev/scripts/common.py` | 公共工具库（JSON、路径、时间、进程） |
| `dev/scripts/pipeline_monitor_lib.py` | 监控检查 + Git 提交逻辑 |
| `dev/scripts/monitor_results.py` | 独立轮询监控脚本 |
| `dev/scripts/web_console.py` | HTTP 仪表盘服务 |
| `dev/config/pipeline.config.json` | 核心配置（APP类型、Agent定义、调度参数） |
| `dev/config/task_template.txt` | Agent 任务模板（`{{变量}}` 占位符） |
| `build/build.ps1` | HarmonyOS hvigor 构建脚本 |
| `skills/simapp-scenario-spec-gen/SKILL.md` | Spec 生成 Skill 规则 |
| `dev/frontend/index.html` + `app.js` + `styles.css` | Web 仪表盘前端 |

### 10.2 目录约定

```
{project}/
├── apps/
│   ├── baseline/{appType}/          ← 基线工程 (只读，Agent 禁止修改)
│   └── scenarios/{appType}/{scenarioXXX}/
│       ├── spec/                    ← Spec 文件 (*.spec.md, task_prompt.txt)
│       ├── mock-data/               ← 独立 JSON mock 数据
│       ├── output/result.json       ← 构建结果
│       ├── logs/                    ← pipeline/agent/web 日志
│       └── state/runtime.json       ← 运行时状态
├── build/
│   └── build.ps1                    ← 构建入口
├── dev/
│   ├── config/                      ← 配置中心
│   ├── scripts/                     ← Python 脚本
│   └── frontend/                    ← Web Console 前端
└── skills/
    └── {skill-name}/
        ├── SKILL.md                 ← 规则定义
        └── references/              ← 参考文档
```

### 10.3 命令行参考

```bash
# 基础执行
python dev/scripts/run_pipeline.py --input scenario1.json

# 等待 Agent 完成 (同步模式)
python dev/scripts/run_pipeline.py --input scenario1.json --wait

# 预览模式 (不实际执行)
python dev/scripts/run_pipeline.py --input scenario1.json --dry-run

# 手动指定场景编号 (否则从文件名推断)
python dev/scripts/run_pipeline.py --input my_case.json --scenario-id 005

# 无 Web Console 模式
python dev/scripts/run_pipeline.py --input scenario1.json --no-web

# 强制重试
python dev/scripts/run_pipeline.py --input scenario1.json --force-retry

# 独立监控 (轮询模式)
python dev/scripts/monitor_results.py --loop
python dev/scripts/monitor_results.py --once

# Web Console 独立启动
python dev/scripts/web_console.py --selected travel/scenario001
```

---

> 架构图: [simapp-automation-architecture.svg](./simapp-automation-architecture.svg)
