#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Verifies Azure SignalR Service setup and diagnoses connection issues.

.DESCRIPTION
    This script checks:
    - Azure SignalR Service health and configuration
    - Connection string validity
    - Network connectivity to SignalR endpoint
    - Service tier and limits
    - Current usage and capacity

.PARAMETER ResourceGroup
    The Azure resource group containing the SignalR service

.PARAMETER SignalRName
    The name of the Azure SignalR Service

.PARAMETER ConnectionString
    Optional: Test a specific connection string

.EXAMPLE
    .\verify-signalr-setup.ps1 -ResourceGroup "myResourceGroup" -SignalRName "livestream-signalr-service"

.EXAMPLE
    .\verify-signalr-setup.ps1 -ConnectionString "Endpoint=https://..."
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup,
    
    [Parameter(Mandatory=$false)]
    [string]$SignalRName,
    
    [Parameter(Mandatory=$false)]
    [string]$ConnectionString,
    
    [Parameter(Mandatory=$false)]
    [switch]$UseLocal,
    
    [Parameter(Mandatory=$false)]
    [switch]$FixAppsettings
)

$ErrorActionPreference = "Continue"
$WarningPreference = "Continue"

# Color output functions
function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Write-Success {
    param([string]$Message)
    Write-ColorOutput "? $Message" "Green"
}

function Write-Failure {
    param([string]$Message)
    Write-ColorOutput "? $Message" "Red"
}

function Write-Warning-Custom {
    param([string]$Message)
    Write-ColorOutput "? $Message" "Yellow"
}

function Write-Info {
    param([string]$Message)
    Write-ColorOutput "? $Message" "Cyan"
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-ColorOutput "???????????????????????????????????????????????????????" "Magenta"
    Write-ColorOutput "  $Title" "Magenta"
    Write-ColorOutput "???????????????????????????????????????????????????????" "Magenta"
    Write-Host ""
}

# Parse connection string
function Parse-ConnectionString {
    param([string]$ConnStr)
    
    $result = @{
        Endpoint = ""
        AccessKey = ""
        Version = ""
        AuthType = ""
    }
    
    if ([string]::IsNullOrWhiteSpace($ConnStr)) {
        return $result
    }
    
    $parts = $ConnStr -split ";"
    foreach ($part in $parts) {
        if ($part -match "Endpoint=(.+)") {
            $result.Endpoint = $matches[1]
        }
        elseif ($part -match "AccessKey=(.+)") {
            $result.AccessKey = $matches[1].Substring(0, [Math]::Min(10, $matches[1].Length)) + "..."
        }
        elseif ($part -match "Version=(.+)") {
            $result.Version = $matches[1]
        }
        elseif ($part -match "AuthType=(.+)") {
            $result.AuthType = $matches[1]
        }
    }
    
    return $result
}

# Test network connectivity
function Test-SignalRConnectivity {
    param([string]$Endpoint)
    
    if ([string]::IsNullOrWhiteSpace($Endpoint)) {
        Write-Failure "No endpoint provided"
        return $false
    }
    
    # Extract hostname from endpoint
    $hostname = $Endpoint -replace "https://", "" -replace "http://", ""
    
    Write-Info "Testing connectivity to: $hostname"
    
    # Test DNS resolution
    try {
        $dnsResult = Resolve-DnsName -Name $hostname -ErrorAction Stop
        Write-Success "DNS resolution successful: $($dnsResult[0].IPAddress)"
    }
    catch {
        Write-Failure "DNS resolution failed: $($_.Exception.Message)"
        return $false
    }
    
    # Test HTTPS connection (port 443)
    Write-Info "Testing HTTPS connection (port 443)..."
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $asyncResult = $tcpClient.BeginConnect($hostname, 443, $null, $null)
        $wait = $asyncResult.AsyncWaitHandle.WaitOne(5000, $false)
        
        if ($wait -and $tcpClient.Connected) {
            Write-Success "TCP connection to port 443 successful"
            $tcpClient.Close()
        }
        else {
            Write-Failure "TCP connection to port 443 failed (timeout or refused)"
            $tcpClient.Close()
            return $false
        }
    }
    catch {
        Write-Failure "TCP connection test failed: $($_.Exception.Message)"
        return $false
    }
    
    # Test HTTP endpoint
    Write-Info "Testing HTTP GET request..."
    try {
        $response = Invoke-WebRequest -Uri $Endpoint -Method Get -TimeoutSec 10 -ErrorAction Stop
        Write-Success "HTTP endpoint is reachable (Status: $($response.StatusCode))"
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 404) {
            Write-Success "HTTP endpoint is reachable (404 expected for root path)"
        }
        else {
            Write-Warning-Custom "HTTP endpoint returned: $($_.Exception.Message)"
        }
    }
    
    return $true
}

