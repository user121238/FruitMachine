# ==============================================================================
# 水果机 APK 一键构建脚本
# 1. 自动同步根目录 index.html 到 android/assets/index.html
# 2. 拷贝至纯 ASCII 临时目录避免 aapt2 中文路径问题
# 3. 完成 compile -> link -> javac -> d8 -> zipalign -> apksigner
# 4. 输出最新的 "水果大满贯.apk" 到当前工程根目录
# ==============================================================================

[CmdletBinding()]
param(
    [string]$SdkPath = $env:ANDROID_HOME,
    [string]$BuildToolsVersion = "35.0.0",
    [string]$PlatformApi = "35"
)

$ErrorActionPreference = "Stop"
$ProjectDir = $PSScriptRoot

if (-not $SdkPath) {
    if (Test-Path "D:\Android\android-sdk") {
        $SdkPath = "D:\Android\android-sdk"
    } elseif (Test-Path "$env:LOCALAPPDATA\Android\Sdk") {
        $SdkPath = "$env:LOCALAPPDATA\Android\Sdk"
    } else {
        throw "未找到 Android SDK 路径，请设置 ANDROID_HOME 环境变量或通过 -SdkPath 参数传入。"
    }
}

$BuildToolsDir = Join-Path $SdkPath "build-tools\$BuildToolsVersion"
$AndroidJar = Join-Path $SdkPath "platforms\android-$PlatformApi\android.jar"

if (-not (Test-Path $BuildToolsDir)) {
    throw "未找到 build-tools 目录: $BuildToolsDir"
}
if (-not (Test-Path $AndroidJar)) {
    throw "未找到 android.jar: $AndroidJar"
}

$Aapt2 = Join-Path $BuildToolsDir "aapt2.exe"
$Zipalign = Join-Path $BuildToolsDir "zipalign.exe"
$ApkSigner = Join-Path $BuildToolsDir "apksigner.bat"
$D8 = Join-Path $BuildToolsDir "d8.bat"

Write-Host ">>> [1/6] 检查与同步资产文件..." -ForegroundColor Cyan
Copy-Item (Join-Path $ProjectDir "index.html") (Join-Path $ProjectDir "android\assets\index.html") -Force
Write-Host "  [OK] index.html 已同步至 android/assets/index.html" -ForegroundColor Green
if (Test-Path (Join-Path $ProjectDir "cabinet.html")) {
    Copy-Item (Join-Path $ProjectDir "cabinet.html") (Join-Path $ProjectDir "android\assets\cabinet.html") -Force
    Write-Host "  [OK] cabinet.html (竖版机台) 已同步至 android/assets/cabinet.html" -ForegroundColor Green
}
if (Test-Path (Join-Path $ProjectDir "images.js")) {
    Copy-Item (Join-Path $ProjectDir "images.js") (Join-Path $ProjectDir "android\assets\images.js") -Force
    Write-Host "  [OK] images.js 已同步至 android/assets/images.js" -ForegroundColor Green
}
if (Test-Path (Join-Path $ProjectDir "images")) {
    Copy-Item (Join-Path $ProjectDir "images") (Join-Path $ProjectDir "android\assets\images") -Recurse -Force
    Write-Host "  [OK] images 目录已同步至 android/assets/images" -ForegroundColor Green
}

