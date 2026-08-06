# Azure LiveStream App Deployment & Configuration Script
# Consolidated script for complete Azure deployment, configuration, and diagnostics
# Version: 2.0

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('Setup', 'Deploy', 'Configure', 'Diagnose', 'Check')]
    [string]$Action = 'Setup',
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = 'Trial',
    
    [Parameter(Mandatory=$false)]
    [string]$StorageAccountName = 'livestreamtrial',
    
    [Parameter(Mandatory=$false)]
    [string]$AcrName = 'livestreamacr',
    
    [Parameter(Mandatory=$false)]
    [string]$AppName = 'livestream-app',
    
    [Parameter(Mandatory=$false)]
    [string]$FrontDoorProfileName = 'livestream-cdn',
    
    [Parameter(Mandatory=$false)]
    [string]$FrontDoorEndpointName = 'livestream-signalr-service',
    
    [Parameter(Mandatory=$false)]
    [string]$Location = 'germanywestcentral',
    
    [Parameter(Mandatory=$false)]
    [string]$StreamId,
    
    [Parameter(Mandatory=$false)]
    [string]$ServerUrl = 'https://localhost:7119'
)

# ==================== COMMON FUNCTIONS ====================

function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "   $Title" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
}

function Write-Success {
    param([string]$Message)
    Write-Host "? $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "? $Message" -ForegroundColor Red
}

function Write-Warning {
    param([string]$Message)
    Write-Host "? $Message" -ForegroundColor Yellow
}

function Write-Info {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor White
}

function Test-AzureCLI {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Error "Azure CLI is not installed"
        Write-Info "Install from: https://docs.microsoft.com/cli/azure/install-azure-cli"
        return $false
    }
    Write-Success "Azure CLI is installed"
    return $true
}

function Test-AzureLogin {
    $account = az account show 2>$null | ConvertFrom-Json
    if (-not $account) {
        Write-Step "Not logged in to Azure. Logging in..."
        az login
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to login to Azure"
            return $false
        }
        $account = az account show | ConvertFrom-Json
    }
    Write-Success "Logged in as: $($account.user.name)"
    Write-Info "Subscription: $($account.name)"
    return $true
}

function Test-FFmpeg {
    try {
        $ffmpegVersion = & ffmpeg -version 2>&1 | Select-Object -First 1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "FFmpeg is installed"
            return $true
        }
    } catch {
        Write-Error "FFmpeg not found in PATH"
        Write-Info "Install: choco install ffmpeg OR winget install ffmpeg"
        return $false
    }
    return $false
}

function Get-StorageAccountName {
    param([string]$ConnectionString)
    
    if ($ConnectionString -match "AccountName=([^;]+)") {
        return $Matches[1]
    }
    return $null
}

# ==================== SETUP ACTION ====================

