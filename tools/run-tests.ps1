# Прогон тестов YAxUnit: загрузка расширения тестов в ИБ -> снятие безопасного режима -> запуск -> итог.
# Использование:  powershell -NoProfile -File tools\run-tests.ps1 [-Config tests\yaxunit\все.json] [-SkipLoad]
# Код выхода скрипта: 0 — тесты прошли, 1 — есть падения, 2 — ошибка запуска (нет отчета).
# Источник параметров запуска YAxUnit: https://github.com/bia-technologies/yaxunit (docs, run-config)
param(
    [string]$Config = 'tests\yaxunit\все.json',
    # Расширения для загрузки: имя расширения в ИБ -> каталог в Extensions\
    [hashtable]$Extensions = [ordered]@{ 'СчетаМагазина' = 'Bills'; 'Тесты' = 'Тесты' },
    [switch]$SkipLoad
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$bin  = 'C:\Program Files\1cv8\8.5.1.1529\bin'
$base = '/F"C:\Users\psi\Downloads\AICourse\DBIS07"'
$user = '/N"Администратор"'
$logs = Join-Path $root '.logs'
New-Item -ItemType Directory -Force (Join-Path $logs 'yaxunit') | Out-Null

function Invoke-1C([string]$Exe, [string[]]$Arguments) {
    $p = Start-Process (Join-Path $bin $Exe) -ArgumentList $Arguments -Wait -PassThru
    return $p.ExitCode
}

if (-not $SkipLoad) {
    foreach ($Extension in $Extensions.Keys) {
        $dir = $Extensions[$Extension]
        $code = Invoke-1C '1cv8.exe' @('DESIGNER', $base, $user, '/DisableStartupDialogs',
            '/LoadConfigFromFiles', "`"$root\Extensions\$dir`"", '-Extension', $Extension,
            "/Out`"$logs\load-$Extension.log`"")
        if ($code -ne 0) { Get-Content "$logs\load-$Extension.log" -Encoding UTF8; exit 2 }
        # Загруженное расширение применяется к ИБ только после обновления (отдельным вызовом:
        # вместе с /LoadConfigFromFiles платформа отвечает «Ошибка в параметрах командной строки»).
        $code = Invoke-1C '1cv8.exe' @('DESIGNER', $base, $user, '/DisableStartupDialogs',
            '/UpdateDBCfg', '-Extension', $Extension, "/Out`"$logs\update-$Extension.log`"")
        if ($code -ne 0) { Get-Content "$logs\update-$Extension.log" -Encoding UTF8; exit 2 }
    }

    # Конфигуратор подключает загруженное расширение в безопасном режиме — YAxUnit в нем не работает.
    $epf = Join-Path $logs 'СнятиеБезопасногоРежимаРасширений.epf'
    if (-not (Test-Path $epf)) { Write-Host "Нет $epf — соберите tools\epf навыком epf-build"; exit 2 }
    [void](Invoke-1C '1cv8c.exe' @('ENTERPRISE', $base, $user, '/DisableStartupDialogs',
        "/Execute`"$epf`"", "/C`"$logs\unsafe.log`""))
    Get-Content "$logs\unsafe.log" -Encoding UTF8
}

$cfg = Get-Content (Join-Path $root $Config) -Raw -Encoding UTF8 | ConvertFrom-Json
Remove-Item $cfg.reportPath, $cfg.exitCode -ErrorAction SilentlyContinue
[void](Invoke-1C '1cv8c.exe' @('ENTERPRISE', $base, $user, '/DisableStartupDialogs',
    "/C`"RunUnitTests=$(Join-Path $root $Config)`""))

if (-not (Test-Path $cfg.reportPath)) { Write-Host "Отчет не сформирован: $($cfg.reportPath)"; exit 2 }
[xml]$report = Get-Content $cfg.reportPath -Raw -Encoding UTF8
foreach ($case in $report.SelectNodes('//testcase')) {
    $failure = $case.SelectSingleNode('failure|error')
    if ($failure) { Write-Host "FAIL  $($case.classname): $($failure.message)" -ForegroundColor Red }
    else          { Write-Host "OK    $($case.classname)" -ForegroundColor Green }
}
$exit = [int](Get-Content $cfg.exitCode -Raw).Trim()
Write-Host "Итого тестов: $($report.SelectNodes('//testcase').Count), код результата YAxUnit: $exit"
exit $exit
