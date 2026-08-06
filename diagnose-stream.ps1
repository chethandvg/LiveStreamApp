#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Diagnoses HLS streaming issues for LiveStream App

.DESCRIPTION
    Comprehensive diagnostic tool that checks:
    - FFmpeg installation and configuration
    - Azure Storage connectivity and CORS
    - Stream file availability
    - CDN configuration
    - Network connectivity
    - HLS manifest validity

.PARAMETER StreamId
    The stream ID to diagnose (optional)

.PARAMETER CheckAll
    Perform all diagnostic checks

.EXAMPLE
    .\diagnose-stream.ps1

.EXAMPLE
    .\diagnose-stream.ps1 -StreamId "stream_12345"

.EXAMPLE
    .\diagnose-stream.ps1 -CheckAll
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$StreamId,
    
    [Parameter(Mandatory=$false)]
    [switch]$CheckAll
)

# Color output functions
function Write-Success { param($Message) Write-Host "? $Message" -ForegroundColor Green }
function Write-Info { param($Message) Write-Host "? $Message" -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host "? $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "? $Message" -ForegroundColor Red }
function Write-Section { param($Message) Write-Host "`n=== $Message ===" -ForegroundColor Cyan }

Write-Host "`n????????????????????????????????????????????????" -ForegroundColor Cyan
Write-Host "?   LiveStream App - Diagnostic Tool          ?" -ForegroundColor Cyan
Write-Host "????????????????????????????????????????????????" -ForegroundColor Cyan
Write-Host ""

$issues = @()
$warnings = @()
$successes = @()

# 1. Check FFmpeg Installation
Write-Section "FFmpeg Installation"
try {
    $ffmpegVersion = ffmpeg -version 2>&1 | Select-Object -First 1
    if ($ffmpegVersion -match "ffmpeg version") {
        Write-Success "FFmpeg is installed: $ffmpegVersion"
        $successes += "FFmpeg is properly installed"
    } else {
        Write-Error "FFmpeg found but version check failed"
        $issues += "FFmpeg installation issue"
    }
} catch {
    Write-Error "FFmpeg is not installed or not in PATH"
    Write-Host "  Download from: https://ffmpeg.org/download.html" -ForegroundColor Gray
    $issues += "FFmpeg is not installed"
}

# 2. Check .NET SDK
Write-Section ".NET SDK"
try {
    $dotnetVersion = dotnet --version 2>&1
    if ($dotnetVersion -match "^\d+\.\d+") {
        Write-Success ".NET SDK version: $dotnetVersion"
        if ([version]$dotnetVersion -ge [version]"9.0") {
            $successes += ".NET 9+ is installed"
        } else {
            Write-Warning ".NET 9.0 is recommended, current version: $dotnetVersion"
            $warnings += ".NET version is below 9.0"
        }
    }
} catch {
    Write-Error ".NET SDK is not installed"
    $issues += ".NET SDK is not installed"
}

# 3. Check Configuration Files
Write-Section "Configuration Files"
$appsettingsPath = "Server/appsettings.json"
if (Test-Path $appsettingsPath) {
    Write-Success "Found Server/appsettings.json"
    
    try {
        $appsettings = Get-Content $appsettingsPath -Raw | ConvertFrom-Json
        
        # Check Azure Storage connection string
        if ($appsettings.AzureStorage.ConnectionString) {
            if ($appsettings.AzureStorage.ConnectionString -match "DefaultEndpointsProtocol=https") {
                Write-Success "Azure Storage connection string is configured"
                $successes += "Azure Storage configuration is present"
                
                # Extract storage account name
                if ($appsettings.AzureStorage.ConnectionString -match "AccountName=([^;]+)") {
                    $storageAccountName = $matches[1]
                    Write-Info "  Storage Account: $storageAccountName"
                }
            } else {
                Write-Warning "Azure Storage connection string may be incomplete"
                $warnings += "Check Azure Storage connection string"
            }
        } else {
            Write-Error "Azure Storage connection string is missing"
            $issues += "Azure Storage connection string not configured"
        }
        
        # Check CDN configuration
        if ($appsettings.Azure.CDN.BaseUrl) {
            Write-Success "CDN Base URL is configured: $($appsettings.Azure.CDN.BaseUrl)"
            $cdnBaseUrl = $appsettings.Azure.CDN.BaseUrl
            $successes += "CDN configuration is present"
        } else {
            Write-Error "CDN Base URL is not configured"
            $issues += "CDN Base URL not configured"
        }
        
        # Check SignalR configuration
        if ($appsettings.Azure.SignalR.ConnectionString) {
            Write-Success "SignalR connection string is configured"
            $successes += "SignalR configuration is present"
        } else {
            Write-Warning "SignalR connection string is not configured (optional)"
            $warnings += "SignalR not configured - chat may not work"
        }
        
    } catch {
        Write-Error "Failed to parse appsettings.json: $($_.Exception.Message)"
        $issues += "Configuration file parsing error"
    }
} else {
    Write-Error "Server/appsettings.json not found"
    Write-Host "  Please run this script from the solution root directory" -ForegroundColor Gray
    $issues += "Configuration file not found"
}

# Check client configuration
$clientAppsettingsPath = "Client/wwwroot/appsettings.json"
if (Test-Path $clientAppsettingsPath) {
    Write-Success "Found Client/wwwroot/appsettings.json"
    
    try {
        $clientConfig = Get-Content $clientAppsettingsPath -Raw | ConvertFrom-Json
        
        if ($clientConfig.Azure.CDN.BaseUrl) {
            if ($clientConfig.Azure.CDN.BaseUrl -eq $cdnBaseUrl) {
                Write-Success "Client CDN URL matches server configuration"
                $successes += "Client and server CDN configuration match"
            } else {
                Write-Warning "Client CDN URL differs from server configuration"
                Write-Host "  Client: $($clientConfig.Azure.CDN.BaseUrl)" -ForegroundColor Gray
                Write-Host "  Server: $cdnBaseUrl" -ForegroundColor Gray
                $warnings += "CDN URL mismatch between client and server"
            }
        } else {
            Write-Error "Client CDN URL is not configured"
            $issues += "Client CDN URL not configured"
        }
    } catch {
        Write-Error "Failed to parse client appsettings.json"
        $issues += "Client configuration parsing error"
    }
} else {
    Write-Warning "Client/wwwroot/appsettings.json not found"
    $warnings += "Client configuration file not found"
}

# 4. Check Azure Storage Connectivity (if configured)
if ($storageAccountName) {
    Write-Section "Azure Storage Connectivity"
    
    try {
        $storageUrl = "https://$storageAccountName.blob.core.windows.net/livestreams/"
        Write-Info "Testing connection to: $storageUrl"
        
        $response = Invoke-WebRequest -Uri $storageUrl -Method HEAD -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        Write-Success "Azure Storage is reachable (Status: $($response.StatusCode))"
        $successes += "Azure Storage is accessible"
        
        # Check CORS headers
        if ($response.Headers['Access-Control-Allow-Origin']) {
            Write-Success "CORS is configured (Access-Control-Allow-Origin: $($response.Headers['Access-Control-Allow-Origin']))"
            $successes += "CORS is properly configured"
        } else {
            Write-Warning "CORS headers not found in response"
            Write-Host "  Run .\configure-cors.ps1 to configure CORS" -ForegroundColor Gray
            $warnings += "CORS may not be configured - run configure-cors.ps1"
        }
        
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 404) {
            Write-Warning "Storage container 'livestreams' not found (404)"
            Write-Host "  The container will be created automatically when streaming starts" -ForegroundColor Gray
            $warnings += "Storage container not created yet (will be auto-created)"
        } elseif ($statusCode -eq 403) {
            Write-Error "Access denied to storage account (403)"
            $issues += "Storage account access denied - check permissions"
        } else {
            Write-Error "Failed to connect to Azure Storage: $($_.Exception.Message)"
            $issues += "Azure Storage connectivity issue"
        }
    }
}

