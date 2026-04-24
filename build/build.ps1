param(
    [ValidateSet('debug', 'release')]
    [string]$BuildMode = 'debug',

    [switch]$Clean,

    [string]$ConfigPath = '',

    [string]$Target = 'apps/baseline/commonApp'
)

$ErrorActionPreference = 'Stop'

$buildScriptPath = (Resolve-Path -LiteralPath $MyInvocation.MyCommand.Path).Path
$buildDir = Split-Path -Parent $buildScriptPath
$projectRoot = (Resolve-Path (Join-Path $buildDir '..')).Path

function Expand-EnvPath {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }
    [Environment]::ExpandEnvironmentVariables($Value.Trim())
}

function Assert-PathExists {
    param(
        [string]$Path,
        [string]$Message
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw $Message
    }
}

function Get-BuildConfigPath {
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        return (Resolve-Path -LiteralPath $ConfigPath).Path
    }

    $preferredLocal = Join-Path $buildDir 'build.config.json'
    if (Test-Path -LiteralPath $preferredLocal) {
        return (Resolve-Path -LiteralPath $preferredLocal).Path
    }

    $legacyLocal = Join-Path $buildDir 'build_new.config.json'
    if (Test-Path -LiteralPath $legacyLocal) {
        return (Resolve-Path -LiteralPath $legacyLocal).Path
    }

    $preferredExample = Join-Path $buildDir 'build.config.example.json'
    if (Test-Path -LiteralPath $preferredExample) {
        return (Resolve-Path -LiteralPath $preferredExample).Path
    }

    $legacyExample = Join-Path $buildDir 'build_new.config.example.json'
    return (Resolve-Path -LiteralPath $legacyExample).Path
}

function Read-BuildConfig {
    $path = Get-BuildConfigPath
    $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $obj = $raw | ConvertFrom-Json

    $devEcoRoot = Expand-EnvPath $obj.devEcoStudioRoot
    if ([string]::IsNullOrWhiteSpace($devEcoRoot) -and -not [string]::IsNullOrWhiteSpace($env:DEVECO_STUDIO_ROOT)) {
        $devEcoRoot = Expand-EnvPath $env:DEVECO_STUDIO_ROOT
    }
    $sdkRel = if ($obj.PSObject.Properties['sdkRelativePath']) { $obj.sdkRelativePath } else { 'sdk\default' }
    $compatRoot = Expand-EnvPath $obj.compatSdkRoot
    $hvigorPath = $null
    if ($obj.PSObject.Properties['hvigorJsPath'] -and $null -ne $obj.hvigorJsPath) {
        $hvigorPath = Expand-EnvPath ([string]$obj.hvigorJsPath)
        if ([string]::IsNullOrWhiteSpace($hvigorPath)) {
            $hvigorPath = $null
        }
    }

    [pscustomobject]@{
        ConfigPath       = $path
        DevEcoRoot       = $devEcoRoot
        SdkRelativePath  = $sdkRel
        CompatSdkRoot    = $compatRoot
        HvigorJsPath     = $hvigorPath
        SdkPkg           = $obj.sdkPkg
    }
}

