# 当前框架基线

将这份文档作为当前仓库的默认起点假设，再进一步验证当前分支是否已经发生变化。该基线面向 `C:\Users\ttelab\commApp\simApp-main\smiAPP_0414_codex` 当前工作区，而不是一个抽象的通用 simApp 框架。

## 1. 工程形态

- 平台：HarmonyOS ArkUI / ArkTS
- 工程性质：单模块示例应用，不是完整业务 App
- 根模块：`entry`
- App 级配置：`AppScope/app.json5`
- 模块级配置：`entry/src/main/module.json5`
- 入口 Ability：`entry/src/main/ets/entryability/EntryAbility.ets`
- 主页面注册表：`entry/src/main/resources/base/profile/main_pages.json`
- 当前注册页面：仅 `pages/Index`
- 当前页面实现：`entry/src/main/ets/pages/Index.ets`

## 2. 应用与构建元信息

- bundleName：`com.hauwei.arkUIdemo`
- app label 资源：`$string:app_name`
- 当前应用名称文案：`ArkUI Demo`
- vendor：`example`
- versionName：`1.0.0`
- versionCode：`1000000`
- deviceTypes：`phone`、`tablet`
- runtimeOS：`HarmonyOS`
- compatibleSdkVersion：`6.0.2(22)`
- targetSdkVersion：`6.0.2(22)`
- buildMode：`debug`、`release`

## 3. 启动与页面装配方式

- 应用通过 `EntryAbility` 启动。
- `onWindowStageCreate` 中直接 `loadContent('pages/Index')`。
- 当前没有根据业务状态决定首屏的分发逻辑。
- 当前没有登录态、城市态、地址态或订单态决定的启动分支。
- 当前没有独立路由管理层，页面装配方式仍然是最基础的入口页加载。

## 4. 当前页面与 UI 组成

当前唯一页面是 `Index.ets`，其 UI 结构可视为一个静态演示页，而不是业务首页。

已确认页面组成：

- 顶部标题区
  - 标题：`HarmonyOS ArkUI`
  - 副标题：`A simple home page with state, list rendering, and click interaction.`
- 一个点击计数卡片区
  - 展示文案：`Button clicked {n} times`
  - 一个 `Tap Here` 按钮
- 一个清单区
  - 标题：`Build Checklist`
  - 三个本地 Todo 项
  - 每项包含状态圆点、标题文本和 `Done` / `Undo` 按钮
- 底部使用 `Blank()` 占位填充剩余空间

已确认样式特征：

- 页面根背景色：`#F3F6FB`
- 页面主容器为 `Column`
- 大量使用白底卡片、圆角、静态间距
- 当前样式为 demo 级本地硬编码，不是主题化设计系统
- 当前没有独立公共样式 token、组件库封装或品牌设计规范

## 5. 当前交互与状态模型

当前只存在本地内存态交互：

- `clickCount`
  - 类型：`number`
  - 作用：记录按钮点击次数
  - 更新方式：点击 `Tap Here` 后自增
- `todos`
  - 类型：`TodoItem[]`
  - 作用：渲染本地演示清单
  - 更新方式：点击每行按钮后切换 `done` 状态

当前状态管理边界：

- 仅页面内 `@State`
- 没有 `@StorageLink`、`AppStorage`、持久化存储或跨页共享状态
- 没有 ViewModel、Store、Repository 或服务层抽象
- 没有异步请求驱动的状态切换

## 6. 当前资源与文案基线

- 字符串资源文件：`entry/src/main/resources/base/element/string.json`
- 颜色资源文件：`entry/src/main/resources/base/element/color.json`
- 当前字符串资源较少，仅包含 app 名称、模块描述和入口描述
- 当前颜色资源仅显式声明启动窗口背景色 `#F3F6FB`
- 页面大部分文案和颜色仍直接写在 `Index.ets` 中
- 当前没有业务词汇表，如城市、地址、景点、票务、订单、支付等资源定义，只是一个基础通用的骨架

## 7. 当前已经具备的能力

可以视为已存在的基础能力：

- 单页面 ArkUI 声明式布局
- 文本、按钮、行列容器等基础组件拼装
- 本地 `@State` 状态更新
- `ForEach` 列表渲染
- 基于本地状态的简单交互反馈
- 从 Ability 加载单个页面
- 使用 build 脚本构建 HarmonyOS HAP

这些能力只说明“框架壳”存在，不代表具体业务流程已经实现。

## 8. 当前缺失或未落地的能力

默认缺失的框架能力包括：

- 没有旅游业务域流程
- 没有购票、选城市、选地址、下单、确认页等业务页面
- 没有多页面导航流程
- 没有除 `pages/Index` 之外的已注册页面
- 没有页面路由图或页面栈管理设计
- 没有可复用业务组件
- 没有网络驱动的数据流
- 没有接口层、数据适配层或 mock 数据方案
- 没有持久化层
- 没有定位、地图、地址选择或城市切换能力
- 没有显式加载态、空态、错误态、权限态模式
- 没有表单校验、搜索、筛选、弹窗、Toast、底部浮层等业务交互模式
- 没有自动化测试、页面级测试或业务验收脚本

## 9. 对 simApp 场景还原的直接含义

针对故障场景 spec 生成，默认应做如下判断：

- 不要假设“旅游首页”“猫眼首页”“地址切换”“当前定位城市”“购票流程”已经存在。
- 即使场景描述中提到首页，也不能把当前 `Index.ets` 直接当作真实业务首页。
- 若场景要求出现页面跳转、业务状态同步、地址选择、定位结果回填或多页面回退，通常都属于 `new feature` 或 `modify existing`。
- 只有当当前分支真实新增了相应页面、路由和交互，才能标记为 `already implemented`。
- 如果场景只需要一个静态说明页或极轻量的本地交互演示，才可能复用现有 demo 页面结构。

## 10. spec 生成时的推荐映射规则

在把场景需求映射到当前分支时，优先按以下思路判断：

1. 页面是否存在
   - 当前通常答案是否，因为只注册了 `pages/Index`。
2. 交互模式是否存在
   - 当前只有按钮点击和本地列表切换。
3. 状态来源是否存在
   - 当前只有页面内内存态，不存在业务数据源。
4. 路由链路是否存在
   - 当前不存在真实业务跳转链路。
5. UI 是否可直接复用
   - 只能复用最基础的 ArkUI 布局能力，不能视为业务 UI 已实现。

## 11. 基线更新触发条件

若当前分支后续发生以下变化，应同步更新本文件：

- 新增第二个及以上业务页面
- `main_pages.json` 注册更多页面
- 引入 `router` 或其他显式导航逻辑
- 增加网络请求、仓储层或 mock 数据层
- 增加业务组件目录或公共 UI 组件
- 增加定位、地址、城市、购票、订单等业务能力
- 增加测试脚本或自动化验收能力