# 5. Check Stream Files (if StreamId provided)
if ($StreamId) {
    Write-Section "Stream Files for '$StreamId'"
    
    if ($cdnBaseUrl) {
        $manifestUrl = "$cdnBaseUrl/$StreamId/index.m3u8"
        Write-Info "Checking manifest at: $manifestUrl"
        
        try {
            $manifestResponse = Invoke-WebRequest -Uri $manifestUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
            
            if ($manifestResponse.StatusCode -eq 200) {
                Write-Success "Manifest file found (200 OK)"
                Write-Host "  Content-Type: $($manifestResponse.Headers['Content-Type'])" -ForegroundColor Gray
                Write-Host "  Size: $($manifestResponse.Content.Length) bytes" -ForegroundColor Gray
                $successes += "Stream manifest is accessible"
                
                # Parse manifest to check for segments
                $manifestContent = $manifestResponse.Content
                $segments = @()
                $manifestContent -split "`n" | ForEach-Object {
                    if ($_ -match "segment_\d+\.ts") {
                        $segments += $matches[0]
                    }
                }
                
                if ($segments.Count -gt 0) {
                    Write-Success "Found $($segments.Count) video segments in manifest"
                    $successes += "Video segments are being generated"
                    
                    # Test first segment
                    $firstSegment = $segments[0]
                    $segmentUrl = "$cdnBaseUrl/$StreamId/$firstSegment"
                    Write-Info "Testing first segment: $segmentUrl"
                    
                    try {
                        $segmentResponse = Invoke-WebRequest -Uri $segmentUrl -Method HEAD -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                        Write-Success "First segment is accessible (Status: $($segmentResponse.StatusCode))"
                        $successes += "Video segments are accessible"
                    } catch {
                        Write-Warning "First segment is not accessible: $($_.Exception.Message)"
                        $warnings += "Video segments may not be accessible via CDN"
                    }
                } else {
                    Write-Warning "No video segments found in manifest"
                    $warnings += "Stream may have just started - no segments yet"
                }
            }
        } catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            if ($statusCode -eq 404) {
                Write-Warning "Stream manifest not found (404)"
                Write-Host "  The stream may not have started yet or has ended" -ForegroundColor Gray
                Write-Host "  Start broadcasting to create the stream files" -ForegroundColor Gray
                $warnings += "Stream not found - broadcaster needs to start streaming"
            } else {
                Write-Error "Failed to access manifest: $($_.Exception.Message)"
                $issues += "Cannot access stream manifest"
            }
        }
    } else {
        Write-Warning "CDN Base URL not configured, cannot check stream files"
    }
}

