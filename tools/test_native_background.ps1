param([string]$Device = 'emulator-5554', [string]$Version = '0.1.13')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path (Split-Path -Parent $projectRoot) '环境配置/启用开发环境.ps1')
$logPath = Join-Path $projectRoot "validation/tutorials-$Version-native-background.log"
Set-Content -LiteralPath $logPath -Value '' -Encoding utf8
$adbPath = (Get-Command adb).Source
$watcher = Start-Job -ArgumentList $adbPath,$Device,$logPath -ScriptBlock {
  param($adbPath, $deviceId, $logPath)
  function Wait-Marker([string]$marker) {
    $deadline = [DateTime]::UtcNow.AddSeconds(90)
    do {
      if ((Get-Content -LiteralPath $logPath -Raw) -match $marker) { return }
      Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Timed out waiting for $marker"
  }
  Wait-Marker 'QINBAN_NATIVE_BACKGROUND_READY'
  & $adbPath -s $deviceId shell input keyevent KEYCODE_HOME
  try {
    Wait-Marker 'QINBAN_NATIVE_BACKGROUND_CHECKED'
  } finally {
    $restoreOutput = & $adbPath -s $deviceId shell am start -n com.pianoforparkinson.piano_practice.validation/com.pianoforparkinson.piano_practice.MainActivity 2>&1
    $restoreExitCode = $LASTEXITCODE
    $restoreOutput | ForEach-Object { Write-Output "$_" }
    if ($restoreExitCode -ne 0) { throw "Unable to restore isolated app: $restoreExitCode" }
  }
}
try {
  Push-Location $projectRoot
  flutter test integration_test/native_background_test.dart -d $Device --dart-define=ISOLATED_TEST_PACKAGE=true --reporter expanded *> $logPath
  $testExitCode = $LASTEXITCODE
  if ($testExitCode -ne 0) { throw "Native background test exited $testExitCode" }
  Receive-Job -Job $watcher -Wait -ErrorAction Stop
} finally {
  Pop-Location
  Stop-Job -Job $watcher -ErrorAction SilentlyContinue
  Remove-Job -Job $watcher -Force
}
Get-Content -LiteralPath $logPath -Tail 12
