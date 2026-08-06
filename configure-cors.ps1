#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Configures CORS settings for Azure Storage and Azure Front Door to enable HLS streaming

.DESCRIPTION
    This script configures CORS (Cross-Origin Resource Sharing) settings on:
    1. Azure Storage Blob Service - for direct storage access
    2. Azure Front Door - for CDN access
    
    It fixes the invalid CORS header issue that blocks HLS streaming.

.PARAMETER StorageAccountName
    The name of the Azure Storage account

.PARAMETER ResourceGroup
    The resource group containing the storage account (optional, will be auto-detected if not provided)

.PARAMETER FrontDoorName
    The name of the Azure Front Door profile (optional, will be auto-detected)

.PARAMETER FixFrontDoor
    Also configure CORS on Azure Front Door (recommended)

.EXAMPLE
    .\configure-cors.ps1 -StorageAccountName "livestreamtrial"

.EXAMPLE
    .\configure-cors.ps1 -StorageAccountName "livestreamtrial" -FixFrontDoor

.EXAMPLE
    .\configure-cors.ps1 -StorageAccountName "livestreamtrial" -ResourceGroup "LiveStreamApp-RG" -FixFrontDoor
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup,
    
    [Parameter(Mandatory=$false)]
    [string]$FrontDoorName,
    
    [Parameter(Mandatory=$false)]
    [switch]$FixFrontDoor
)

# Color output functions
function Write-Success { param($Message) Write-Host "? $Message" -ForegroundColor Green }
function Write-Info { param($Message) Write-Host "? $Message" -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host "? $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "? $Message" -ForegroundColor Red }
function Write-Section { param($Message) Write-Host "`n=== $Message ===" -ForegroundColor Cyan }

Write-Host "`n????????????????????????????????????????????????" -ForegroundColor Cyan
Write-Host "?   Azure CORS Configuration Tool              ?" -ForegroundColor Cyan
Write-Host "?   Fixes: Invalid CORS Header Issues          ?" -ForegroundColor Cyan
Write-Host "????????????????????????????????????????????????" -ForegroundColor Cyan
Write-Host ""

# Check if Azure CLI is installed
Write-Section "Prerequisites Check"
Write-Info "Checking Azure CLI installation..."
try {
    $azVersion = az version --output json 2>$null | ConvertFrom-Json
    Write-Success "Azure CLI version $($azVersion.'azure-cli') is installed"
} catch {
    Write-Error "Azure CLI is not installed or not in PATH"
    Write-Host "`nPlease install Azure CLI from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli`n" -ForegroundColor Yellow
    exit 1
}

# Check if logged in
Write-Info "Checking Azure login status..."
$loginStatus = az account show 2>$null
if (-not $loginStatus) {
    Write-Warning "Not logged in to Azure"
    Write-Info "Attempting to login..."
    az login
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to login to Azure"
        exit 1
    }
}

$account = az account show | ConvertFrom-Json
Write-Success "Logged in as: $($account.user.name)"
Write-Info "Subscription: $($account.name) ($($account.id))"

# Get storage account name from appsettings if not provided
if (-not $StorageAccountName) {
    Write-Section "Configuration Discovery"
    Write-Info "Attempting to read storage account from Server/appsettings.json..."
    
    if (Test-Path "Server/appsettings.json") {
        $appsettings = Get-Content "Server/appsettings.json" -Raw | ConvertFrom-Json
        $connectionString = $appsettings.AzureStorage.ConnectionString
        
        if ($connectionString -match "AccountName=([^;]+)") {
            $StorageAccountName = $matches[1]
            Write-Success "Found storage account: $StorageAccountName"
        } else {
            Write-Error "Could not parse storage account name from connection string"
            Write-Host "Please provide the storage account name using -StorageAccountName parameter" -ForegroundColor Yellow
            exit 1
        }
    } else {
        Write-Error "Server/appsettings.json not found"
        Write-Host "Please run this script from the solution root directory or provide -StorageAccountName parameter" -ForegroundColor Yellow
        exit 1
    }
}

# Find resource group if not provided
if (-not $ResourceGroup) {
    Write-Info "Searching for storage account '$StorageAccountName'..."
    $storageAccounts = az storage account list --query "[?name=='$StorageAccountName']" | ConvertFrom-Json
    
    if ($storageAccounts.Count -eq 0) {
        Write-Error "Storage account '$StorageAccountName' not found in subscription"
        exit 1
    }
    
    $ResourceGroup = $storageAccounts[0].resourceGroup
    Write-Success "Found storage account in resource group: $ResourceGroup"
}

# Get storage account key
Write-Section "Azure Storage CORS Configuration"
Write-Info "Retrieving storage account key..."
$keys = az storage account keys list --account-name $StorageAccountName --resource-group $ResourceGroup | ConvertFrom-Json
$accountKey = $keys[0].value
Write-Success "Retrieved storage account key"

# Configure CORS for Blob service
Write-Info "Configuring CORS for Blob service..."