# Check appsettings.json files
function Check-AppSettings {
    Write-Info "Checking Server/appsettings.json..."
    
    $appsettingsPath = "Server/appsettings.json"
    $appsettingsDevPath = "Server/appsettings.Development.json"
    
    if (-not (Test-Path $appsettingsPath)) {
        Write-Failure "appsettings.json not found at: $appsettingsPath"
        return $null
    }
    
    $appsettings = Get-Content $appsettingsPath -Raw | ConvertFrom-Json
    $connStr = $appsettings.Azure.SignalR.ConnectionString
    
    if ([string]::IsNullOrWhiteSpace($connStr)) {
        Write-Failure "Azure:SignalR:ConnectionString is empty or missing"
        return $null
    }
    
    Write-Success "Connection string found in appsettings.json"
    
    # Check development settings
    if (Test-Path $appsettingsDevPath) {
        $appsettingsDev = Get-Content $appsettingsDevPath -Raw | ConvertFrom-Json
        if ($appsettingsDev.Azure.SignalR.UseLocal) {
            Write-Success "Development mode: UseLocal is set to TRUE (will use local SignalR)"
            return @{
                ConnectionString = $connStr
                UseLocal = $true
            }
        }
    }
    
    return @{
        ConnectionString = $connStr
        UseLocal = $false
    }
}

# Check Azure CLI and login
function Check-AzureCLI {
    Write-Info "Checking Azure CLI..."
    
    try {
        $azVersion = az version --output json 2>$null | ConvertFrom-Json
        Write-Success "Azure CLI installed: $($azVersion.'azure-cli')"
    }
    catch {
        Write-Failure "Azure CLI is not installed or not in PATH"
        Write-Info "Install from: https://aka.ms/InstallAzureCLI"
        return $false
    }
    
    # Check if logged in
    try {
        $account = az account show 2>$null | ConvertFrom-Json
        Write-Success "Logged in as: $($account.user.name)"
        Write-Info "Subscription: $($account.name) ($($account.id))"
        return $true
    }
    catch {
        Write-Warning-Custom "Not logged in to Azure CLI"
        Write-Info "Run: az login"
        return $false
    }
}

# Get SignalR Service details
function Get-SignalRServiceDetails {
    param([string]$RG, [string]$Name)
    
    Write-Info "Fetching SignalR Service details..."
    
    try {
        $service = az signalr show --name $Name --resource-group $RG --output json 2>$null | ConvertFrom-Json
        
        if ($null -eq $service) {
            Write-Failure "SignalR Service not found: $Name in resource group $RG"
            return $null
        }
        
        Write-Success "SignalR Service found: $Name"
        Write-Info "Location: $($service.location)"
        Write-Info "Tier: $($service.sku.name) (Capacity: $($service.sku.capacity))"
        Write-Info "Provisioning State: $($service.provisioningState)"
        Write-Info "Host Name: $($service.hostName)"
        Write-Info "Public Port: $($service.publicPort)"
        Write-Info "Server Port: $($service.serverPort)"
        
        # Check tier limits
        if ($service.sku.name -eq "Free_F1") {
            Write-Warning-Custom "FREE TIER DETECTED - Limits:"
            Write-Info "  - Max Connections: 20"
            Write-Info "  - Max Messages: 20,000 per day"
            Write-Info "  - Max Units: 1"
            Write-Warning-Custom "Consider upgrading to Standard tier for production use"
        }
        elseif ($service.sku.name -match "Standard") {
            Write-Success "Standard tier - Higher limits available"
            Write-Info "  - Max Connections: $(100 * $service.sku.capacity)"
            Write-Info "  - Max Messages: ~1M per unit per day"
        }
        
        # Check features
        if ($service.features) {
            Write-Info "Enabled Features:"
            foreach ($feature in $service.features) {
                Write-Info "  - $($feature.flag): $($feature.value)"
            }
        }
        
        return $service
    }
    catch {
        Write-Failure "Failed to get SignalR Service details: $($_.Exception.Message)"
        return $null
    }
}

