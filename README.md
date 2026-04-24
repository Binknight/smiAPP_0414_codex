# HarmonyArkUIDemo

仓库现在采用多层工程结构：

- `apps/baseline/commonApp/`：通用基线工程，只保存可复用的基础版本
- `apps/baseline/travelApp/`：出行类 APP
- `apps/baseline/exploreApp/`：内容类 APP
- `apps/baseline/shoppingApp/`：购物类 APP
- `apps/baseline/deliveryApp/`：外卖类 APP
- `apps/scenarios/scenarioxxx/`：具体场景工程副本，每个目录独立保存 spec、mock、输出、日志和状态
- `scenarios/scenarioxxx/`：旧版场景工程目录（迁移过渡期保留）

## 构建

命令行构建入口统一为 `build/build.ps1`，必须显式指定目标工程：

```powershell
powershell -ExecutionPolicy Bypass -File .\build\build.ps1 -Target apps/baseline/commonApp
powershell -ExecutionPolicy Bypass -File .\build\build.ps1 -Target apps/baseline/travelApp
powershell -ExecutionPolicy Bypass -File .\build\build.ps1 -Target apps/baseline/exploreApp
powershell -ExecutionPolicy Bypass -File .\build\build.ps1 -Target apps/baseline/shoppingApp
powershell -ExecutionPolicy Bypass -File .\build\build.ps1 -Target apps/scenarios/scenario001
```

可选参数：

- `-Clean`
- `-BuildMode release`
- `-ConfigPath .\build\build.config.json`

构建脚本会：

- 优先读取 `build/build.config.json`，不存在时回退到 `build/build_new.config.json`，再回退到 `build/build.config.example.json`
- 将目标工程源码复制到 `tmp/<target>/`
- 将共享 `build/` 资源一并复制到同一个 `tmp/` 工作区
- 在 `tmp/` 工作区内执行 `hvigor assembleHap`
- 从 `tmp/<target>/entry/build/default/outputs/default/` 探测 `.hap` 产物

`build/build.bat` 只是对 `build.ps1` 的透传包装，因此同样支持 `-Target`。

## 场景流水线

自动化入口：

```powershell
python dev/scripts/run_pipeline.py --input scenario1.json
python dev/scripts/run_pipeline.py --input scenario1.json --no-web
python dev/scripts/run_pipeline.py --input scenario1.json --wait
```

当前行为：

- 脚本只会同步并切换到匹配的基线分支，不再创建新的场景分支
- 场景目录默认创建或复用为 `scenarios/scenarioxxx/`
- 运行态文件全部写入目标场景目录：
  - `spec/`
  - `mock-data/`
  - `output/`
  - `logs/`
  - `state/`
- 自动提交与推送目标为当前匹配分支，提交白名单按当前场景目录动态生成

## Web 控制台

`run_pipeline.py` 默认会启动本地 Web 控制台。控制台会扫描当前分支工作区中的：

- `apps/baseline/` 下的基线工程（`commonApp`、`travelApp`、`exploreApp` 等）
- `apps/scenarios/scenarioxxx`
- `scenarios/scenarioxxx`（旧版过渡目录）

页面支持切换查看不同 pipeline 的状态、日志、产物下载和终止动作。

## 目录约定

```text
apps/
  baseline/
    commonApp/
    travelApp/
    exploreApp/
    shoppingApp/
    deliveryApp/
  scenarios/
    scenario001/
      spec/
      mock-data/
      output/
      logs/
      state/
scenarios/
  scenario001/       (旧版过渡目录)
    spec/
    mock-data/
    output/
    logs/
    state/
build/
dev/
tmp/
```

## 配置

主配置文件为 `dev/config/pipeline.config.json`，重点字段：

- `paths.base_app_root`
- `paths.scenarios_root`
- `paths.build_root`
- `git.app_types`
- `agent.definitions`
- `scheduler`

首次使用时请复制 `build/build.config.example.json` 为 `build/build.config.json`。`devEcoStudioRoot` 默认通过环境变量 `DEVECO_STUDIO_ROOT` 注入，例如先执行 `$env:DEVECO_STUDIO_ROOT = 'C:\Program Files\Huawei\DevEco Studio'`，再运行构建脚本。

签名配置不再写死在 `build-profile.json5` 中。构建脚本会在复制到 `tmp/<target>/` 后，从以下环境变量注入签名字段：

- `OHOS_CERT_PATH`
- `OHOS_KEY_ALIAS`
- `OHOS_KEY_PASSWORD`
- `OHOS_PROFILE_PATH`
- `OHOS_SIGN_ALG`（可选，默认 `SHA256withECDSA`）
- `OHOS_STORE_FILE`
- `OHOS_STORE_PASSWORD`

PowerShell 示例：

```powershell
$env:OHOS_CERT_PATH = 'C:\Users\me\.ohos\config\default.cer'
$env:OHOS_KEY_ALIAS = 'debugKey'
$env:OHOS_KEY_PASSWORD = '***'
$env:OHOS_PROFILE_PATH = 'C:\Users\me\.ohos\config\default.p7b'
$env:OHOS_STORE_FILE = 'C:\Users\me\.ohos\config\default.p12'
$env:OHOS_STORE_PASSWORD = '***'
```

如果这些环境变量都未设置，构建脚本会保留模板占位值；如果只设置了一部分，则会直接报错，避免生成不完整的签名配置。