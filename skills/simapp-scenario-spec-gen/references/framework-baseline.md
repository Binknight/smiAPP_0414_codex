# 当前框架基线

将这份文档作为当前仓库的默认起点假设，再进一步验证当前分支是否已经发生变化。该基线面向 `C:\Users\ttelab\commApp\travel-sim-app` 当前工作区，而不是旧仓库或抽象的通用 simApp 框架。

## 1. 工程形态

- 平台：HarmonyOS ArkUI / ArkTS
- 工程性质：单模块旅行仿真预订应用，已具备多业务屏内容，但仍以本地 mock 数据驱动
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
- 当前应用名称文案：`途屿旅行`
- module 描述：`旅游类仿真预订应用`
- entry 描述：`旅游类 APP 主入口`
- vendor：`example`
- versionName：`1.0.0`
- versionCode：`1000000`
- deviceTypes：`phone`、`tablet`
- runtimeOS：`HarmonyOS`
- compatibleSdkVersion：`6.0.2(22)`
- targetSdkVersion：`6.0.2(22)`
- hvigor / plugin 版本：`6.0.1`
- buildMode：`debug`、`release`

## 3. 启动与页面装配方式

- 应用通过 `EntryAbility` 启动。
- `onWindowStageCreate` 中直接 `loadContent('pages/Index')`。
- 当前没有拆分为多 `.ets` 页面文件，也没有独立路由表。
- 页面切换由 `Index.ets` 内部状态 `currentScreen` 驱动，而不是正式 router 框架。
- 当前屏幕键包括：
  - `home`
  - `search`
  - `results`
  - `detail`
  - `booking`
  - `payment`
  - `orders`
  - `service`
  - `profile`
  - `orderDetail`

## 4. 当前页面与 UI 组成

当前唯一注册页面仍是 `Index.ets`，但它不再是简单 demo 页，而是一个单文件承载的旅行业务壳。已确认的主要 UI 分区如下：

- 首页
  - 顶部品牌标题与副标题
  - 酒店 / 机票 / 火车票 / 门票 / 度假服务切换
  - 搜索摘要卡片与“去查询”入口
  - 快捷业务入口网格
  - Banner 横向滚动区
  - 热门目的地与猜你喜欢推荐区
- 搜索页
  - 根据业务类型动态展示出发地、目的地、日期、人数、房间数、舱位等字段
  - 常用城市快捷选择
  - 搜索触发按钮
- 结果页
  - 排序条件切换
  - 筛选标签切换
  - 商品卡片列表
- 详情页
  - 商品头图区
  - 核心卖点
  - 套餐列表与预订入口
- 下单页
  - 订单摘要
  - 出行人 / 手机号 / 发票信息
  - 费用明细
- 支付页
  - 应付金额
  - 倒计时
  - 支付方式选择
- 订单页
  - 订单卡片列表
  - 订单状态与查看入口
- 订单详情页
  - 订单摘要
  - 状态、金额、售后服务信息
- 客服页
  - 智能客服、出行提醒、服务承诺信息块
- 我的页
  - 会员信息
  - 积分 / 钱包 / 优惠券资产卡片
  - 常用旅客、发票与报销、设置入口
- 底部 Tab
  - 首页
  - 订单
  - 客服
  - 我的

已确认样式特征：

- 主背景色仍为浅灰蓝色系：`#F3F7FB`
- 大量使用白底卡片、圆角、蓝色强调色 `#0A5EFF`
- 视觉风格已偏向旅行业务化，而不是旧的 checklist demo
- 样式仍然集中写在 `Index.ets`，尚未抽离为设计 token、公共主题或组件库

## 5. 当前交互与状态模型

当前交互核心仍是单页本地状态，但业务覆盖范围明显扩大。已确认主要状态包括：

- 页面导航状态
  - `currentScreen`
  - `currentTab`
- 搜索与业务态
  - `currentService`
  - `searchForm`
  - `selectedSort`
  - `selectedFilters`
- 商品与套餐选择态
  - `selectedProductId`
  - `selectedPackageId`
- 订单态
  - `selectedOrderId`
  - `orders`
- 填单与支付态
  - `draftTraveler`
  - `draftPhone`
  - `invoiceRequired`
  - `paymentMethod`
  - `paymentCountdown`

当前状态管理边界：

- 仅页面内 `@State`
- 没有 `AppStorage`、`PersistentStorage`、数据库或本地持久化
- 没有 ViewModel、Store、Repository 或独立服务层
- 没有真实异步请求，状态切换完全由同步本地逻辑驱动