function Invoke-Setup {
    Write-Header "Azure Front Door Setup for Live Streaming"
    Write-Warning "Note: Azure CDN is being retired. Using Azure Front Door instead."
    Write-Host ""
    
    if (-not (Test-AzureCLI)) { return }
    if (-not (Test-AzureLogin)) { return }
    
    # Check and create resource group
    Write-Step "Checking resource group..."
    $rgExists = az group show --name $ResourceGroupName 2>$null
    if (-not $rgExists) {
        Write-Warning "Resource group '$ResourceGroupName' not found"
        Write-Info "Available resource groups:"
        az group list --query "[].name" -o tsv | ForEach-Object { Write-Info "  - $_" }
        Write-Host ""
        
        $response = Read-Host "Create resource group '$ResourceGroupName'? (Y/N)"
        if ($response -eq 'Y' -or $response -eq 'y') {
            az group create --name $ResourceGroupName --location $Location --output none
            Write-Success "Resource group created"
        } else {
            Write-Error "Setup cancelled"
            return
        }
    } else {
        Write-Success "Resource group exists"
    }
    
    # Register providers
    Write-Host ""
    Write-Step "Registering Azure providers..."
    az provider register --namespace Microsoft.Cdn --output none
    az provider register --namespace Microsoft.Network --output none
    Write-Success "Providers registered"
    
    # Create Front Door profile
    Write-Host ""
    Write-Step "Creating Front Door profile..."
    $profileExists = az afd profile show --profile-name $FrontDoorProfileName --resource-group $ResourceGroupName 2>$null
    
    if (-not $profileExists) {
        az afd profile create `
            --profile-name $FrontDoorProfileName `
            --resource-group $ResourceGroupName `
            --sku Standard_AzureFrontDoor `
            --output none
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Front Door profile created"
        } else {
            Write-Error "Failed to create Front Door profile"
            return
        }
    } else {
        Write-Success "Front Door profile exists"
    }
    
    # Create endpoint
    Write-Host ""
    Write-Step "Creating Front Door endpoint..."
    $endpointExists = az afd endpoint show `
        --endpoint-name $FrontDoorEndpointName `
        --profile-name $FrontDoorProfileName `
        --resource-group $ResourceGroupName 2>$null
    
    if (-not $endpointExists) {
        az afd endpoint create `
            --endpoint-name $FrontDoorEndpointName `
            --profile-name $FrontDoorProfileName `
            --resource-group $ResourceGroupName `
            --enabled-state Enabled `
            --output none
        
        if ($LASTEXITCODE -eq 0) {
            $endpoint = az afd endpoint show `
                --endpoint-name $FrontDoorEndpointName `
                --profile-name $FrontDoorProfileName `
                --resource-group $ResourceGroupName | ConvertFrom-Json
            $frontDoorHostname = $endpoint.hostName
            Write-Success "Front Door endpoint created"
            Write-Info "Hostname: $frontDoorHostname"
        }
    } else {
        $endpoint = $endpointExists | ConvertFrom-Json
        $frontDoorHostname = $endpoint.hostName
        Write-Success "Front Door endpoint exists"
        Write-Info "Hostname: $frontDoorHostname"
    }
    
    # Create origin group
    Write-Host ""
    Write-Step "Creating origin group..."
    $originGroupName = "storage-origin-group"
    $originGroupExists = az afd origin-group show `
        --origin-group-name $originGroupName `
        --profile-name $FrontDoorProfileName `
        --resource-group $ResourceGroupName 2>$null
    
    if (-not $originGroupExists) {
        az afd origin-group create `
            --origin-group-name $originGroupName `
            --profile-name $FrontDoorProfileName `
            --resource-group $ResourceGroupName `
            --probe-request-type GET `
            --probe-protocol Https `
            --probe-interval-in-seconds 100 `
            --probe-path "/" `
            --sample-size 4 `
            --successful-samples-required 3 `
            --additional-latency-in-milliseconds 50 `
            --output none
        Write-Success "Origin group created"
    } else {
        Write-Success "Origin group exists"
    }
    
    # Create storage origin
    Write-Host ""
    Write-Step "Creating storage origin..."
    $originName = "storage-origin"
    $storageHostname = "$StorageAccountName.blob.core.windows.net"
    
    $originExists = az afd origin show `
        --origin-name $originName `
        --origin-group-name $originGroupName `
        --profile-name $FrontDoorProfileName `
        --resource-group $ResourceGroupName 2>$null
    
    if (-not $originExists) {
        az afd origin create `
            --origin-name $originName `
            --origin-group-name $originGroupName `
            --profile-name $FrontDoorProfileName `
            --resource-group $ResourceGroupName `
            --host-name $storageHostname `
            --origin-host-header $storageHostname `
            --priority 1 `
            --weight 1000 `
            --enabled-state Enabled `
            --http-port 80 `
            --https-port 443 `
            --output none
        Write-Success "Storage origin created"
    } else {
        Write-Success "Storage origin exists"
    }
    
    # Create route
    Write-Host ""
    Write-Step "Creating route..."
    $routeName = "livestreams-route"
    $routeExists = az afd route show `
        --route-name $routeName `
        --endpoint-name $FrontDoorEndpointName `
        --profile-name $FrontDoorProfileName `
        --resource-group $ResourceGroupName 2>$null
    
    if (-not $routeExists) {
        az afd route create `
            --route-name $routeName `
            --endpoint-name $FrontDoorEndpointName `
            --profile-name $FrontDoorProfileName `
            --resource-group $ResourceGroupName `
            --origin-group $originGroupName `
            --supported-protocols Http Https `
            --link-to-default-domain Enabled `
            --https-redirect Enabled `
            --forwarding-protocol HttpsOnly `
            --patterns-to-match "/livestreams/*" `
            --enable-compression true `
            --query-string-caching-behavior IgnoreQueryString `
            --output none
        Write-Success "Route created"
    } else {
        Write-Success "Route exists"
    }
    
    # Configure CORS
    Write-Host ""
    Write-Step "Configuring CORS rules..."
    $ruleSetName = "CORSRules"
    
    $ruleSetExists = az afd rule-set show `
        --rule-set-name $ruleSetName `
        --profile-name $FrontDoorProfileName `
        --resource-group $ResourceGroupName 2>$null
    
    if (-not $ruleSetExists) {
        az afd rule-set create `
            --rule-set-name $ruleSetName `
            --profile-name $FrontDoorProfileName `
            --resource-group $ResourceGroupName `
            --output none
    }
    
    # Add CORS rules
    az afd rule create `
        --rule-name "AddCORSOrigin" `
        --rule-set-name $ruleSetName `
        --profile-name $FrontDoorProfileName `
        --resource-group $ResourceGroupName `
        --order 1 `
        --match-variable RequestUri `
        --operator Contains `
        --match-values "/livestreams/" `
        --action-name ModifyResponseHeader `
        --header-action Override `
        --header-name "Access-Control-Allow-Origin" `
        --header-value "*" `
        --output none 2>$null
    
    Write-Success "CORS rules configured"
    
    # Associate rule set with route
    az afd route update `
        --route-name $routeName `
        --endpoint-name $FrontDoorEndpointName `
        --profile-name $FrontDoorProfileName `
        --resource-group $ResourceGroupName `
        --rule-sets $ruleSetName `
        --output none 2>$null
    
    # Configure storage CORS
    Write-Host ""
    Write-Step "Configuring Azure Storage CORS..."
    az storage cors clear --services b --account-name $StorageAccountName 2>$null | Out-Null
    az storage cors add `
        --services b `
        --methods GET HEAD OPTIONS `
        --origins "*" `
        --allowed-headers "*" `
        --exposed-headers "*" `
        --max-age 3600 `
        --account-name $StorageAccountName `
        --output none 2>$null
    
    az storage container set-permission `
        --name livestreams `
        --public-access blob `
        --account-name $StorageAccountName `
        --output none 2>$null
    
    Write-Success "Storage CORS configured"
    
    # Summary
    Write-Header "Setup Complete!"
    Write-Success "Front Door Endpoint: https://$frontDoorHostname/livestreams"
    Write-Host ""
    Write-Info "Update your appsettings.json:"
    Write-Host '  "Azure": {' -ForegroundColor White
    Write-Host '    "CDN": {' -ForegroundColor White
    Write-Host "      `"BaseUrl`": `"https://$frontDoorHostname/livestreams`"" -ForegroundColor Cyan
    Write-Host '    }' -ForegroundColor White
    Write-Host '  }' -ForegroundColor White
    Write-Host ""
    Write-Warning "Note: Front Door propagation takes 5-10 minutes"
}