# Get SignalR Service keys
function Get-SignalRKeys {
    param([string]$RG, [string]$Name)
    
    Write-Info "Fetching SignalR Service keys..."
    
    try {
        $keys = az signalr key list --name $Name --resource-group $RG --output json 2>$null | ConvertFrom-Json
        
        if ($null -eq $keys) {
            Write-Failure "Failed to retrieve keys"
            return $null
        }
        
        Write-Success "Keys retrieved successfully"
        Write-Info "Primary Key: $($keys.primaryKey.Substring(0, 10))..."
        Write-Info "Secondary Key: $($keys.secondaryKey.Substring(0, 10))..."
        
        return $keys
    }
    catch {
        Write-Failure "Failed to get SignalR keys: $($_.Exception.Message)"
        return $null
    }
}

# Get SignalR usage and metrics
function Get-SignalRUsage {
    param([string]$RG, [string]$Name)
    
    Write-Info "Checking SignalR Service usage..."
    
    try {
        $usage = az signalr list-usage --name $Name --resource-group $RG --output json 2>$null | ConvertFrom-Json
        
        if ($null -eq $usage -or $usage.Count -eq 0) {
            Write-Warning-Custom "No usage data available"
            return
        }
        
        Write-Success "Current usage:"
        foreach ($metric in $usage) {
            $percentage = if ($metric.limit -gt 0) { [math]::Round(($metric.currentValue / $metric.limit) * 100, 2) } else { 0 }
            $status = if ($percentage -ge 80) { "Red" } elseif ($percentage -ge 60) { "Yellow" } else { "Green" }
            Write-ColorOutput "  - $($metric.name.value): $($metric.currentValue) / $($metric.limit) ($percentage%)" $status
        }
    }
    catch {
        Write-Warning-Custom "Failed to get usage data: $($_.Exception.Message)"
    }
}

# Test connection with .NET code
function Test-DotNetSignalRConnection {
    param([string]$ConnStr)
    
    Write-Info "Testing SignalR connection with .NET code simulation..."
    
    $parsed = Parse-ConnectionString -ConnStr $ConnStr
    
    if ([string]::IsNullOrWhiteSpace($parsed.Endpoint)) {
        Write-Failure "Invalid connection string - no endpoint found"
        return $false
    }
    
    # Test the negotiate endpoint
    $negotiateUrl = "$($parsed.Endpoint)/client/negotiate?hub=ChatHub"
    
    Write-Info "Testing negotiate endpoint: $negotiateUrl"
    
    try {
        $response = Invoke-WebRequest -Uri $negotiateUrl -Method Post -TimeoutSec 10 -ErrorAction Stop
        Write-Success "Negotiate endpoint is accessible (Status: $($response.StatusCode))"
        
        if ($response.StatusCode -eq 401) {
            Write-Warning-Custom "Authentication required - this is normal, indicates service is working"
            return $true
        }
        
        return $true
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        
        if ($statusCode -eq 401) {
            Write-Success "Service is responding (401 Unauthorized - normal for unauthenticated request)"
            return $true
        }
        elseif ($statusCode -eq 404) {
            Write-Warning-Custom "Negotiate endpoint returned 404 - check hub name 'ChatHub'"
            return $false
        }
        elseif ($statusCode -eq 502) {
            Write-Failure "502 Bad Gateway - Service is having issues!"
            Write-Info "This is the error you're experiencing"
            return $false
        }
        else {
            Write-Warning-Custom "Unexpected status: $statusCode - $($_.Exception.Message)"
            return $false
        }
    }
}

