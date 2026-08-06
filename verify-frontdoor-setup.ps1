# Verify Azure Front Door Setup for Live Streaming

param(
    [string]$FrontDoorProfileName = "livestream-cdn",
    [string]$StorageAccountName = "livestreamtrial"
)

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "   Azure Front Door Verification Tool" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Check Azure CLI
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "✗ Azure CLI is not installed" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please install from:" -ForegroundColor Yellow
    Write-Host "https://docs.microsoft.com/cli/azure/install-azure-cli" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Alternative: Test Front Door manually in Azure Portal" -ForegroundColor Yellow
    exit 1
}

# Check login
Write-Host "Checking Azure login..." -ForegroundColor Yellow
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "Not logged in. Logging in..." -ForegroundColor Yellow
    az login
    if ($LASTEXITCODE -ne 0) {
        Write-Host "✗ Failed to login to Azure" -ForegroundColor Red
        exit 1
    }
    $account = az account show | ConvertFrom-Json
}

Write-Host "✓ Logged in as: $($account.user.name)" -ForegroundColor Green
Write-Host "  Subscription: $($account.name)" -ForegroundColor White
Write-Host ""

# Search for Front Door profiles
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Searching for Front Door Profile..." -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

$profiles = az afd profile list 2>$null | ConvertFrom-Json

if (-not $profiles -or $profiles.Count -eq 0) {
    Write-Host "✗ No Front Door profiles found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Azure Front Door has not been set up yet." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Create Front Door (Recommended for production):" -ForegroundColor Yellow
    Write-Host "   Run: .\setup-azure-frontdoor.ps1" -ForegroundColor White
    Write-Host ""
    Write-Host "2. Use direct storage access (Quick test):" -ForegroundColor Yellow
    Write-Host "   Update appsettings.json:" -ForegroundColor White
    Write-Host '   "BaseUrl": "https://livestreamtrial.blob.core.windows.net/livestreams"' -ForegroundColor Cyan
    Write-Host "   Then run: .\configure-storage-cors.ps1" -ForegroundColor White
    Write-Host ""
    exit 0
}

# Find the matching profile
$profile = $profiles | Where-Object { $_.name -eq $FrontDoorProfileName }

if (-not $profile) {
    Write-Host "Profile '$FrontDoorProfileName' not found" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Available Front Door profiles:" -ForegroundColor Cyan
    foreach ($p in $profiles) {
        Write-Host "  - $($p.name)" -ForegroundColor White
        Write-Host "    Resource Group: $($p.resourceGroup)" -ForegroundColor Gray
        Write-Host "    SKU: $($p.sku.name)" -ForegroundColor Gray
    }
    Write-Host ""
    
    if ($profiles.Count -eq 1) {
        $profile = $profiles[0]
        $FrontDoorProfileName = $profile.name
        Write-Host "Using profile: $FrontDoorProfileName" -ForegroundColor Cyan
        Write-Host ""
    } else {
        Write-Host "Please specify the correct profile name:" -ForegroundColor Yellow
        Write-Host "  .\verify-frontdoor-setup.ps1 -FrontDoorProfileName 'YOUR_PROFILE_NAME'" -ForegroundColor White
        Write-Host ""
        exit 0
    }
}

$resourceGroup = $profile.resourceGroup

Write-Host "✓ Front Door Profile Found!" -ForegroundColor Green
Write-Host ""
Write-Host "Profile Details:" -ForegroundColor Cyan
Write-Host "  Name: $($profile.name)" -ForegroundColor White
Write-Host "  Resource Group: $($profile.resourceGroup)" -ForegroundColor White
Write-Host "  SKU: $($profile.sku.name)" -ForegroundColor White
Write-Host "  Location: $($profile.location)" -ForegroundColor White
Write-Host "  Provisioning State: $($profile.provisioningState)" -ForegroundColor $(if ($profile.provisioningState -eq 'Succeeded') { 'Green' } else { 'Yellow' })
Write-Host ""

# Check endpoints
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Checking Endpoints..." -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

$endpoints = az afd endpoint list `
    --profile-name $FrontDoorProfileName `
    --resource-group $resourceGroup 2>$null | ConvertFrom-Json

