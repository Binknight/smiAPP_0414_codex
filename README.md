# HarmonyArkUIDemo

A simple HarmonyOS ArkUI (ArkTS) sample app with:

- A home screen header
- A button click counter
- A checklist with toggle state

## Files

- `AppScope/app.json5`: app-level metadata
- `entry/src/main/ets/pages/Index.ets`: main ArkUI page
- `entry/src/main/ets/entryability/EntryAbility.ets`: entry ability
- `entry/src/main/module.json5`: module config

## Run

1. Open `HarmonyArkUIDemo` in DevEco Studio.
2. Add or replace the signing files under `AppScope`:
   - `debug.p12`
   - `debug.cer`
   - `debug.p7b`
3. If your SDK version is not `5.0.0(12)`, update the root `build-profile.json5`.
4. Run on an emulator or device.

## Build Script

- Command line: `powershell -ExecutionPolicy Bypass -File .\build.ps1`
- Double click: `build.bat`
- Clean build: `powershell -ExecutionPolicy Bypass -File .\build.ps1 -Clean`
- Release mode: `powershell -ExecutionPolicy Bypass -File .\build.ps1 -BuildMode release`

The script automatically:

- uses DevEco Studio's bundled JDK
- creates the local `.deveco-sdk` compatibility mapping
- runs `hvigor assembleHap`
- writes HAP outputs to `entry\build\default\outputs\default`

## Next steps

- Add a second page and route navigation
- Integrate `@ohos.net.http`
- Persist data locally
https://contentcenter-vali-drcn.dbankcdn.cn/pvt_2/DeveloperAlliance_package_901_9/9b/v3/0fdyewgcSaSmJXn-PCNYXg/devecostudio-windows-6.0.1.251.zip?HW-CC-KV=V1&HW-CC-Date=20260414T125825Z&HW-CC-Expire=7200&HW-CC-Sign=1BD0E8F162D0324776A4246BB7E03D0F0BD790CE6D8F811A2CC4E70DACFACBF1