# ==================== DEPLOY ACTION ====================

function Invoke-Deploy {
    Write-Header "Azure Container Registry Deployment"
    
    if (-not (Test-AzureCLI)) { return }
    if (-not (Test-AzureLogin)) { return }
    
    # Create resource group
    Write-Step "Creating resource group..."
    az group create --name $ResourceGroupName --location $Location --output none
    Write-Success "Resource group ready"
    
    # Create ACR
    Write-Host ""
    Write-Step "Creating Azure Container Registry..."
    az acr create `
        --resource-group $ResourceGroupName `
        --name $AcrName `
        --sku Basic `
        --admin-enabled true `
        --output none
    Write-Success "ACR ready"
    
    # Build and push
    Write-Host ""
    Write-Step "Building and pushing Docker image..."
    az acr build `
        --registry $AcrName `
        --image "livestreamapp:latest" `
        --file Server/Dockerfile `
        .
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Image pushed successfully"
        
        $acrLoginServer = az acr show --name $AcrName --resource-group $ResourceGroupName --query loginServer --output tsv
        Write-Host ""
        Write-Success "Image: $acrLoginServer/livestreamapp:latest"
        Write-Host ""
        Write-Info "Deploy to Azure Container Instances:"
        Write-Info "  az container create --resource-group $ResourceGroupName --name $AppName \"
        Write-Info "    --image $acrLoginServer/livestreamapp:latest \"
        Write-Info "    --dns-name-label $AppName --ports 8080 --cpu 2 --memory 4"
    }
}

# ==================== CONFIGURE ACTION ====================

function Invoke-Configure {
    Write-Header "Azure Storage CORS Configuration"
    
    if (-not (Test-AzureCLI)) { return }
    if (-not (Test-AzureLogin)) { return }
    
    # Read configuration
    $config = Get-Content -Path "Server/appsettings.json" -Raw | ConvertFrom-Json
    $connectionString = $config.AzureStorage.ConnectionString
    $containerName = $config.AzureStorage.ContainerName
    
    $accountName = Get-StorageAccountName -ConnectionString $connectionString
    if (-not $accountName) {
        Write-Error "Could not parse storage account name from connection string"
        return
    }
    
    Write-Success "Storage Account: $accountName"
    Write-Success "Container: $containerName"
    
    # Configure CORS
    Write-Host ""
    Write-Step "Configuring CORS..."
    az storage cors add `
        --services b `
        --methods GET HEAD OPTIONS `
        --origins "*" `
        --allowed-headers "*" `
        --exposed-headers "*" `
        --max-age 3600 `
        --account-name $accountName `
        --connection-string $connectionString `
        --output none 2>$null
    
    # Set container access
    az storage container set-permission `
        --name $containerName `
        --account-name $accountName `
        --public-access blob `
        --connection-string $connectionString `
        --output none 2>$null
    
    Write-Success "CORS configured successfully"
    Write-Host ""
    Write-Info "Storage URL: https://$accountName.blob.core.windows.net/$containerName"
}

# ==================== DIAGNOSE ACTION ====================

function Invoke-Diagnose {
    Write-Header "Stream Diagnostics"
    
    if ([string]::IsNullOrEmpty($StreamId)) {
        $StreamId = Read-Host "Enter Stream ID"
    }
    
    Write-Info "Diagnosing stream: $StreamId"
    Write-Info "Server URL: $ServerUrl"
    Write-Host ""
    
    # Check server
    Write-Step "Checking if server is running..."
    try {
        Invoke-RestMethod -Uri "$ServerUrl/health" -Method Get -TimeoutSec 5 | Out-Null
        Write-Success "Server is running"
    } catch {
        Write-Error "Server is not responding"
        Write-Info "Start the server: dotnet run --project Server"
        return
    }
    
    # Check stream status
    Write-Host ""
    Write-Step "Checking stream status..."
    try {
        $statusUrl = "$ServerUrl/api/streamingest/status/$StreamId"
        $statusResponse = Invoke-RestMethod -Uri $statusUrl -Method Get -TimeoutSec 5
        Write-Success "Stream found on server"
        Write-Info "Status: $($statusResponse.status)"
        Write-Info "Chunks Received: $($statusResponse.metadata.ChunksReceived)"
    } catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            Write-Warning "Stream NOT found on server"
            Write-Info "Start the broadcaster at $ServerUrl/broadcast"
        } else {
            Write-Error "Error checking stream: $($_.Exception.Message)"
        }
        return
    }
    
    # Check configuration
    Write-Host ""
    Write-Step "Checking configuration..."
    $config = Get-Content -Path "Server/appsettings.json" -Raw | ConvertFrom-Json
    $cdnUrl = $config.Azure.CDN.BaseUrl
    
    if ($cdnUrl) {
        Write-Success "CDN URL: $cdnUrl"
        Write-Info "Expected Stream URL: $cdnUrl/$StreamId/index.m3u8"
    } else {
        Write-Warning "CDN URL not configured"
    }
    
    # Check FFmpeg
    Write-Host ""
    Test-FFmpeg | Out-Null
}

# ==================== CHECK ACTION ====================

function Invoke-Check {
    Write-Header "Live Stream Setup Checker"
    
    $allGood = $true
    
    # Check FFmpeg
    Write-Step "Checking FFmpeg..."
    if (-not (Test-FFmpeg)) { $allGood = $false }
    
    # Check Azure Storage
    Write-Host ""
    Write-Step "Checking Azure Storage configuration..."
    $serverConfig = Get-Content -Path "Server/appsettings.json" -Raw | ConvertFrom-Json
    $connectionString = $serverConfig.AzureStorage.ConnectionString
    
    if ($connectionString -and $connectionString -like "*AccountName=*") {
        Write-Success "Azure Storage connection string configured"
        $accountName = Get-StorageAccountName -ConnectionString $connectionString
        Write-Info "Storage Account: $accountName"
    } else {
        Write-Error "Azure Storage connection string missing or invalid"
        $allGood = $false
    }
    
    # Check CDN
    Write-Host ""
    Write-Step "Checking CDN configuration..."
    $cdnUrl = $serverConfig.Azure.CDN.BaseUrl
    
    if ($cdnUrl) {
        Write-Success "CDN URL configured: $cdnUrl"
    } else {
        Write-Error "CDN URL missing"
        $allGood = $false
    }
    
    # Check build
    Write-Host ""
    Write-Step "Checking if solution builds..."
    try {
        $buildOutput = dotnet build --no-restore --verbosity quiet 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Solution builds successfully"
        } else {
            Write-Error "Build failed"
            $allGood = $false
        }
    } catch {
        Write-Warning "Could not verify build"
    }
    
    # Summary
    Write-Host ""
    Write-Header "Summary"
    if ($allGood) {
        Write-Success "All checks passed! Ready to stream."
        Write-Host ""
        Write-Info "Next steps:"
        Write-Info "  1. Run: dotnet run --project Server"
        Write-Info "  2. Navigate to /broadcast to start streaming"
        Write-Info "  3. Share the viewer link with your audience"
    } else {
        Write-Error "Some checks failed. Please fix the issues above."
    }
}

# ==================== MAIN ====================

Write-Host ""
Write-Host "??????????????????????????????????????????????????" -ForegroundColor Cyan
Write-Host "?   Azure LiveStream App Deployment Script      ?" -ForegroundColor Cyan
Write-Host "??????????????????????????????????????????????????" -ForegroundColor Cyan

switch ($Action) {
    'Setup'     { Invoke-Setup }
    'Deploy'    { Invoke-Deploy }
    'Configure' { Invoke-Configure }
    'Diagnose'  { Invoke-Diagnose }
    'Check'     { Invoke-Check }
}

Write-Host ""