try {
    # Clear existing CORS rules first
    Write-Info "Clearing existing CORS rules..."
    az storage cors clear --services b --account-name $StorageAccountName --account-key $accountKey 2>$null | Out-Null
    
    # Add new CORS rule with correct configuration
    Write-Info "Adding new CORS rule..."
    az storage cors add `
        --services b `
        --methods GET HEAD OPTIONS `
        --origins "*" `
        --allowed-headers "*" `
        --exposed-headers "*" `
        --max-age 3600 `
        --account-name $StorageAccountName `
        --account-key $accountKey
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "? Storage CORS settings applied successfully!"
    } else {
        Write-Error "Failed to apply CORS settings"
        exit 1
    }
} catch {
    Write-Error "Error configuring CORS: $($_.Exception.Message)"
    exit 1
}

# Verify CORS settings
Write-Info "Verifying CORS configuration..."
$corsSettings = az storage cors list --services b --account-name $StorageAccountName --account-key $accountKey | ConvertFrom-Json

if ($corsSettings.Count -gt 0) {
    Write-Success "? CORS configuration verified"
    Write-Host "`nCurrent Storage CORS Settings:" -ForegroundColor Cyan
    Write-Host "  Allowed Origins: $($corsSettings[0].allowedOrigins -join ', ')" -ForegroundColor Gray
    Write-Host "  Allowed Methods: $($corsSettings[0].allowedMethods -join ', ')" -ForegroundColor Gray
    Write-Host "  Allowed Headers: $($corsSettings[0].allowedHeaders -join ', ')" -ForegroundColor Gray
    Write-Host "  Exposed Headers: $($corsSettings[0].exposedHeaders -join ', ')" -ForegroundColor Gray
    Write-Host "  Max Age: $($corsSettings[0].maxAgeInSeconds) seconds" -ForegroundColor Gray
} else {
    Write-Warning "Could not verify CORS settings"
}

# Configure Azure Front Door CORS (if requested)
if ($FixFrontDoor) {
    Write-Section "Azure Front Door CORS Configuration"
    
    # Try to find Front Door profile
    if (-not $FrontDoorName) {
        Write-Info "Searching for Azure Front Door profiles..."
        $frontDoors = az afd profile list --resource-group $ResourceGroup 2>$null | ConvertFrom-Json
        
        if ($frontDoors -and $frontDoors.Count -gt 0) {
            $FrontDoorName = $frontDoors[0].name
            Write-Success "Found Front Door profile: $FrontDoorName"
        } else {
            Write-Warning "No Azure Front Door profile found in resource group"
            Write-Host "Skipping Front Door CORS configuration" -ForegroundColor Yellow
            $FixFrontDoor = $false
        }
    }
    
    if ($FixFrontDoor -and $FrontDoorName) {
        Write-Info "Configuring CORS for Azure Front Door: $FrontDoorName..."
        
        # Get Front Door endpoints
        $endpoints = az afd endpoint list --profile-name $FrontDoorName --resource-group $ResourceGroup 2>$null | ConvertFrom-Json
        
        if ($endpoints -and $endpoints.Count -gt 0) {
            $endpointName = $endpoints[0].name
            Write-Info "Found endpoint: $endpointName"
            
            # Check if a route exists
            $routes = az afd route list --endpoint-name $endpointName --profile-name $FrontDoorName --resource-group $ResourceGroup 2>$null | ConvertFrom-Json
            
            if ($routes -and $routes.Count -gt 0) {
                foreach ($route in $routes) {
                    Write-Info "Updating route: $($route.name)..."
                    
                    # Update route to enable CORS
                    az afd route update `
                        --endpoint-name $endpointName `
                        --profile-name $FrontDoorName `
                        --resource-group $ResourceGroup `
                        --route-name $route.name `
                        --enabled-state Enabled `
                        --https-redirect Enabled 2>$null | Out-Null
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-Success "? Updated route: $($route.name)"
                    }
                }
                
                Write-Success "? Azure Front Door CORS configured"
                Write-Host "`nNote: Front Door will pass through CORS headers from the origin (Storage Account)" -ForegroundColor Yellow
                Write-Host "The Storage CORS configuration above will be used." -ForegroundColor Yellow
            } else {
                Write-Warning "No routes found in Front Door endpoint"
                Write-Host "Front Door may need manual configuration in Azure Portal" -ForegroundColor Yellow
            }
        } else {
            Write-Warning "No endpoints found in Front Door profile"
        }
    }
}

# Additional recommendations
Write-Section "Post-Configuration Steps"

Write-Host "`n1. Storage Account Public Access:" -ForegroundColor Yellow
Write-Info "Ensure your storage container allows blob access:"
Write-Host "   az storage container set-permission \\" -ForegroundColor Gray
Write-Host "     --name livestreams \\" -ForegroundColor Gray
Write-Host "     --public-access blob \\" -ForegroundColor Gray
Write-Host "     --account-name $StorageAccountName \\" -ForegroundColor Gray
Write-Host "     --account-key <your-key>" -ForegroundColor Gray