Write-Host ">>> [2/6] 准备纯 ASCII 临时构建目录..." -ForegroundColor Cyan
$TempBuildDir = Join-Path $env:TEMP "fruit-slot-build"
if (Test-Path $TempBuildDir) {
    Remove-Item $TempBuildDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempBuildDir | Out-Null
Copy-Item -Path (Join-Path $ProjectDir "android\*") -Destination $TempBuildDir -Recurse -Force

$KeystoreSrc = Join-Path $ProjectDir "fruit-release.jks"
$KeystoreDst = Join-Path $TempBuildDir "fruit-release.jks"
Copy-Item $KeystoreSrc $KeystoreDst -Force

$BuildWorkDir = Join-Path $TempBuildDir "build"
$GenDir = Join-Path $BuildWorkDir "gen"
$ClassesDir = Join-Path $BuildWorkDir "classes"
New-Item -ItemType Directory -Path $GenDir -Force | Out-Null
New-Item -ItemType Directory -Path $ClassesDir -Force | Out-Null

Push-Location $TempBuildDir
try {
    Write-Host ">>> [3/6] aapt2 编译与链接资源..." -ForegroundColor Cyan
    & $Aapt2 compile --dir res -o "$BuildWorkDir\res.zip"
    if ($LASTEXITCODE -ne 0) { throw "aapt2 compile 失败" }

    & $Aapt2 link -o "$BuildWorkDir\base.apk" `
        -I $AndroidJar `
        --manifest AndroidManifest.xml `
        -A assets `
        --java $GenDir `
        --min-sdk-version 21 `
        --target-sdk-version 35 `
        "$BuildWorkDir\res.zip"
    if ($LASTEXITCODE -ne 0) { throw "aapt2 link 失败" }

    Write-Host ">>> [4/6] 编译 Java 源码与 D8 字节码打包..." -ForegroundColor Cyan
    $JavaFiles = Get-ChildItem -Path $GenDir, (Join-Path $TempBuildDir "java") -Filter "*.java" -Recurse | Select-Object -ExpandProperty FullName
    javac -encoding UTF-8 -source 8 -target 8 -bootclasspath $AndroidJar -d $ClassesDir $JavaFiles
    if ($LASTEXITCODE -ne 0) { throw "javac 失败" }

    $ClassFiles = Get-ChildItem -Path $ClassesDir -Filter "*.class" -Recurse | Select-Object -ExpandProperty FullName
    cmd.exe /c "$D8 --release --lib `"$AndroidJar`" --min-api 21 --output `"$BuildWorkDir`" $($ClassFiles -join ' ')"
    if ($LASTEXITCODE -ne 0) { throw "d8 失败" }

    # 将 classes.dex 注入 base.apk
    python -c "import zipfile; z = zipfile.ZipFile(r'$BuildWorkDir\base.apk', 'a'); z.write(r'$BuildWorkDir\classes.dex', 'classes.dex'); z.close()"
    if ($LASTEXITCODE -ne 0) { throw "合并 classes.dex 到 base.apk 失败" }

    Write-Host ">>> [5/6] 对齐 (zipalign) 与签名 (apksigner)..." -ForegroundColor Cyan
    $AlignedApk = Join-Path $BuildWorkDir "aligned.apk"
    & $Zipalign -f 4 "$BuildWorkDir\base.apk" $AlignedApk
    if ($LASTEXITCODE -ne 0) { throw "zipalign 失败" }

    # 提取版本号与格式化时间戳
    $ManifestContent = Get-Content (Join-Path $ProjectDir "android\AndroidManifest.xml") -Raw
    $VersionName = "1.0"
    if ($ManifestContent -match 'android:versionName="([^"]+)"') {
        $VersionName = $matches[1]
    }
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $VersionedApkName = "水果大满贯_v${VersionName}_${Timestamp}.apk"
    $FinalApk = Join-Path $ProjectDir $VersionedApkName
    $DefaultApk = Join-Path $ProjectDir "水果大满贯.apk"

    cmd.exe /c "$ApkSigner sign --ks `"$KeystoreDst`" --ks-pass pass:fruit2026 --ks-key-alias fruit --key-pass pass:fruit2026 --out `"$FinalApk`" `"$AlignedApk`""
    if ($LASTEXITCODE -ne 0) { throw "apksigner 失败" }

    # 同时更新通用的 水果大满贯.apk，保证固定路径与脚本的向后兼容
    Copy-Item $FinalApk $DefaultApk -Force

    Write-Host ">>> [6/6] 验证 APK 签名..." -ForegroundColor Cyan
    cmd.exe /c "$ApkSigner verify --verbose `"$FinalApk`""
    if ($LASTEXITCODE -ne 0) { throw "APK 验证失败" }

    Write-Host "`n========================================================" -ForegroundColor Green
    Write-Host "  [SUCCESS] APK 构建成功！" -ForegroundColor Green
    Write-Host "  版本输出: $FinalApk" -ForegroundColor Green
    Write-Host "  通用输出: $DefaultApk" -ForegroundColor Green
    Write-Host "  文件大小: $((Get-Item $FinalApk).Length) 字节" -ForegroundColor Green
    Write-Host "========================================================`n" -ForegroundColor Green
} finally {
    Pop-Location
    if (Test-Path $TempBuildDir) {
        Remove-Item $TempBuildDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
