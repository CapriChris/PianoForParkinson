param(
    [Parameter(Mandatory)][string]$WebRoot,
    [string]$Python = 'python',
    [string]$Flutter = 'flutter',
    [string]$OpenSsl = 'openssl',
    [string]$TestPath = 'test/integration/live_sync_smoke_test.dart'
)
$ErrorActionPreference = 'Stop'
$app = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$web = (Resolve-Path $WebRoot).Path
$work = Join-Path $app ('.dart_tool/local-sync-qa-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$env:APP_ENV = 'test'
$env:DATABASE_URL = 'sqlite:///' + (Join-Path $work 'isolated.db').Replace('\','/')
$env:UPLOAD_DIR = Join-Path $work 'uploads'
$env:OUTPUT_DIR = Join-Path $work 'outputs'
$env:REPORT_DIR = Join-Path $work 'reports'
$env:BOOTSTRAP_ADMIN_USERNAME = 'local-sync-qa'
$env:BOOTSTRAP_ADMIN_PASSWORD = [guid]::NewGuid().ToString('N')
$env:JWT_SECRET = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
$env:MICRO_EXPRESSION_ENTRY = ''
$env:TRAINING_VIDEO_ENABLED = 'false'
$env:EXPERT_LLM_BASE_URL = ''
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = $listener.LocalEndpoint.Port
$listener.Stop()
$cert = Join-Path $work 'local-cert.pem'
$key = Join-Path $work 'local-key.pem'
$cfg = Join-Path $work 'openssl.cnf'
@'
[req]
distinguished_name = dn
x509_extensions = extensions
prompt = no
[dn]
CN = 127.0.0.1
[extensions]
subjectAltName = IP:127.0.0.1
basicConstraints = critical,CA:TRUE
'@ | Set-Content -Encoding ascii $cfg
& $OpenSsl req -config $cfg -x509 -nodes -newkey rsa:2048 -days 1 -out $cert -keyout $key 2> (Join-Path $work 'openssl.log')
if ($LASTEXITCODE) { throw 'OpenSSL failed' }
$server = Start-Process -FilePath $Python -ArgumentList @('-m','uvicorn','app.main:app','--host','127.0.0.1','--port',$port,'--ssl-keyfile',('"'+$key+'"'),'--ssl-certfile',('"'+$cert+'"')) -WorkingDirectory (Join-Path $web 'backend') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $work 'web.log') -RedirectStandardError (Join-Path $work 'web-error.log')
try {
    $env:PD_SYNC_TEST_URL = "https://127.0.0.1:$port/api"
    $env:PD_SYNC_TEST_PASSWORD = $env:BOOTSTRAP_ADMIN_PASSWORD
    $env:PD_SYNC_TEST_CERT = $cert
    for ($i=0; $i -lt 200; $i++) {
        $server.Refresh()
        if ($server.HasExited) { throw "Isolated Web failed; inspect $work/web-error.log" }
        & $Python -c "import ssl,sys,urllib.request; urllib.request.urlopen(sys.argv[1], context=ssl.create_default_context(cafile=sys.argv[2]),timeout=2).read()" "$env:PD_SYNC_TEST_URL/system/health" $cert 2> (Join-Path $work 'health-error.log')
        if ($LASTEXITCODE -eq 0) { break }
        Start-Sleep -Milliseconds 300
    }
    if ($LASTEXITCODE) { throw 'Isolated Web not ready' }
    Push-Location $app
    try {
        & $Flutter test --no-pub --reporter expanded $TestPath
        if ($LASTEXITCODE) { throw 'Real HTTPS sync smoke failed' }
    } finally { Pop-Location }
} finally {
    if (!$server.HasExited) { Stop-Process -Id $server.Id }
    Remove-Item Env:PD_SYNC_TEST_PASSWORD,Env:PD_SYNC_TEST_URL,Env:PD_SYNC_TEST_CERT -ErrorAction SilentlyContinue
}