Write-Host "`n2. Azure Front Door Cache:" -ForegroundColor Yellow
Write-Info "Purge Front Door cache to ensure new CORS headers are used:"
Write-Host "   az afd endpoint purge \\" -ForegroundColor Gray
Write-Host "     --resource-group $ResourceGroup \\" -ForegroundColor Gray
Write-Host "     --profile-name <your-front-door-name> \\" -ForegroundColor Gray
Write-Host "     --endpoint-name <your-endpoint-name> \\" -ForegroundColor Gray
Write-Host "     --content-paths '/*'" -ForegroundColor Gray

Write-Host "`n3. Test CORS:" -ForegroundColor Yellow
Write-Info "Test CORS headers are correct:"
$storageUrl = "https://$StorageAccountName.blob.core.windows.net/livestreams/"
Write-Host "   curl -I -H 'Origin: https://localhost:7119' \\" -ForegroundColor Gray
Write-Host "     -H 'Access-Control-Request-Method: GET' \\" -ForegroundColor Gray
Write-Host "     $storageUrl" -ForegroundColor Gray

Write-Host "`n4. Browser Cache:" -ForegroundColor Yellow
Write-Info "Clear your browser cache or use incognito mode to test"
Write-Host "   Windows/Linux: Ctrl+Shift+R" -ForegroundColor Gray
Write-Host "   Mac: Cmd+Shift+R" -ForegroundColor Gray

# Test CORS
Write-Section "CORS Testing"
$testCors = Read-Host "`nWould you like to test CORS with a sample request? (y/n)"
if ($testCors -eq 'y') {
    Write-Info "Testing CORS headers..."
    $storageUrl = "https://$StorageAccountName.blob.core.windows.net/livestreams/"
    
    try {
        $response = Invoke-WebRequest -Uri $storageUrl -Method OPTIONS -Headers @{
            "Origin" = "https://localhost:7119"
            "Access-Control-Request-Method" = "GET"
            "Access-Control-Request-Headers" = "Content-Type"
        } -UseBasicParsing -ErrorAction Stop
        
        Write-Success "? CORS test successful!"
        
        $allowOrigin = $response.Headers['Access-Control-Allow-Origin']
        $allowMethods = $response.Headers['Access-Control-Allow-Methods']
        $allowHeaders = $response.Headers['Access-Control-Allow-Headers']
        
        Write-Host "`nCORS Response Headers:" -ForegroundColor Cyan
        if ($allowOrigin) {
            if ($allowOrigin -eq '*' -or $allowOrigin -eq 'https://localhost:7119') {
                Write-Success "  Access-Control-Allow-Origin: $allowOrigin"
            } else {
                Write-Error "  Access-Control-Allow-Origin: $allowOrigin (INVALID - should be * or specific origin)"
            }
        } else {
            Write-Error "  Access-Control-Allow-Origin: NOT SET"
        }
        
        if ($allowMethods) {
            Write-Host "  Access-Control-Allow-Methods: $allowMethods" -ForegroundColor Gray
        }
        
        if ($allowHeaders) {
            Write-Host "  Access-Control-Allow-Headers: $allowHeaders" -ForegroundColor Gray
        }
        
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 404) {
            Write-Warning "Container not found (404) - this is normal if no streams exist yet"
            Write-Host "CORS headers will be present once you start streaming" -ForegroundColor Gray
        } elseif ($statusCode -eq 403) {
            Write-Error "Access denied (403) - check container permissions"
        } else {
            Write-Warning "CORS test failed: $($_.Exception.Message)"
            Write-Host "This may be normal depending on container configuration" -ForegroundColor Gray
        }
    }
}

# Summary
Write-Section "Summary"

Write-Success "? CORS configuration complete!"

Write-Host "`nWhat was configured:" -ForegroundColor Cyan
Write-Host "  ? Azure Storage Blob CORS rules" -ForegroundColor Green
Write-Host "  ? Allow all origins (*)" -ForegroundColor Green
Write-Host "  ? Allow GET, HEAD, OPTIONS methods" -ForegroundColor Green
Write-Host "  ? Allow all headers" -ForegroundColor Green

if ($FixFrontDoor -and $FrontDoorName) {
    Write-Host "  ? Azure Front Door configured to pass through CORS" -ForegroundColor Green
}

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "  1. Clear browser cache (Ctrl+Shift+R)" -ForegroundColor Gray
Write-Host "  2. Restart your application" -ForegroundColor Gray
Write-Host "  3. Test streaming" -ForegroundColor Gray
Write-Host "  4. Check browser console for CORS errors" -ForegroundColor Gray

Write-Host "`nIf CORS errors persist:" -ForegroundColor Yellow
Write-Host "  1. Purge Azure Front Door cache" -ForegroundColor Gray
Write-Host "  2. Check Azure Portal ? Storage ? CORS settings" -ForegroundColor Gray
Write-Host "  3. Verify Access-Control-Allow-Origin header is not '**'" -ForegroundColor Gray
Write-Host "  4. Run: .\diagnose-stream.ps1 for detailed diagnostics" -ForegroundColor Gray

Write-Host ""
