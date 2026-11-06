$ErrorActionPreference = 'Stop'
$app = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$classes = Join-Path $app '.dart_tool/capture-namespace-java-test'
New-Item -ItemType Directory -Force -Path $classes | Out-Null
& javac -d $classes (Join-Path $app 'android/app/src/main/java/com/pianoforparkinson/piano_practice/CaptureNamespaceMigration.java') (Join-Path $app 'android/app/src/test/java/com/pianoforparkinson/piano_practice/CaptureNamespaceMigrationTest.java')
if ($LASTEXITCODE) { throw 'Capture namespace compilation failed' }
& java -cp $classes com.pianoforparkinson.piano_practice.CaptureNamespaceMigrationTest
if ($LASTEXITCODE) { throw 'Capture namespace file regression failed' }
