param(
    [string]$FlutterRoot = 'E:\mic\flutter\flutter',
    [string]$AndroidSdk = 'E:\android-toolchain\sdk',
    [string]$JavaRoot = 'E:\android-toolchain\jdk\jdk-17.0.20.1+1',
    [string]$GradleRoot = 'E:\android-toolchain\gradle\gradle-8.9',
    [string]$GradleCache = 'E:\android-toolchain\gradle-home',
    [string]$BuildDirectory = (Join-Path $env:TEMP ('youqi-build-' + [Guid]::NewGuid().ToString('N')))
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$versionMatch = [regex]::Match((Get-Content -LiteralPath (Join-Path $PSScriptRoot 'pubspec.yaml') -Raw -Encoding utf8), '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$')
if (-not $versionMatch.Success) { throw 'pubspec.yaml 缺少 version: x.y.z+build。' }
$appVersion = $versionMatch.Groups[1].Value
$appBuild = $versionMatch.Groups[2].Value
$delivery = Join-Path (Split-Path $PSScriptRoot -Parent) "installers\$appVersion"
$apkName = "Youqi-$appVersion-preview.apk"
$apk = Join-Path $delivery $apkName
if (Test-Path -LiteralPath $apk) { throw "该版本安装包已归档，请提升版本号后再构建：$apk" }
foreach ($toolPath in @($FlutterRoot, $AndroidSdk, $JavaRoot, $GradleRoot)) {
    if (-not (Test-Path -LiteralPath $toolPath)) { throw "工具路径不存在：$toolPath" }
}
$resolvedBuild = [System.IO.Path]::GetFullPath($BuildDirectory)
if ($resolvedBuild -match '[^\x00-\x7F]') { throw 'Flutter 3.24 的 Windows AOT 工具需要纯英文构建目录。请指定 -BuildDirectory。' }
if (Test-Path -LiteralPath $resolvedBuild) { throw "请使用一个新的构建目录，避免混入旧文件：$resolvedBuild" }
New-Item -ItemType Directory -Path $resolvedBuild | Out-Null
# Keep the Chinese source directory intact; the native AOT tools run from an ASCII copy.
& robocopy $PSScriptRoot $resolvedBuild /E /XD build .dart_tool .gradle screenshots /XF *.log /NFL /NDL /NJH /NJS /NP
if ($LASTEXITCODE -gt 7) { throw "复制源码失败：$LASTEXITCODE" }
$env:JAVA_HOME = $JavaRoot
$env:ANDROID_HOME = $AndroidSdk
$env:GRADLE_USER_HOME = $GradleCache
$localConfig = "sdk.dir=$($AndroidSdk.Replace('\','\\'))`nflutter.sdk=$($FlutterRoot.Replace('\','\\'))`nflutter.buildMode=release`nflutter.versionName=$appVersion`nflutter.versionCode=$appBuild`n"
[System.IO.File]::WriteAllText((Join-Path $resolvedBuild 'android\local.properties'), $localConfig, [System.Text.UTF8Encoding]::new($false))
Push-Location -LiteralPath $resolvedBuild
try {
    & (Join-Path $FlutterRoot 'bin\flutter.bat') pub get --offline
    if ($LASTEXITCODE -ne 0) { throw 'pub get 失败；首次使用可先在线获取 SDK 依赖。' }
    & (Join-Path $GradleRoot 'bin\gradle.bat') -p android assembleRelease testReleaseUnitTest lintRelease --console=plain
    if ($LASTEXITCODE -ne 0) { throw 'Android 构建或检查失败。' }
    New-Item -ItemType Directory -Path $delivery -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $resolvedBuild 'build\app\outputs\apk\release\app-release.apk') -Destination $apk
    $hash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
    [System.IO.File]::WriteAllText((Join-Path $delivery 'SHA256SUMS.txt'), "$hash  $apkName`n", [System.Text.UTF8Encoding]::new($false))
    Write-Output "安装包：$apk"
    Write-Output "构建与检查报告：$resolvedBuild\build\app\reports"
} finally { Pop-Location }
