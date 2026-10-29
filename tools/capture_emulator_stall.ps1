param([string]$Device='emulator-5554')
$projectPath = Split-Path -Parent $PSScriptRoot
. (Join-Path (Split-Path -Parent $projectPath) '环境配置/启用开发环境.ps1')
$capturePath = Join-Path $projectPath ('validation/emulator-stall-' + (Get-Date -Format yyyyMMdd-HHmmss))
New-Item -ItemType Directory -Path $capturePath -ErrorAction Stop | Out-Null
Get-CimInstance Win32_Process | Where-Object {$_.Name -match 'qemu|emulator'} | Select-Object ProcessId,Name,CommandLine | Format-List | Out-File (Join-Path $capturePath 'host-processes.txt')
Get-CimInstance Win32_OperatingSystem | Select-Object TotalVisibleMemorySize,FreePhysicalMemory | Format-List | Out-File (Join-Path $capturePath 'host-memory.txt')
Get-WinEvent -FilterHashtable @{LogName='Application';Id=1000,1002;StartTime=(Get-Date).AddHours(-3)} -ErrorAction SilentlyContinue | Where-Object {$_.Message -match 'qemu|emulator'} | Select-Object TimeCreated,Message | Format-List | Out-File (Join-Path $capturePath 'host-faults.txt')
adb -s $Device shell dumpsys SurfaceFlinger --list | Out-File (Join-Path $capturePath 'surfaces.txt')
adb -s $Device shell dumpsys SurfaceFlinger --latency | Out-File (Join-Path $capturePath 'display-timing.txt')
adb -s $Device shell dumpsys gfxinfo com.pianoforparkinson.piano_practice framestats | Out-File (Join-Path $capturePath 'release-frames.txt')
adb -s $Device shell dumpsys gfxinfo com.pianoforparkinson.piano_practice.validation framestats | Out-File (Join-Path $capturePath 'test-frames.txt')
adb -s $Device shell dumpsys activity exit-info com.pianoforparkinson.piano_practice | Out-File (Join-Path $capturePath 'app-exit-info.txt')
adb -s $Device shell dumpsys cpuinfo | Out-File (Join-Path $capturePath 'guest-cpu.txt')
adb -s $Device shell cat /proc/meminfo | Out-File (Join-Path $capturePath 'guest-memory.txt')
adb -s $Device logcat -d -t 1200 | Out-File (Join-Path $capturePath 'logcat.txt')
Write-Output "Read-only diagnostics saved: $capturePath"
