param(
    [string]$TestPath = 'integration_test/training_configuration_test.dart',
    [string]$Device = 'emulator-5554',
    [string[]]$Defines = @('TRAINING_UI_TEST=true')
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {
    if ($Defines | Where-Object { $_ -match '^(ISOLATED_TEST_PACKAGE|DANCE_FLOW_TEST_PACKAGE)=' }) { throw 'Package identity defines are managed by this script.' }
    $defineArgs = @('--dart-define=ISOLATED_TEST_PACKAGE=true') + @($Defines | ForEach-Object { "--dart-define=$_" })
    $sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT }
    if (-not $sdk) { throw 'Set ANDROID_HOME before testing.' }
    $adb = Join-Path $sdk 'platform-tools/adb.exe'
    $mainPackage = 'com.pianoforparkinson.piano_practice'
    $before = (& $adb -s $Device shell dumpsys package $mainPackage) -join "`n"
    $firstInstall = [regex]::Match($before, 'firstInstallTime=([^\r\n]+)').Groups[1].Value.Trim()
    # Flutter caches the APK identity BEFORE rebuilding the test. Prebuild the
    # isolated APK so a previous main APK cannot become its cleanup target.
    & flutter build apk --debug --no-pub --target-platform android-x64 --target $TestPath @defineArgs
    if ($LASTEXITCODE -ne 0) { throw 'Isolated test build failed.' }
    $buildTools = Get-ChildItem -LiteralPath (Join-Path $sdk 'build-tools') -Directory | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    $aapt = Join-Path $buildTools.FullName 'aapt.exe'
    $badging = & $aapt dump badging 'build/app/outputs/flutter-apk/app-debug.apk'
    if ($LASTEXITCODE -ne 0 -or ($badging -join "`n") -notmatch "package: name='com\.pianoforparkinson\.piano_practice\.validation'") { throw 'Test APK identity is not isolated.' }
    & flutter test $TestPath -d $Device --no-pub --no-uninstall @defineArgs
    if ($LASTEXITCODE -ne 0) { throw 'Device tests failed.' }
    $after = (& $adb -s $Device shell dumpsys package $mainPackage) -join "`n"
    $preserved = [regex]::Match($after, 'firstInstallTime=([^\r\n]+)').Groups[1].Value.Trim()
    if ($firstInstall -and $preserved -ne $firstInstall) { throw 'Main installation changed during isolated testing.' }
    Write-Output 'Device tests completed. Main installation identity preserved.'
} finally { Pop-Location }
