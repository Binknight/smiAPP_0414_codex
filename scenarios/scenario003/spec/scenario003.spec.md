# SimApp 特定场景增量开发 Spec

## 1. Spec 元信息

- 场景来源：D:\13.simApp\0423\scenario3.json
- 输出文件：D:\13.simApp\0423\agentic-sim-app-starter\scenarios\scenario003\spec\scenario003.spec.md
- 目标 App / 业务域：general (通用类 APP)
- 仓库基线：main-refactor
- Spec 范围：搜索页面导航栏筛选功能
- 置信度：高

## 2. 场景摘要

### 2.1 原始问题描述

淘宝/华为商城"搜索页面导航栏筛选异常"

### 2.2 对应特定场景的摘要

针对通用类 APP 的搜索页面，实现导航栏中的多级别筛选功能，包括分类筛选和排序选项。

### 2.3 预期行为

用户进入搜索页面后，可以通过导航栏的筛选控件切换分类（全部、图书、数码、服装等）和排序方式（综合、销量、价格升序、价格降序），筛选结果实时更新展示。

## 3. 证据清单

### 3.1 JSON 证据

```json
{
  "question": "淘宝/华为商城\"搜索页面导航栏筛选异常\"",
  "exception": "",
  "exception_type": "云侧（大模型侧）故障",
  "exception_reason": "",
  "app": "general",
  "flow": "",
  "flow_reason": ""
}
```

### 3.2 截图证据

无（reserved / not implemented in this pass）

### 3.3 UTG 证据

无（reserved / not implemented in this pass）

### 3.4 信息缺口与歧义点

- 具体的筛选维度（除了分类和排序外是否还有其他筛选条件）
- 搜索关键词输入功能是否需要实现
- 筛选结果的展示形式（列表、网格、卡片等）

## 4. 重建后的产品流程

### 4.1 前置条件

- 应用已成功启动
- 主页面存在并可访问

### 4.2 页面序列

1. 首页 (Index) -> 点击进入 -> 2. 搜索页 (Search)

### 4.3 用户动作与系统响应

1. 用户点击进入搜索页面
2. 页面顶部显示筛选导航栏（Tab 形式）
3. 用户点击不同的分类 Tab（全部/图书/数码/服装/食品）
4. 页面底部商品列表根据筛选条件实时刷新
5. 用户切换排序方式（综合/销量/价格）
6. 列表排序实时更新

### 4.4 重点关注的触发点

- 导航栏 Tab 切换事件
- 筛选条件变更导致的列表刷新
- 排序方式变更导致的列表重新排序

## 5. UI / 页面设计规格

### 5.1 涉及页面

1. **Index.ets** - 首页（添加进入搜索页的入口）
2. **Search.ets** - 搜索页面（新增）

### 5.2 页面级布局与分区

**Search 页面布局**：
- 顶部搜索栏（固定）
  - 搜索输入框
  - 搜索按钮
- 导航栏分区（固定）
  - 分类 Tab 导航（横向滚动或固定显示）
  - 排序 Tab 导航
- 内容区域（可滚动）
  - 商品列表
  - 空状态提示

**Index 页面修改**：
- 在现有内容下方添加"进入搜索页"按钮

### 5.3 关键 UI 组件与状态

**SearchPage 组件**：

@State 状态：
- `selectedCategory: string = '全部'` - 当前选中的分类
- `sortBy: string = '综合'` - 当前选中的排序方式
- `searchKeyword: string = ''` - 搜索关键词
- `categories: string[] = ['全部', '图书', '数码', '服装', '食品']` - 分类列表
- `sortOptions: string[] = ['综合', '销量', '价格升序', '价格降序']` - 排序选项
- `products: ProductItem[] = []` - 商品列表数据

**ProductItem 接口**：
```typescript
interface ProductItem {
  id: string;
  name: string;
  price: number;
  sales: number;
  category: string;
  image?: string;
}
```

**关键交互**：
- CategoryTab 点击：切换到对应分类，过滤商品列表
- SortTab 点击：切换排序方式，重新排序商品列表
- 搜索按钮点击：根据关键词过滤列表（可扩展）

### 5.4 导航与路由规则

