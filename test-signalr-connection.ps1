#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Quick SignalR connection test

.DESCRIPTION
    Performs a fast connectivity check to Azure SignalR Service

.EXAMPLE
    .\test-signalr-connection.ps1
#>

Write-Host "?? Quick SignalR Connection Test" -ForegroundColor Cyan
Write-Host ""

# Check appsettings
$appsettingsPath = "Server/appsettings.json"
if (-not (Test-Path $appsettingsPath)) {
    Write-Host "? Server/appsettings.json not found" -ForegroundColor Red
    exit 1
}

# Check if UseLocal is enabled
$appsettingsDevPath = "Server/appsettings.Development.json"
if (Test-Path $appsettingsDevPath) {
    $appsettingsDev = Get-Content $appsettingsDevPath -Raw | ConvertFrom-Json
    if ($appsettingsDev.Azure.SignalR.UseLocal) {
        Write-Host "? Using LOCAL SignalR (UseLocal = true)" -ForegroundColor Green
        Write-Host "   Azure SignalR will NOT be used in development mode" -ForegroundColor Gray
        Write-Host ""
        Write-Host "??  To test Azure SignalR:" -ForegroundColor Cyan
        Write-Host "   Set 'UseLocal' to false in Server/appsettings.Development.json" -ForegroundColor Gray
        exit 0
    }
}

# Parse connection string
$appsettings = Get-Content $appsettingsPath -Raw | ConvertFrom-Json
$connStr = $appsettings.Azure.SignalR.ConnectionString

if ([string]::IsNullOrWhiteSpace($connStr)) {
    Write-Host "? Connection string is empty" -ForegroundColor Red
    exit 1
}

# Extract endpoint
if ($connStr -match "Endpoint=([^;]+)") {
    $endpoint = $matches[1]
    $hostname = $endpoint -replace "https://", "" -replace "http://", ""
    
    Write-Host "?? Testing: $hostname" -ForegroundColor Yellow
    Write-Host ""
    
    # Test DNS
    Write-Host "1. DNS Resolution... " -NoNewline
    try {
        $dns = Resolve-DnsName -Name $hostname -ErrorAction Stop
        Write-Host "?" -ForegroundColor Green
    }
    catch {
        Write-Host "?" -ForegroundColor Red
        Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    
    # Test TCP
    Write-Host "2. TCP Connection (port 443)... " -NoNewline
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $asyncResult = $tcpClient.BeginConnect($hostname, 443, $null, $null)
        $wait = $asyncResult.AsyncWaitHandle.WaitOne(5000, $false)
        
        if ($wait -and $tcpClient.Connected) {
            Write-Host "?" -ForegroundColor Green
            $tcpClient.Close()
        }
        else {
            Write-Host "? (timeout)" -ForegroundColor Red
            $tcpClient.Close()
            exit 1
        }
    }
    catch {
        Write-Host "?" -ForegroundColor Red
        Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    
    # Test HTTPS
    Write-Host "3. HTTPS Endpoint... " -NoNewline
    try {
        $response = Invoke-WebRequest -Uri $endpoint -Method Get -TimeoutSec 10 -ErrorAction Stop
        Write-Host "? (Status: $($response.StatusCode))" -ForegroundColor Green
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            Write-Host "? (404 - expected)" -ForegroundColor Green
        }
        else {
            Write-Host "??  (Status: $($_.Exception.Response.StatusCode))" -ForegroundColor Yellow
        }
    }
    
    # Test negotiate endpoint
    Write-Host "4. SignalR Negotiate... " -NoNewline
    $negotiateUrl = "$endpoint/client/negotiate?hub=ChatHub"
    try {
        $response = Invoke-WebRequest -Uri $negotiateUrl -Method Post -TimeoutSec 10 -ErrorAction Stop
        Write-Host "?" -ForegroundColor Green
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 401) {
            Write-Host "? (401 - service is working)" -ForegroundColor Green
        }
        elseif ($statusCode -eq 502) {
            Write-Host "? 502 BAD GATEWAY!" -ForegroundColor Red
            Write-Host ""
            Write-Host "??  SignalR service is having issues!" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Quick fix:" -ForegroundColor Cyan
            Write-Host "  .\verify-signalr-setup.ps1 -FixAppsettings" -ForegroundColor White
            Write-Host ""
            exit 1
        }
        else {
            Write-Host "??  (Status: $statusCode)" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
    Write-Host "? All checks passed!" -ForegroundColor Green
    Write-Host ""
}
else {
    Write-Host "? Invalid connection string format" -ForegroundColor Red
    exit 1
}
