[CmdletBinding()]
param(
    [int]$Port = 8787
)

$ErrorActionPreference = 'Stop'
$url = "http://127.0.0.1:$Port/health"
$result = Invoke-RestMethod -Uri $url -Method Get
$result | ConvertTo-Json -Depth 5

$addresses = @(Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike '127.*' } |
    Select-Object -ExpandProperty IPAddress)
foreach ($address in $addresses) {
    Write-Host "手机 Gateway 地址：http://${address}:$Port"
}
