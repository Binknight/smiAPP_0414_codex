param(
    [ValidateSet('debug', 'release')]
    [string]$BuildMode = 'debug',

    [switch]$Clean,

    [string]$ConfigPath = ''
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Expand-EnvPath {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }
    [Environment]::ExpandEnvironmentVariables($Value.Trim())
}

function Get-BuildConfigPath {
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        return (Resolve-Path -LiteralPath $ConfigPath).Path
    }
    $local = Join-Path $projectRoot 'build_new.config.json'
    if (Test-Path -LiteralPath $local) {
        return (Resolve-Path -LiteralPath $local).Path
    }
    $example = Join-Path $projectRoot 'build_new.config.example.json'
    return (Resolve-Path -LiteralPath $example).Path
}

function Read-BuildConfig {
    $path = Get-BuildConfigPath
    $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $obj = $raw | ConvertFrom-Json

    $devEcoRoot = Expand-EnvPath $obj.devEcoStudioRoot
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

function Assert-PathExists {
    param(
        [string]$Path,
        [string]$Message
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw $Message
    }
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

$config = Read-BuildConfig
$devecoRoot = $config.DevEcoRoot
if ([string]::IsNullOrWhiteSpace($devecoRoot)) {
    throw 'devEcoStudioRoot is empty. Edit build_new.config.json (copy from build_new.config.example.json if needed).'
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
    throw 'compatSdkRoot is empty. Set it in build_new.config.json (e.g. under %LOCALAPPDATA%, not under the project .deveco-sdk folder).'
}

$compatSdkRoot = $config.CompatSdkRoot

Write-Host "Config file: $($config.ConfigPath)"
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
Ensure-HvigorPackages -ProjectRoot $projectRoot -DevEcoRoot $devecoRoot

$env:DEVECO_SDK_HOME = $compatSdkRoot
$env:PATH = "$jbrBin;$env:PATH"
$nodePathEntries = @(
    (Join-Path $projectRoot 'node_modules'),
    (Join-Path $devecoRoot 'tools\hvigor\hvigor\node_modules'),
    (Join-Path $devecoRoot 'tools\hvigor\hvigor-ohos-plugin\node_modules')
) | Where-Object { Test-Path -LiteralPath $_ }
$existingNodePathEntries = @()
if (-not [string]::IsNullOrWhiteSpace($env:NODE_PATH)) {
    $existingNodePathEntries = $env:NODE_PATH -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}
$env:NODE_PATH = (($nodePathEntries + $existingNodePathEntries) | Select-Object -Unique) -join ';'

Push-Location $projectRoot
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

    $outputDir = Join-Path $projectRoot 'entry\build\default\outputs\default'
    if (Test-Path -LiteralPath $outputDir) {
        Write-Host ''
        Write-Host "Build artifacts:"
        Get-ChildItem -LiteralPath $outputDir -Filter *.hap |
            Sort-Object LastWriteTime -Descending |
            ForEach-Object { Write-Host "  $($_.FullName)" }
    }
}
finally {
    Pop-Location
}
