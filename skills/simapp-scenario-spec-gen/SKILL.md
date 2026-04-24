---
name: simapp-scenario-spec-gen
description: 基于场景 JSON app场景截图、UTG 产物和当前项目分支，为 simApp 特定场景还原生成开发 spec。适用于需要分析 scenario1.json 这类场景定义、重建涉及的 App 页面与交互流程、识别缺失或模糊的 UI 信息、对比当前 HarmonyOS ArkUI 框架能力，并产出结构稳定、需求清晰、UI 设计明确、可测试可验收的增量实现说明的任务。
---

# SimApp 场景 Spec 生成

## 概述

使用这个 skill，可以把APP场景输入转换成面向当前仓库的可实现 spec。先基于证据重建场景，再对照现有代码库判断实现范围，最后输出结构稳定、基于模板的增量开发 spec。

## 工作流

### 1. 收集场景证据

优先读取场景 JSON。存在时，至少提取以下字段：

- `question`
- `exception`
- `exception_type`
- `exception_reason`
- `app`
- `flow`
- `flow_reason`

如果其他字段为空，则从 `question` 中推断核心场景表述。如果文件内容存在乱码或编码噪声，先做归一化再继续分析。

如果同时提供了截图或 UTG 数据：

- 使用截图补充可见 UI 组件、视觉层级、文案、异常状态和样式线索。
- 使用 UTG 补充页面拓扑、导航边、入口点和交互可达性。
- 将截图和 UTG 的补充分析视为可选证据。若缺失，应明确说明信息缺口，不要编造细节。

使用 [scenario-analysis-checklist.md](./references/scenario-analysis-checklist.md) 保证提取过程稳定一致。

### 2. 重建目标场景

场景总结应以产品行为为中心，而不是仅复述原始 JSON。

需要识别：

- 涉及的 App 模块或业务域
- 可能涉及的页面或视图
- 用户目标与前置条件
- 预期交互流程
- 已观察到的异常行为
- 可能的页面跳转路径与返回路径
- 被证据明确确认的 UI 元素
- 仍然模糊的 UI 或交互细节
- 当前场景信息是否足以支撑实现

如果细节不足，必须保留“假设”或“开放问题”专节。不要默默用产品细节脑补填空。

### 3. 对比当前分支

在提出开发任务前，先检查当前仓库。重点关注页面、路由、可复用组件、状态管理、数据来源和样式基础能力。

使用 [framework-baseline.md](./references/framework-baseline.md) 作为当前仓库的默认基线，再判断工作区是否已偏离该基线。

将每条需求归入以下类别之一：

1. `already implemented`：当前分支已经支持所需行为，不需要新增开发任务。
2. `modify existing`：现有框架已经有接近目标的功能或页面，只需要进行定向修改。
3. `new feature`：现有框架缺少对应能力，需要新增页面、组件、导航、状态或数据逻辑。
4. `blocked by missing input`：由于缺少关键场景细节，请求当前无法被安全实现。

优先输出增量方案。只要可能，就把每个开发项锚定到已有文件、模块或能力上。

### 4. 谨慎处理 UI 精细化建模

始终保留一个“基于截图与 UTG 的 UI 精细化建模”子章节。

当前规则：

- 每份 spec 都必须包含该子章节。
- 章节内容只能写入被证据确认的信息。
- 如果没有截图或 UTG 产物，则标记为 `reserved / not implemented in this pass`。

不要根据微弱线索编造精确尺寸、颜色或组件树。

### 5. 按固定结构输出最终 spec

始终使用 [spec-template.md](./references/spec-template.md) 中的模板。保持章节顺序与标题不变，以确保多次输出结构一致。

spec 必须满足：

- 区分已确认事实、推断、假设和未知项
- 用可实现的方式描述目标页面和 UI 组件
- 解释每项任务为何属于新增、修改、已覆盖或被阻塞
- 包含测试范围和验收标准
- 保持相对于当前代码库的增量性质

## 输出规则

使用简洁、面向实现的语言。

保持结构稳定，但根据证据质量调整内容深度：

- 如果场景信息不足，仍然输出完整模板，并显式标注不确定部分。
- 如果当前框架已经实现该场景，则输出“无需开发、只需验证”的 spec，而不是强行编造开发任务。
- 如果请求涉及多个候选页面，应在同一模板中拆分为多个子流程。

### 6. 默认落盘规则

生成 spec 时，不要只在对话中输出，默认必须同时写入仓库文件。

默认输出目录：

- 当前场景目录下的 `scenarios/scenarioxxx/spec/`

默认命名规则：

- 如果当前目标目录是 `scenarios/scenario001/spec/` 且输入文件是 `scenario1.json`，则输出为 `scenarios/scenario001/spec/scenario1.spec.md`
- 如果当前目标目录是 `scenarios/scenario001/spec/` 且输入文件是 `foo/bar/case-a.json`，则输出为 `scenarios/scenario001/spec/case-a.spec.md`
- 如果一次生成多个场景，则为每个场景分别生成独立 `.spec.md` 文件

默认行为：

- 先按模板生成完整 spec 内容
- 再将内容保存到默认 spec 文件
- 最后在对话中返回生成结果摘要和文件路径

只有在用户明确指定其他输出路径时，才覆盖上述默认规则。

当用户只要求 spec 时，生成并保存完成版 spec，再在对话中返回文件路径。当用户要求先分析时，先给出简短分析摘要，再生成并保存完整 spec。

## 仓库特定说明

针对当前仓库基线：

- 除非当前分支体现出更完整的业务能力，否则应将其视为 HarmonyOS ArkUI 示例应用。
- 默认假设只有一个入口页、少量本地状态，没有正式业务流程。
- 对于真实的App特定场景，大多数情况应归入 `new feature` 或 `modify existing`，而不是 `already implemented`。

在判断“场景已被支持”之前，必须确认相关页面、路由和交互在当前分支中真实存在。

## 参考资料

- 在提取场景细节前，先阅读 [scenario-analysis-checklist.md](./references/scenario-analysis-checklist.md)。
- 在判断实现范围前，先阅读 [framework-baseline.md](./references/framework-baseline.md)。
- 每次输出最终 spec 时，都复制 [spec-template.md](./references/spec-template.md) 的标题结构。