## 6. 当前数据模型与 mock 基线

当前仓库已经具备明确的数据模型与 mock 数据层，不应再按“无业务数据”的旧假设处理。

已确认模型文件：

- `entry/src/main/ets/models/AppModels.ets`

已确认 mock 文件：

- `entry/src/main/ets/mock/homeMock.ets`
- `entry/src/main/ets/mock/inventoryMock.ets`
- `entry/src/main/ets/mock/searchMock.ets`
- `entry/src/main/ets/mock/orderMock.ets`

已确认业务类型：

- `hotel`
- `flight`
- `train`
- `ticket`
- `vacation`

已确认数据能力：

- 首页快捷入口、Banner、目的地推荐数据
- 搜索表单默认值、排序选项、筛选选项、常用城市
- 商品列表与详情数据
- 套餐数据
- 初始订单列表
- 会员资料数据

这意味着与“搜索、比价、结果列表、商品详情、下单、支付、订单查看、客服、个人中心”有关的场景，通常不再属于纯 `new feature from zero`，而应优先判断为 `modify existing`。

## 7. 当前已经具备的能力

可以视为已经存在的基础能力：

- 单入口页内多屏切换
- 首页到底部 Tab 的主导航壳
- 服务类型切换
- 搜索条件编辑与查询动作
- 结果列表排序与筛选
- 商品详情浏览
- 套餐选择与下单流程
- 支付方式选择与支付完成后的订单写入
- 订单列表与订单详情查看
- 客服与个人中心静态业务入口
- 本地 mock 数据驱动的旅行预订演示链路

这些能力说明“旅行预订业务壳”已经存在，只是仍然集中在单文件、本地状态和 mock 数据层。

## 8. 当前缺失或未落地的能力

默认缺失的框架能力包括：

- 没有真实多页面文件拆分
- 没有正式 router / NavPathStack / 页面栈管理
- 没有网络请求层
- 没有仓储层、接口适配层或数据缓存层
- 没有本地持久化
- 没有登录、鉴权、账号体系
- 没有真实定位、地图、地址 POI 选择能力
- 没有支付 SDK、订单后端、库存后端等真实服务对接
- 没有统一表单校验框架
- 没有 Toast、Dialog、BottomSheet 等显式公共交互组件封装
- 没有自动化测试、页面测试或验收脚本
- 没有公共 UI 组件目录或设计系统沉淀

## 9. 对 simApp 场景还原的直接含义

针对故障场景 spec 生成，默认应做如下判断：

- 不要再把当前仓库判断成“只有静态 Index demo 页”的旧基线。
- 如果场景涉及首页、搜索、结果列表、详情、下单、支付、订单、客服、我的等流程，优先检查现有 `Index.ets` 是否已具备相近交互。
- 如果场景只要求调整已有流程中的文案、状态切换、字段、卡片结构、排序筛选逻辑或订单流转，通常属于 `modify existing`。
- 如果场景要求真实路由、多文件页面、服务端数据、定位地图、登录鉴权、持久化或外部 SDK，对当前仓库通常仍属于 `new feature`。
- 只有当当前分支真实引入了相应能力，才可以把需求标记为 `already implemented`。

## 10. spec 生成时的推荐映射规则

在把场景需求映射到当前分支时，优先按以下思路判断：

1. 页面壳是否存在
   - 当前通常答案是“部分存在”，因为多业务屏已在 `Index.ets` 中实现。
2. 交互模式是否存在
   - 当前通常答案是“多数基础交互存在”，包括筛选、选择、下单、支付、订单查看。
3. 状态来源是否存在
   - 当前存在页面内本地状态和 mock 数据，但不存在真实后端数据源。
4. 路由链路是否存在
   - 当前只存在单文件内的屏幕状态切换，不存在正式业务路由体系。
5. UI 是否可直接复用
   - 当前大量业务卡片、表单块、列表块、底部 Tab 和详情区可作为复用基础，但通常需要在 `Index.ets` 内继续修改或拆分。

## 11. 基线更新触发条件

若当前分支后续发生以下变化，应同步更新本文档：

- 新增第二个及以上真实页面文件并接入路由
- `main_pages.json` 注册更多页面
- 引入 `router`、`NavPathStack` 或其他显式导航逻辑
- 拆分出公共组件目录、服务层、仓储层或状态管理层
- 接入真实网络请求、持久化存储或外部 SDK
- 增加登录、定位、地图、地址选择、支付、订单后端等真实业务能力
- 增加自动化测试脚本或页面级验收能力