if (-not $endpoints -or $endpoints.Count -eq 0) {
    Write-Host "✗ No endpoints found!" -ForegroundColor Red
    Write-Host "  Run: .\setup-azure-frontdoor.ps1" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host "✓ Found $($endpoints.Count) endpoint(s)" -ForegroundColor Green
    Write-Host ""
    
    foreach ($endpoint in $endpoints) {
        Write-Host "Endpoint: $($endpoint.name)" -ForegroundColor Cyan
        Write-Host "  Hostname: $($endpoint.hostName)" -ForegroundColor White
        Write-Host "  Status: $($endpoint.enabledState)" -ForegroundColor $(if ($endpoint.enabledState -eq 'Enabled') { 'Green' } else { 'Red' })
        Write-Host "  Provisioning: $($endpoint.provisioningState)" -ForegroundColor $(if ($endpoint.provisioningState -eq 'Succeeded') { 'Green' } else { 'Yellow' })
        Write-Host ""
        
        $frontDoorUrl = "https://$($endpoint.hostName)/livestreams"
    }
}

# Check origin groups
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Checking Origin Groups..." -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

$originGroups = az afd origin-group list `
    --profile-name $FrontDoorProfileName `
    --resource-group $resourceGroup 2>$null | ConvertFrom-Json

if (-not $originGroups -or $originGroups.Count -eq 0) {
    Write-Host "✗ No origin groups found!" -ForegroundColor Red
} else {
    Write-Host "✓ Found $($originGroups.Count) origin group(s)" -ForegroundColor Green
    Write-Host ""
    
    foreach ($originGroup in $originGroups) {
        Write-Host "Origin Group: $($originGroup.name)" -ForegroundColor Cyan
        
        # Get origins in this group
        $origins = az afd origin list `
            --origin-group-name $originGroup.name `
            --profile-name $FrontDoorProfileName `
            --resource-group $resourceGroup 2>$null | ConvertFrom-Json
        
        if ($origins) {
            foreach ($origin in $origins) {
                Write-Host "  Origin: $($origin.name)" -ForegroundColor White
                Write-Host "    Host: $($origin.hostName)" -ForegroundColor Gray
                Write-Host "    Status: $($origin.enabledState)" -ForegroundColor $(if ($origin.enabledState -eq 'Enabled') { 'Green' } else { 'Red' })
                
                # Check if origin matches storage
                $expectedOrigin = "$StorageAccountName.blob.core.windows.net"
                if ($origin.hostName -eq $expectedOrigin) {
                    Write-Host "    ✓ Correctly points to storage account" -ForegroundColor Green
                } else {
                    Write-Host "    ⚠ Expected: $expectedOrigin" -ForegroundColor Yellow
                }
            }
        }
        Write-Host ""
    }
}

# Check routes
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Checking Routes..." -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

if ($endpoints) {
    foreach ($endpoint in $endpoints) {
        $routes = az afd route list `
            --endpoint-name $endpoint.name `
            --profile-name $FrontDoorProfileName `
            --resource-group $resourceGroup 2>$null | ConvertFrom-Json
        
        if ($routes -and $routes.Count -gt 0) {
            Write-Host "✓ Found $($routes.Count) route(s) for endpoint: $($endpoint.name)" -ForegroundColor Green
            foreach ($route in $routes) {
                Write-Host "  Route: $($route.name)" -ForegroundColor Cyan
                Write-Host "    Patterns: $($route.patternsToMatch -join ', ')" -ForegroundColor Gray
                Write-Host "    HTTPS: $($route.httpsRedirect)" -ForegroundColor Gray
            }
        } else {
            Write-Host "✗ No routes found for endpoint: $($endpoint.name)" -ForegroundColor Red
        }
        Write-Host ""
    }
}

# Check Storage CORS
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Checking Storage CORS..." -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

