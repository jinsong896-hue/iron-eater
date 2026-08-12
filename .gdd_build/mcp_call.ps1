param(
    [Parameter(Mandatory=$true)][string]$Method,
    [Parameter(Mandatory=$false)][string]$ParamsFile = '',
    [Parameter(Mandatory=$false)][string]$Server = 'http://127.0.0.1:8000/mcp',
    [Parameter(Mandatory=$false)][string]$SessionFile = 'E:\unity\.gdd_build\mcp_session.txt'
)

$ErrorActionPreference = 'Stop'

function Invoke-McpJson($jsonBody, $sessionId) {
    $headers = @{ Accept = 'application/json, text/event-stream' }
    if ($sessionId) { $headers['Mcp-Session-Id'] = $sessionId }
    $r = Invoke-WebRequest -Uri $Server -Method Post -ContentType 'application/json' -Headers $headers -Body $jsonBody -TimeoutSec 300 -UseBasicParsing
    return $r
}

$sessionId = $null
if (Test-Path -LiteralPath $SessionFile) {
    $sessionId = (Get-Content -LiteralPath $SessionFile -Encoding UTF8 -Raw).Trim()
}

if (-not $sessionId) {
    # handshake
    $initBody = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"codex-shell","version":"1.0"}}}'
    $resp = Invoke-McpJson $initBody $null
    $sid = $resp.Headers['Mcp-Session-Id']
    if ($sid) { $sid | Set-Content -LiteralPath $SessionFile -Encoding UTF8; $sessionId = $sid }
    $notifyBody = '{"jsonrpc":"2.0","method":"notifications/initialized"}'
    try { Invoke-McpJson $notifyBody $sessionId | Out-Null } catch {}
}

$paramsJson = '{}'
if ($ParamsFile -and (Test-Path -LiteralPath $ParamsFile)) {
    $paramsJson = (Get-Content -LiteralPath $ParamsFile -Encoding UTF8 -Raw).Trim()
}
$argsObj = $paramsJson | ConvertFrom-Json
$body = @{ jsonrpc = '2.0'; id = 2; method = 'tools/call'; params = @{ name = $Method; arguments = $argsObj } } | ConvertTo-Json -Depth 30 -Compress
$r = Invoke-McpJson $body $sessionId
$content = $r.Content
$json = ($content -split "`n" | Where-Object { $_ -like 'data:*' } | ForEach-Object { $_.Substring(5) }) -join ''
if ($json) {
    $respObj = $json | ConvertFrom-Json
    if ($respObj.error) {
        Write-Output ("MCP ERROR: " + ($respObj.error | ConvertTo-Json -Depth 10 -Compress))
        exit 1
    }
    if ($respObj.result.structuredContent) {
        return $respObj.result.structuredContent | ConvertTo-Json -Depth 30
    }
    return $respObj.result | ConvertTo-Json -Depth 30
} else {
    return $content
}
