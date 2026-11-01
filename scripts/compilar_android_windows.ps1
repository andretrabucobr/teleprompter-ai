param(
    [ValidateSet('base', 'tiny')]
    [string]$Modelo = 'base',
    [string]$ArquivoModelo = ''
)

$ErrorActionPreference = 'Stop'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$raiz = (Get-Location).Path

function Exigir-Comando([string]$Nome, [string]$Ajuda) {
    if (-not (Get-Command $Nome -ErrorAction SilentlyContinue)) {
        throw "Nao encontrei '$Nome'. $Ajuda"
    }
}
function Executar([string]$Programa, [string[]]$Argumentos) {
    Write-Host "`n>> $Programa $($Argumentos -join ' ')" -ForegroundColor Cyan
    & $Programa @Argumentos
    if ($LASTEXITCODE -ne 0) {
        throw "O comando '$Programa' terminou com codigo $LASTEXITCODE."
    }
}

try {
    Write-Host 'Teleprompter AI - compilacao Android local' -ForegroundColor Green
    Exigir-Comando 'flutter' 'Instale o Flutter SDK e adicione flutter\bin ao PATH: https://docs.flutter.dev/get-started/install'
    Exigir-Comando 'java' 'Instale o JDK 17 ou use o JDK do Android Studio: https://developer.android.com/studio'
    $python = if (Get-Command 'py' -ErrorAction SilentlyContinue) { 'py' } else { 'python' }
    Exigir-Comando $python 'Instale Python 3.10+ em https://www.python.org/downloads/windows/'

    [string[]]$pyPrefix = @()
    if ($python -eq 'py') { $pyPrefix = @('-3') }
    Executar $python ($pyPrefix + @('--version'))
    Executar 'flutter' @('--version')
    $sdk = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME,
             (Join-Path $env:LOCALAPPDATA 'Android\Sdk')) |
             Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $sdk) {
        throw 'Android SDK ausente. Instale o Android Studio e o SDK Manager: https://developer.android.com/studio'
    }
    Write-Host "Android SDK detectado: $sdk"
    if (-not $env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT = $sdk }
    if (-not (Test-Path 'android\app\src\main\AndroidManifest.xml')) {
        Executar 'flutter' @('create', '--platforms=android', '--project-name=teleprompter_ai', '.')
    }
    Executar $python ($pyPrefix + @('scripts/configurar_plataformas.py', '--platform', 'android'))

    $argsModelo = @('scripts/instalar_modelo.py', '--model', $Modelo)
    if ($ArquivoModelo) {
        $archive = (Resolve-Path $ArquivoModelo).Path
        $argsModelo += @('--archive', $archive)
    }
    Executar $python ($pyPrefix + $argsModelo)
    Executar 'flutter' @('pub', 'get')

    # Analise e testes sao exigidos, para nao produzir um APK enganoso.
    Executar 'flutter' @('analyze', '--no-fatal-infos', '--no-fatal-warnings')
    Executar 'flutter' @('test')
    Executar 'flutter' @('build', 'apk', '--debug', '--target-platform', 'android-arm64')

    $origem = Join-Path $raiz 'build\app\outputs\flutter-apk\app-debug.apk'
    if (-not (Test-Path $origem)) {
        throw "Flutter nao gerou o APK esperado: $origem"
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $raiz 'dist') | Out-Null
    $destino = Join-Path $raiz 'dist\TeleprompterAI-v0.4-debug-Android-arm64.apk'
    Copy-Item -Path $origem -Destination $destino -Force
    Write-Host "`nSUCESSO! APK criado: $destino" -ForegroundColor Green
    Write-Host 'APK de teste; nao esta assinado para publicacao na Play Store.'
    exit 0
} catch {
    Write-Host "`nERRO: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Confirme flutter doctor -v, licencas Android, acesso a Internet e permissoes.'
    exit 1
}