try {
    $corsRules = az storage cors list `
        --services b `
        --account-name $StorageAccountName 2>$null | ConvertFrom-Json
    
    if ($corsRules -and $corsRules.Count -gt 0) {
        Write-Host "✓ CORS rules configured:" -ForegroundColor Green
        foreach ($rule in $corsRules) {
            Write-Host "  Origins: $($rule.allowedOrigins -join ', ')" -ForegroundColor White
            Write-Host "  Methods: $($rule.allowedMethods -join ', ')" -ForegroundColor White
            Write-Host "  Max Age: $($rule.maxAgeInSeconds)s" -ForegroundColor White
        }
        
        $hasWildcard = $corsRules | Where-Object { $_.allowedOrigins -contains '*' }
        if ($hasWildcard) {
            Write-Host "  ✓ Wildcard origins allowed (*)" -ForegroundColor Green
        }
    } else {
        Write-Host "✗ No CORS rules configured!" -ForegroundColor Red
        Write-Host "  Run: .\configure-storage-cors.ps1" -ForegroundColor White
    }
} catch {
    Write-Host "⚠ Could not check CORS configuration" -ForegroundColor Yellow
}
Write-Host ""

# Check container public access
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Checking Container Public Access..." -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

try {
    $containerAccess = az storage container show `
        --name livestreams `
        --account-name $StorageAccountName `
        --query "properties.publicAccess" `
        --output tsv 2>$null
    
    if ($containerAccess -eq "blob" -or $containerAccess -eq "container") {
        Write-Host "✓ Container public access enabled: $containerAccess" -ForegroundColor Green
    } else {
        Write-Host "✗ Container public access NOT enabled!" -ForegroundColor Red
        Write-Host "  Current: $containerAccess" -ForegroundColor White
        Write-Host "  Run: .\configure-storage-cors.ps1" -ForegroundColor White
    }
} catch {
    Write-Host "⚠ Could not check container access" -ForegroundColor Yellow
}
Write-Host ""

# Test accessibility
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Testing Accessibility..." -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Test storage
$storageUrl = "https://$StorageAccountName.blob.core.windows.net/livestreams/"
Write-Host "Testing storage: $storageUrl" -ForegroundColor White
try {
    $response = Invoke-WebRequest -Uri $storageUrl -Method Head -ErrorAction SilentlyContinue -TimeoutSec 10
    Write-Host "✓ Storage accessible" -ForegroundColor Green
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    if ($code -eq 404) {
        Write-Host "✓ Storage accessible (empty container)" -ForegroundColor Green
    } else {
        Write-Host "⚠ Storage returned: $code" -ForegroundColor Yellow
    }
}

# Test Front Door
if ($frontDoorUrl) {
    Write-Host "Testing Front Door: $frontDoorUrl" -ForegroundColor White
    try {
        $response = Invoke-WebRequest -Uri $frontDoorUrl -Method Head -ErrorAction SilentlyContinue -TimeoutSec 10
        Write-Host "✓ Front Door accessible" -ForegroundColor Green
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code -eq 404) {
            Write-Host "✓ Front Door accessible (empty path)" -ForegroundColor Green
        } elseif ($code -eq 0) {
            Write-Host "⚠ Front Door still propagating" -ForegroundColor Yellow
            Write-Host "  Wait 5-10 minutes" -ForegroundColor White
        } else {
            Write-Host "⚠ Front Door returned: $code" -ForegroundColor Yellow
        }
    }
}
Write-Host ""

# Summary
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

if ($frontDoorUrl) {
    Write-Host "Front Door URL:" -ForegroundColor Cyan
    Write-Host "  $frontDoorUrl" -ForegroundColor White
    Write-Host ""
    Write-Host "Update your appsettings.json:" -ForegroundColor Yellow
    Write-Host '  "Azure": { "CDN": { "BaseUrl": "' -NoNewline -ForegroundColor White
    Write-Host "$frontDoorUrl" -NoNewline -ForegroundColor Cyan
    Write-Host '" } }' -ForegroundColor White
    Write-Host ""
}

Write-Host "Test URLs:" -ForegroundColor Cyan
Write-Host "  Direct: $storageUrl[streamId]/index.m3u8" -ForegroundColor White
if ($frontDoorUrl) {
    Write-Host "  Front Door: $frontDoorUrl/[streamId]/index.m3u8" -ForegroundColor White
}
Write-Host ""

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Verification Complete" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
