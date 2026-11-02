param([string]$Device='emulator-5554')
$ErrorActionPreference='Stop'
$pianoProject=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $pianoProject
try {
    # Build first, then pass a fixed APK path. Flutter can otherwise inspect a
    # stale APK before rebuilding and uninstall the previously cached package.
    flutter build apk --debug --target=integration_test/dance_three_parts_test.dart --dart-define=DANCE_FLOW_TEST_PACKAGE=true
    if($LASTEXITCODE -ne 0){throw 'QA build failed'}
    $pianoMetadata=Get-Content 'build/app/outputs/apk/debug/output-metadata.json' -Raw | ConvertFrom-Json
    if($pianoMetadata.applicationId -ne 'com.pianoforparkinson.piano_practice.dance_flow_test') {throw 'Unexpected package; refusing to run'}
    $pianoQaBinary=Join-Path $pianoProject 'build/dance-three-parts-qa.apk'
    Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-debug.apk' -Destination $pianoQaBinary -Force
    flutter drive --driver=test_driver/dance_screenshots.dart --target=integration_test/dance_three_parts_test.dart --use-application-binary=$pianoQaBinary -d $Device
    if($LASTEXITCODE -ne 0){throw 'QA drive failed'}
} finally { Pop-Location }