# Apply fix to appsettings
function Apply-UseLocalFix {
    Write-Info "Applying UseLocal fix to appsettings.Development.json..."
    
    $appsettingsDevPath = "Server/appsettings.Development.json"
    
    if (-not (Test-Path $appsettingsDevPath)) {
        Write-Failure "File not found: $appsettingsDevPath"
        return $false
    }
    
    try {
        $appsettingsDev = Get-Content $appsettingsDevPath -Raw | ConvertFrom-Json
        
        # Add UseLocal property
        if (-not $appsettingsDev.Azure) {
            $appsettingsDev | Add-Member -MemberType NoteProperty -Name "Azure" -Value @{}
        }
        if (-not $appsettingsDev.Azure.SignalR) {
            $appsettingsDev.Azure | Add-Member -MemberType NoteProperty -Name "SignalR" -Value @{}
        }
        
        $appsettingsDev.Azure.SignalR | Add-Member -MemberType NoteProperty -Name "UseLocal" -Value $true -Force
        
        # Save back
        $appsettingsDev | ConvertTo-Json -Depth 10 | Set-Content $appsettingsDevPath
        
        Write-Success "Updated appsettings.Development.json with UseLocal = true"
        Write-Info "Restart your application to use local SignalR"
        
        return $true
    }
    catch {
        Write-Failure "Failed to update appsettings: $($_.Exception.Message)"
        return $false
    }
}

# Generate recommendations
function Show-Recommendations {
    param($Issues)
    
    Write-Section "RECOMMENDATIONS"
    
    if ($Issues.Count -eq 0) {
        Write-Success "No critical issues found!"
        return
    }
    
    Write-ColorOutput "Found $($Issues.Count) issue(s):" "Yellow"
    Write-Host ""
    
    $priority = 1
    foreach ($issue in $Issues) {
        Write-ColorOutput "[$priority] $($issue.Title)" "Yellow"
        Write-Info "   Problem: $($issue.Problem)"
        Write-Info "   Solution: $($issue.Solution)"
        if ($issue.Command) {
            Write-ColorOutput "   Command: $($issue.Command)" "Cyan"
        }
        Write-Host ""
        $priority++
    }
}

# Main execution
Write-Section "AZURE SIGNALR SERVICE VERIFICATION"

$issues = @()
$config = $null

# Step 1: Check appsettings
Write-Section "1. CHECKING CONFIGURATION FILES"
$config = Check-AppSettings

if ($null -eq $config) {
    $issues += @{
        Title = "Configuration Missing"
        Problem = "SignalR connection string not found in appsettings.json"
        Solution = "Add Azure:SignalR:ConnectionString to Server/appsettings.json"
        Command = "Get connection string from Azure Portal ? SignalR Service ? Keys"
    }
}
elseif ($config.UseLocal) {
    Write-Success "Configuration is set to use LOCAL SignalR - Azure service will be bypassed"
    Write-Info "To test Azure SignalR, set UseLocal to false in appsettings.Development.json"
    exit 0
}

if ($null -ne $config) {
    $ConnectionString = $config.ConnectionString
}

# Step 2: Parse connection string
Write-Section "2. PARSING CONNECTION STRING"
if (-not [string]::IsNullOrWhiteSpace($ConnectionString)) {
    $parsed = Parse-ConnectionString -ConnStr $ConnectionString
    
    Write-Info "Endpoint: $($parsed.Endpoint)"
    Write-Info "Access Key: $($parsed.AccessKey)"
    Write-Info "Version: $($parsed.Version)"
    
    if ([string]::IsNullOrWhiteSpace($parsed.AccessKey)) {
        Write-Info "Auth Type: $($parsed.AuthType) (Managed Identity)"
    }
    else {
        Write-Info "Auth Type: Access Key"
    }
}
else {
    Write-Warning-Custom "No connection string to parse"
}

# Step 3: Test connectivity
Write-Section "3. TESTING NETWORK CONNECTIVITY"
if (-not [string]::IsNullOrWhiteSpace($parsed.Endpoint)) {
    $connectivityOk = Test-SignalRConnectivity -Endpoint $parsed.Endpoint
    
    if (-not $connectivityOk) {
        $issues += @{
            Title = "Network Connectivity Issue"
            Problem = "Cannot reach SignalR endpoint: $($parsed.Endpoint)"
            Solution = "Check firewall, VPN, or network settings. Try from a different network."
            Command = "Test-NetConnection -ComputerName '$($parsed.Endpoint -replace 'https://', '')' -Port 443"
        }
    }
}