- 从 Index 页面跳转到 ProductSearch 页面
- 使用 `router.pushUrl()` 进行页面跳转
- 需要在 `main_pages.json` 中注册 Search 页面

### 5.5 状态与数据要求

- 数据源：使用 mock 数据（参见 mock-data 目录）
- 筛选逻辑：内存中过滤和排序
- 持久化：当前版本暂不实现记忆筛选条件

### 5.6 基于截图 / UTG 的 UI 精细化建模

reserved / not implemented in this pass

## 6. 框架差距分析

### 6.1 现有框架能力

- ArkUI 声明式布局
- 基础组件（Column, Row, Button, Text）
- List / Grid 列表组件
- @State 状态管理
- ForEach 列表渲染
- 页面注册机制

### 6.2 已实现需求

无（当前框架仅为 Demo 应用）

### 6.3 需要修改现有代码的需求

1. **main_pages.json** - 新增 Search 页面路由注册
2. **Index.ets** - 添加进入搜索页的入口按钮

### 6.4 需要新增实现的能力

1. **Search.ets** - 搜索页面实现
2. **models/** - 数据模型定义（可选，可内联）
3. **mock-data/** - 商品数据 JSON 文件

### 6.5 因场景信息缺失导致的阻塞项

无（核心功能可独立实现）

## 7. 增量开发计划

### 7.1 可能变更的文件或模块

- `scenarios/scenario003/entry/src/main/ets/pages/ProductSearchPage.ets` (新增)
- `scenarios/scenario003/entry/src/main/ets/pages/Index.ets` (修改)
- `scenarios/scenario003/entry/src/main/resources/base/profile/main_pages.json` (修改)
- `scenarios/scenario003/mock-data/products.json` (新增)

### 7.2 实现任务

**任务 1：注册 Search 页面路由**
- 编辑 main_pages.json
- 添加 `{ "name": "pages/Search", "path": "pages/Search" }`

**任务 2：创建 Search 页面**
- 创建 Search.ets 文件
- 实现搜索页面 UI 布局
- 实现 Tab 导航栏组件
- 实现商品列表展示
- 实现筛选排序逻辑

**任务 3：Index 页面添加入口**
- 修改 Index.ets
- 添加"进入搜索页"按钮

**任务 4：创建 Mock 数据**
- 创建 mock-data/products.json
- 包含 20-30 个模拟商品数据

**任务 5：构建验证**
- 执行构建脚本
- 验证 HAP 包生成

### 7.3 非目标项

- 不实现搜索输入功能
- 不实现商品详情页跳转
- 不实现持久化存储
- 不实现网络请求
- 不添加复杂动画效果

## 8. 测试策略

### 8.1 功能测试用例

1. 验证进入搜索页面时，默认显示"全部"分类和"综合"排序
2. 验证点击分类 Tab 能正确切换到对应分类
3. 验证商品列表仅显示符合当前分类的数据
4. 验证点击排序 Tab 能正确切换排序方式
5. 验证列表按价格升序/降序正确排序
6. 验证分类和排序可以组合筛选

### 8.2 UI / 交互验证

1. 验证导航栏 Tab 有明确的选中状态（颜色/下划线）
2. 验证列表项显示完整信息（名称、价格、销量）
3. 验证无数据时显示合理的空状态（如果有）

### 8.3 回归覆盖范围

1. 验证 Index 页面其他功能未受影响
2. 验证应用正常启动
3. 验证页面跳转流畅

## 9. 验收标准

- 标准 1：能成功构建并生成 HAP 包
- 标准 2：从首页可以正常跳转到搜索页面
- 标准 3：导航栏分类 Tab 可以点击并有选中状态
- 标准 4：切换分类后列表内容正确过滤
- 标准 5：切换排序后列表顺序正确更新
- 标准 6：所有 Mock 数据已落盘到 mock-data 目录

## 10. 假设与开放问题

### 假设

1. 假设筛选界面采用 Tab 形式展示分类
2. 假设商品列表采用 Grid 布局（2 列）
3. 假设商品数据包含：id, name, price, sales, category, image
4. 假设使用本地静态数据，不涉及网络请求

### 开放问题

1. 是否需要保留最近筛选条件（切换分类后保留之前的排序选择）
2. 是否需要下拉刷新功能
3. 是否需要加载更多功能（分页）