function Find-HvigorJs {
    $explicit = $env:HVIGOR_JS
    if (-not [string]::IsNullOrWhiteSpace($explicit) -and (Test-Path -LiteralPath $explicit)) {
        return $explicit
    }

    $cachesRoot = Join-Path $env:USERPROFILE '.hvigor\project_caches'
    if (-not (Test-Path -LiteralPath $cachesRoot)) {
        return $null
    }

    foreach ($dir in Get-ChildItem -LiteralPath $cachesRoot -Directory -ErrorAction SilentlyContinue) {
        $candidate = Join-Path $dir.FullName 'workspace\node_modules\@ohos\hvigor\bin\hvigor.js'
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    return $null
}

function Build-SdkPkgJson {
    param(
        [object]$SdkPkg
    )

    $api = '22'
    $display = 'HarmonyOS 6.0.2'
    $platformVer = '6.0.2'
    $ver = '6.0.2.130'
    $releaseType = 'Release'
    $stage = 'Release'

    if ($null -ne $SdkPkg) {
        if ($SdkPkg.PSObject.Properties['apiVersion']) { $api = [string]$SdkPkg.apiVersion }
        if ($SdkPkg.PSObject.Properties['displayName']) { $display = [string]$SdkPkg.displayName }
        if ($SdkPkg.PSObject.Properties['platformVersion']) { $platformVer = [string]$SdkPkg.platformVersion }
        if ($SdkPkg.PSObject.Properties['version']) { $ver = [string]$SdkPkg.version }
        if ($SdkPkg.PSObject.Properties['releaseType']) { $releaseType = [string]$SdkPkg.releaseType }
        if ($SdkPkg.PSObject.Properties['stage']) { $stage = [string]$SdkPkg.stage }
    }

    $o = [ordered]@{
        meta = @{ version = '1.0.0' }
        data = [ordered]@{
            apiVersion      = $api
            displayName     = $display
            path            = 'platform'
            platformVersion = $platformVer
            releaseType     = $releaseType
            version         = $ver
            stage           = $stage
        }
    }
    return ($o | ConvertTo-Json -Depth 5 -Compress)
}

function Ensure-CompatSdk {
    param(
        [string]$CompatSdkRoot,
        [string]$OpenharmonyTarget,
        [string]$HmsTarget,
        [string]$SdkPkgJson
    )

    $compatPlatformRoot = Join-Path $CompatSdkRoot 'platform'
    New-Item -ItemType Directory -Force -Path $compatPlatformRoot | Out-Null

    $compatSdkPkg = Join-Path $compatPlatformRoot 'sdk-pkg.json'
    $needsWrite = $true
    if (Test-Path -LiteralPath $compatSdkPkg) {
        $existingSdkPkg = Get-Content -LiteralPath $compatSdkPkg -Raw -Encoding UTF8
        if ($existingSdkPkg -eq $SdkPkgJson) {
            $needsWrite = $false
        }
    }

    if ($needsWrite) {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        try {
            [System.IO.File]::WriteAllText($compatSdkPkg, $SdkPkgJson, $utf8NoBom)
        }
        catch {
            $existingSdkPkg = $null
            if (Test-Path -LiteralPath $compatSdkPkg) {
                try {
                    $existingSdkPkg = Get-Content -LiteralPath $compatSdkPkg -Raw -Encoding UTF8
                }
                catch {
                }
            }

            if ($existingSdkPkg -ne $SdkPkgJson) {
                throw "Failed to update '$compatSdkPkg'. Close DevEco Studio or other processes using the compat SDK, then retry. Original error: $($_.Exception.Message)"
            }
        }
    }

    $junctions = @(
        @{ Link = (Join-Path $compatPlatformRoot 'openharmony'); Target = $OpenharmonyTarget },
        @{ Link = (Join-Path $compatPlatformRoot 'hms'); Target = $HmsTarget }
    )

    foreach ($item in $junctions) {
        if (Test-Path -LiteralPath $item.Link) {
            $linkItem = Get-Item -LiteralPath $item.Link
            $currentTarget = $null
            if ($linkItem.LinkType -eq 'Junction') {
                $currentTarget = @($linkItem.Target)[0]
            }

            if ($currentTarget -ne $item.Target) {
                Remove-Item -LiteralPath $item.Link -Force
                New-Item -ItemType Junction -Path $item.Link -Target $item.Target | Out-Null
            }
        }
        else {
            New-Item -ItemType Junction -Path $item.Link -Target $item.Target | Out-Null
        }
    }
}

function Ensure-HvigorPackages {
    param(
        [string]$ProjectRoot,
        [string]$DevEcoRoot
    )

    $scopedRoot = Join-Path $ProjectRoot 'node_modules\@ohos'
    New-Item -ItemType Directory -Force -Path $scopedRoot | Out-Null

    $packages = @(
        @{
            Link = (Join-Path $scopedRoot 'hvigor')
            Target = (Join-Path $DevEcoRoot 'tools\hvigor\hvigor')
        },
        @{
            Link = (Join-Path $scopedRoot 'hvigor-ohos-plugin')
            Target = (Join-Path $DevEcoRoot 'tools\hvigor\hvigor-ohos-plugin')
        }
    )

    foreach ($item in $packages) {
        Assert-PathExists -Path $item.Target -Message "Required hvigor package not found: $($item.Target)"

        if (Test-Path -LiteralPath $item.Link) {
            $linkItem = Get-Item -LiteralPath $item.Link
            $currentTarget = $null
            if ($linkItem.LinkType -eq 'Junction') {
                $currentTarget = @($linkItem.Target)[0]
            }

            if ($currentTarget -ne $item.Target) {
                Remove-Item -LiteralPath $item.Link -Force -Recurse
                New-Item -ItemType Junction -Path $item.Link -Target $item.Target | Out-Null
            }
        }
        else {
            New-Item -ItemType Junction -Path $item.Link -Target $item.Target | Out-Null
        }
    }
}

function Get-TargetInfo {
    param([string]$RawTarget)

    $normalized = $RawTarget.Replace('/', '\').Trim('\')
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        throw 'Target is empty. Use -Target apps/baseline/commonApp (or apps/baseline/travelApp, apps/baseline/exploreApp, etc.) or -Target apps/scenarios/scenario001.'
    }

    $targetPath = Join-Path $projectRoot $normalized
    Assert-PathExists -Path $targetPath -Message "Target project not found: $targetPath"

    $entryDir = Join-Path $targetPath 'entry'
    Assert-PathExists -Path $entryDir -Message "Target project is missing entry directory: $targetPath"

    $safeName = ($normalized -replace '[\\/]+', '-').ToLowerInvariant()
    $workspaceRoot = Join-Path $projectRoot 'tmp'
    $workspacePath = Join-Path $workspaceRoot $safeName

    [pscustomobject]@{
        TargetArg       = $RawTarget
        TargetRelative  = $normalized
        TargetPath      = (Resolve-Path -LiteralPath $targetPath).Path
        WorkspacePath   = $workspacePath
        WorkspaceTarget = $workspacePath
        OutputDir       = (Join-Path $workspacePath 'entry\build\default\outputs\default')
    }
}

function Copy-Workspace {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (Test-Path -LiteralPath $Destination) {
        cmd /c "rmdir /s /q `"$Destination`"" 2>$null
    }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null

    $excludeNames = @('build', '.hvigor', 'node_modules', 'oh_modules')
    Get-ChildItem -LiteralPath $Source -Force | Where-Object {
        $excludeNames -notcontains $_.Name
    } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }

    $pruneNames = @('build', '.hvigor')
    foreach ($name in $pruneNames) {
        Get-ChildItem -LiteralPath $Destination -Directory -Recurse -Filter $name -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function ConvertTo-JsonStringLiteral {
    param([string]$Value)

    return ($Value | ConvertTo-Json -Compress)
}

function Update-BuildProfileSigningFromEnv {
    param([string]$ProjectRoot)

    $buildProfilePath = Join-Path $ProjectRoot 'build-profile.json5'
    if (-not (Test-Path -LiteralPath $buildProfilePath)) {
        return
    }

    $envMap = [ordered]@{
        '__OHOS_CERT_PATH__'      = [Environment]::GetEnvironmentVariable('OHOS_CERT_PATH')
        '__OHOS_KEY_ALIAS__'      = [Environment]::GetEnvironmentVariable('OHOS_KEY_ALIAS')
        '__OHOS_KEY_PASSWORD__'   = [Environment]::GetEnvironmentVariable('OHOS_KEY_PASSWORD')
        '__OHOS_PROFILE_PATH__'   = [Environment]::GetEnvironmentVariable('OHOS_PROFILE_PATH')
        '__OHOS_SIGN_ALG__'       = [Environment]::GetEnvironmentVariable('OHOS_SIGN_ALG')
        '__OHOS_STORE_FILE__'     = [Environment]::GetEnvironmentVariable('OHOS_STORE_FILE')
        '__OHOS_STORE_PASSWORD__' = [Environment]::GetEnvironmentVariable('OHOS_STORE_PASSWORD')
    }

    $requiredEnvNames = @(
        'OHOS_CERT_PATH',
        'OHOS_KEY_ALIAS',
        'OHOS_KEY_PASSWORD',
        'OHOS_PROFILE_PATH',
        'OHOS_STORE_FILE',
        'OHOS_STORE_PASSWORD'
    )

    $hasSigningEnv = $false
    foreach ($name in $requiredEnvNames) {
        if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
            $hasSigningEnv = $true
            break
        }
    }

    if (-not $hasSigningEnv -and [string]::IsNullOrWhiteSpace($envMap['__OHOS_SIGN_ALG__'])) {
        Write-Host "Signing env vars not set; keeping template signing config in $buildProfilePath"
        return
    }

    $missingEnvNames = @()
    foreach ($name in $requiredEnvNames) {
        if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
            $missingEnvNames += $name
        }
    }

    if ($missingEnvNames.Count -gt 0) {
        throw "Signing env vars are incomplete. Missing: $($missingEnvNames -join ', ')"
    }

    if ([string]::IsNullOrWhiteSpace($envMap['__OHOS_SIGN_ALG__'])) {
        $envMap['__OHOS_SIGN_ALG__'] = 'SHA256withECDSA'
    }

    $template = Get-Content -LiteralPath $buildProfilePath -Raw -Encoding UTF8
    foreach ($token in $envMap.Keys) {
        $template = $template.Replace("`"$token`"", (ConvertTo-JsonStringLiteral $envMap[$token]))
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($buildProfilePath, $template, $utf8NoBom)
    Write-Host "Injected signing config into $buildProfilePath from environment variables."
}

$targetInfo = Get-TargetInfo -RawTarget $Target
$config = Read-BuildConfig
$devecoRoot = $config.DevEcoRoot
if ([string]::IsNullOrWhiteSpace($devecoRoot) -or $devecoRoot -match '%[^%]+%') {
    throw 'devEcoStudioRoot is empty or unresolved. Set env DEVECO_STUDIO_ROOT, or edit build/build.config.json (copy from build/build.config.example.json if needed).'
}

$sdkRoot = Join-Path $devecoRoot $config.SdkRelativePath
$jbrBin = Join-Path $devecoRoot 'jbr\bin'
$openharmonyTarget = Join-Path $sdkRoot 'openharmony'
$hmsTarget = Join-Path $sdkRoot 'hms'

$hvigorEntry = $config.HvigorJsPath
if ([string]::IsNullOrWhiteSpace($hvigorEntry)) {
    $hvigorEntry = Find-HvigorJs
}

if ([string]::IsNullOrWhiteSpace($config.CompatSdkRoot)) {
    throw 'compatSdkRoot is empty. Set it in build/build.config.json (e.g. under %LOCALAPPDATA%, not under the project .deveco-sdk folder).'
}

$compatSdkRoot = $config.CompatSdkRoot

Write-Host "Config file: $($config.ConfigPath)"
Write-Host "Build target: $($targetInfo.TargetRelative)"
Write-Host "Workspace: $($targetInfo.WorkspacePath)"
Write-Host "DEVECO_SDK_HOME -> $compatSdkRoot"

Assert-PathExists -Path $devecoRoot -Message "DevEco Studio not found: $devecoRoot"
Assert-PathExists -Path $sdkRoot -Message "Harmony SDK not found: $sdkRoot"
Assert-PathExists -Path $jbrBin -Message "Bundled JDK not found: $jbrBin"
if ([string]::IsNullOrWhiteSpace($hvigorEntry)) {
    throw 'hvigor.js not found. Set hvigorJsPath in config, or env HVIGOR_JS, or open this project once in DevEco to populate .hvigor cache.'
}
Assert-PathExists -Path $hvigorEntry -Message "hvigor entry not found: $hvigorEntry"
Assert-PathExists -Path $openharmonyTarget -Message "openharmony SDK not found: $openharmonyTarget"
Assert-PathExists -Path $hmsTarget -Message "hms SDK not found: $hmsTarget"

$sdkPkgJson = Build-SdkPkgJson -SdkPkg $config.SdkPkg
Ensure-CompatSdk -CompatSdkRoot $compatSdkRoot -OpenharmonyTarget $openharmonyTarget -HmsTarget $hmsTarget -SdkPkgJson $sdkPkgJson

Copy-Workspace -Source $targetInfo.TargetPath -Destination $targetInfo.WorkspaceTarget
Update-BuildProfileSigningFromEnv -ProjectRoot $targetInfo.WorkspaceTarget
Copy-Workspace -Source $buildDir -Destination (Join-Path $targetInfo.WorkspacePath 'build')
Ensure-HvigorPackages -ProjectRoot $targetInfo.WorkspacePath -DevEcoRoot $devecoRoot

$env:DEVECO_SDK_HOME = $compatSdkRoot
$env:PATH = "$jbrBin;$env:PATH"
$nodePathEntries = @(
    (Join-Path $targetInfo.WorkspacePath 'node_modules'),
    (Join-Path $devecoRoot 'tools\hvigor\hvigor\node_modules'),
    (Join-Path $devecoRoot 'tools\hvigor\hvigor-ohos-plugin\node_modules')
) | Where-Object { Test-Path -LiteralPath $_ }
$existingNodePathEntries = @()
if (-not [string]::IsNullOrWhiteSpace($env:NODE_PATH)) {
    $existingNodePathEntries = $env:NODE_PATH -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}
$env:NODE_PATH = (($nodePathEntries + $existingNodePathEntries) | Select-Object -Unique) -join ';'

Push-Location $targetInfo.WorkspacePath
try {
    if ($Clean) {
        node $hvigorEntry clean --no-daemon
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    }

    node $hvigorEntry assembleHap -p enableSignTask=false -p buildMode=$BuildMode --no-daemon --stacktrace
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    if (Test-Path -LiteralPath $targetInfo.OutputDir) {
        Write-Host ''
        Write-Host "Build artifacts:"
        Get-ChildItem -LiteralPath $targetInfo.OutputDir -Filter *.hap |
            Sort-Object LastWriteTime -Descending |
            ForEach-Object { Write-Host "  $($_.FullName)" }
    }
}
finally {
    Pop-Location
}