# Step 4: Test SignalR-specific endpoints
Write-Section "4. TESTING SIGNALR ENDPOINTS"
if (-not [string]::IsNullOrWhiteSpace($ConnectionString)) {
    $signalrOk = Test-DotNetSignalRConnection -ConnStr $ConnectionString
    
    if (-not $signalrOk) {
        $issues += @{
            Title = "SignalR Service Issue (502 Error)"
            Problem = "SignalR service is returning 502 Bad Gateway"
            Solution = "Service may be down, restarting, or over capacity. Check Azure Portal."
            Command = ".\verify-signalr-setup.ps1 -ResourceGroup '<rg-name>' -SignalRName '<service-name>'"
        }
    }
}

# Step 5: Check Azure resources (if parameters provided)
if (-not [string]::IsNullOrWhiteSpace($ResourceGroup) -and -not [string]::IsNullOrWhiteSpace($SignalRName)) {
    Write-Section "5. CHECKING AZURE RESOURCES"
    
    $azCliOk = Check-AzureCLI
    
    if ($azCliOk) {
        $service = Get-SignalRServiceDetails -RG $ResourceGroup -Name $SignalRName
        
        if ($null -ne $service) {
            # Check provisioning state
            if ($service.provisioningState -ne "Succeeded") {
                $issues += @{
                    Title = "Service Not Ready"
                    Problem = "SignalR service provisioning state: $($service.provisioningState)"
                    Solution = "Wait for service to finish provisioning"
                    Command = "az signalr show --name $SignalRName --resource-group $ResourceGroup"
                }
            }
            
            # Get keys
            $keys = Get-SignalRKeys -RG $ResourceGroup -Name $SignalRName
            
            # Get usage
            Get-SignalRUsage -RG $ResourceGroup -Name $SignalRName
            
            # Check if free tier
            if ($service.sku.name -eq "Free_F1") {
                $issues += @{
                    Title = "Free Tier Limitations"
                    Problem = "Using Free tier (20 connections, 20K messages/day)"
                    Solution = "Upgrade to Standard tier for production workloads"
                    Command = "az signalr update --name $SignalRName --resource-group $ResourceGroup --sku Standard_S1"
                }
            }
        }
    }
}
else {
    Write-Section "5. AZURE RESOURCE CHECK (SKIPPED)"
    Write-Info "To check Azure resources, provide -ResourceGroup and -SignalRName parameters"
    Write-Info "Example: .\verify-signalr-setup.ps1 -ResourceGroup 'myRG' -SignalRName 'mySignalR'"
}

# Step 6: Show recommendations
Show-Recommendations -Issues $issues

# Step 7: Offer quick fixes
Write-Section "QUICK FIXES"

Write-Info "Available quick fixes:"
Write-Host ""
Write-ColorOutput "1. Use Local SignalR (Recommended for Development)" "Cyan"
Write-Info "   Run: .\verify-signalr-setup.ps1 -FixAppsettings"
Write-Info "   This will set UseLocal=true in appsettings.Development.json"
Write-Host ""

Write-ColorOutput "2. Regenerate SignalR Keys" "Cyan"
Write-Info "   Run: az signalr key renew --name <name> --resource-group <rg> --key-type primary"
Write-Host ""

Write-ColorOutput "3. Restart SignalR Service" "Cyan"
Write-Info "   Run: az signalr restart --name <name> --resource-group <rg>"
Write-Host ""

Write-ColorOutput "4. Check Azure Service Health" "Cyan"
Write-Info "   Visit: https://portal.azure.com/#view/Microsoft_Azure_Health/AzureHealthBrowseBlade"
Write-Host ""

# Apply fix if requested
if ($FixAppsettings) {
    Write-Section "APPLYING FIX"
    $fixResult = Apply-UseLocalFix
    
    if ($fixResult) {
        Write-Success "Fix applied successfully!"
        Write-Info "Restart your application to use local SignalR"
    }
    else {
        Write-Failure "Fix failed. Please check the errors above."
    }
}
elseif ($UseLocal) {
    Apply-UseLocalFix | Out-Null
}

# Summary
Write-Section "SUMMARY"

if ($issues.Count -eq 0) {
    Write-Success "All checks passed! SignalR service appears to be healthy."
}
else {
    Write-ColorOutput "Found $($Issues.Count) issue(s) that need attention." "Yellow"
    Write-Info "Review the recommendations above to resolve these issues."
}

Write-Host ""
Write-Info "For detailed troubleshooting, see: SIGNALR_502_FIX.md"
Write-Host ""