# 6. Check CDN/Front Door Configuration
if ($cdnBaseUrl) {
    Write-Section "CDN Configuration"
    
    Write-Info "CDN Base URL: $cdnBaseUrl"
    
    # Parse URL
    if ($cdnBaseUrl -match "^https://([^/]+)") {
        $cdnDomain = $matches[1]
        Write-Info "CDN Domain: $cdnDomain"
        
        # Test CDN reachability
        try {
            $cdnTest = Invoke-WebRequest -Uri $cdnBaseUrl -Method HEAD -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
            Write-Success "CDN endpoint is reachable (Status: $($cdnTest.StatusCode))"
            $successes += "CDN is accessible"
        } catch {
            Write-Warning "CDN endpoint test failed: $($_.Exception.Message)"
            $warnings += "CDN may not be properly configured"
        }
    }
}

# 7. Check if server is running
Write-Section "Application Status"
try {
    $serverUrl = "https://localhost:7119/api/streamingest/ffmpeg-status"
    $serverTest = Invoke-WebRequest -Uri $serverUrl -UseBasicParsing -SkipCertificateCheck -TimeoutSec 5 -ErrorAction Stop
    $ffmpegStatus = $serverTest.Content | ConvertFrom-Json
    
    if ($ffmpegStatus.available) {
        Write-Success "Server is running and FFmpeg is available"
        Write-Host "  FFmpeg Version: $($ffmpegStatus.version)" -ForegroundColor Gray
        $successes += "Server is running with FFmpeg available"
    } else {
        Write-Warning "Server is running but FFmpeg is not available"
        $warnings += "FFmpeg not available to server"
    }
} catch {
    Write-Warning "Cannot connect to local server (https://localhost:7119)"
    Write-Host "  Start the server with: cd Server && dotnet run" -ForegroundColor Gray
    $warnings += "Server is not running"
}

# Summary
Write-Section "Diagnostic Summary"

Write-Host ""
Write-Host "Successes: $($successes.Count)" -ForegroundColor Green
foreach ($success in $successes) {
    Write-Host "  ? $success" -ForegroundColor Green
}

if ($warnings.Count -gt 0) {
    Write-Host ""
    Write-Host "Warnings: $($warnings.Count)" -ForegroundColor Yellow
    foreach ($warning in $warnings) {
        Write-Host "  ? $warning" -ForegroundColor Yellow
    }
}

if ($issues.Count -gt 0) {
    Write-Host ""
    Write-Host "Critical Issues: $($issues.Count)" -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host "  ? $issue" -ForegroundColor Red
    }
}

# Recommendations
Write-Section "Recommendations"

if ($issues.Count -eq 0 -and $warnings.Count -eq 0) {
    Write-Success "All checks passed! Your setup looks good."
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Start the server: cd Server && dotnet run" -ForegroundColor Gray
    Write-Host "2. Open broadcaster: https://localhost:7119/broadcast" -ForegroundColor Gray
    Write-Host "3. Start streaming and share the viewer link" -ForegroundColor Gray
} else {
    if ($issues -contains "FFmpeg is not installed") {
        Write-Host "• Install FFmpeg: https://ffmpeg.org/download.html" -ForegroundColor Yellow
        Write-Host "  - Windows: choco install ffmpeg" -ForegroundColor Gray
        Write-Host "  - macOS: brew install ffmpeg" -ForegroundColor Gray
        Write-Host "  - Linux: apt install ffmpeg" -ForegroundColor Gray
    }
    
    if ($issues -contains "Azure Storage connection string not configured") {
        Write-Host "• Configure Azure Storage in Server/appsettings.json" -ForegroundColor Yellow
    }
    
    if ($warnings -match "CORS") {
        Write-Host "• Configure CORS: .\configure-cors.ps1" -ForegroundColor Yellow
    }
    
    if ($warnings -contains "Server is not running") {
        Write-Host "• Start the server: cd Server && dotnet run" -ForegroundColor Yellow
    }
    
    if (!$StreamId) {
        Write-Host ""
        Write-Host "To diagnose a specific stream, run:" -ForegroundColor Cyan
        Write-Host "  .\diagnose-stream.ps1 -StreamId '<your-stream-id>'" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "For more help, see: TROUBLESHOOTING.md" -ForegroundColor Cyan
Write-Host ""

# Exit code
if ($issues.Count -gt 0) {
    exit 1
} elseif ($warnings.Count -gt 0) {
    exit 0
} else {
    exit 0
}
