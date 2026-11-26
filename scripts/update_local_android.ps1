param(
    [string]$ApkPath = (Join-Path $PSScriptRoot '../build/app/outputs/flutter-apk/app-debug.apk'),
    [string]$Device = 'emulator-5554',
    [switch]$NoLaunch
)
$ErrorActionPreference = 'Stop'
$expectedPackage = 'com.pianoforparkinson.piano_practice'
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT }
if (-not $sdk) { throw 'Set ANDROID_HOME before updating.' }
$adb = Join-Path $sdk 'platform-tools/adb.exe'
$buildTools = Get-ChildItem -LiteralPath (Join-Path $sdk 'build-tools') -Directory | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
$aapt = Join-Path $buildTools.FullName 'aapt.exe'
$apk = (Resolve-Path -LiteralPath $ApkPath).Path
$badging = & $aapt dump badging $apk
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect APK.' }
if (($badging -join "`n") -notmatch "package: name='$([regex]::Escape($expectedPackage))'") {
    throw 'Refusing a test APK or a different application. Build lib/main.dart first.'
}
$before = (& $adb -s $Device shell dumpsys package $expectedPackage) -join "`n"
$firstInstall = [regex]::Match($before, 'firstInstallTime=([^\r\n]+)').Groups[1].Value.Trim()
# Never fall back to uninstalling: a signing/version mismatch must stop here.
& $adb -s $Device install -r $apk
if ($LASTEXITCODE -ne 0) { throw 'Update failed. Existing app data was not removed.' }
$after = (& $adb -s $Device shell dumpsys package $expectedPackage) -join "`n"
$preserved = [regex]::Match($after, 'firstInstallTime=([^\r\n]+)').Groups[1].Value.Trim()
if ($firstInstall -and $preserved -ne $firstInstall) { throw 'Unexpected reinstall detected. Stop and inspect app data.' }
if (-not $NoLaunch) {
    & $adb -s $Device shell am start -n "$expectedPackage/.MainActivity"
    if ($LASTEXITCODE -ne 0) { throw 'Updated app could not be started.' }
}
Write-Output 'Update completed. Existing installation identity preserved.'
