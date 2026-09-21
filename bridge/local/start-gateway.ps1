[CmdletBinding()]
param(
    [int]$Port = 8787,
    [switch]$Loopback,
    [switch]$AllowPrivateNetwork
)

$ErrorActionPreference = 'Stop'

$localRoot = $PSScriptRoot
$gatewayRoot = Join-Path $localRoot '..\tvbox-Swift-macOS\spider-gateway'
$stateRoot = Join-Path $localRoot 'state'
$tokenPath = Join-Path $stateRoot 'gateway-token.txt'

if (-not (Test-Path (Join-Path $gatewayRoot 'package.json'))) {
    throw "找不到 Gateway 源码：$gatewayRoot"
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw '未找到 Node.js。请安装 Node.js 22.13 或更高版本。'
}

New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
if (-not (Test-Path $tokenPath)) {
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    $token = [Convert]::ToBase64String($bytes).Replace('+', '-').Replace('/', '_').TrimEnd('=')
    Set-Content -Path $tokenPath -Value $token -Encoding ascii -NoNewline
} else {
    $token = (Get-Content -Raw $tokenPath).Trim()
}

$env:SPIDER_GATEWAY_HOST = if ($Loopback) { '127.0.0.1' } else { '0.0.0.0' }
$env:SPIDER_GATEWAY_PORT = [string]$Port
$env:SPIDER_GATEWAY_TOKEN = $token
$env:SPIDER_GATEWAY_CACHE_DIR = Join-Path $stateRoot 'jars'
$env:CATVOD_BUNDLE_CACHE_DIR = Join-Path $stateRoot 'bundles'
$env:CATVOD_RUNTIME_DIR = Join-Path $stateRoot 'runtime'
$env:SPIDER_JAR_ALLOW_PRIVATE_NETWORK = if ($AllowPrivateNetwork) { 'true' } else { 'false' }

$lanAddresses = @(Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike '127.*' } |
    Select-Object -ExpandProperty IPAddress)

Write-Host ''
Write-Host '丛丛影视本机临时 Gateway' -ForegroundColor Cyan
Write-Host "监听：$($env:SPIDER_GATEWAY_HOST):$Port"
Write-Host "Token：$token" -ForegroundColor Yellow
Write-Host "Token 文件：$tokenPath"
if ($Loopback) {
    Write-Host "本机地址：http://127.0.0.1:$Port"
} else {
    foreach ($address in $lanAddresses) {
        Write-Host "手机填写：http://${address}:$Port"
    }
}
Write-Host '按 Ctrl+C 停止。' -ForegroundColor DarkGray
Write-Host ''

Push-Location $gatewayRoot
try {
    npm start
} finally {
    Pop-Location
}
