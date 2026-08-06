# CORS Error Fix - Invalid Access-Control-Allow-Origin Header

## ?? Error Details

You're experiencing:
```
Access to XMLHttpRequest at 'https://livestream-signalr-service-cgbaanhtf0athweb.z03.azurefd.net/livestream...'
from origin 'https://localhost:7119' has been blocked by CORS policy:
The 'Access-Control-Allow-Origin' header contains the invalid value '**'.
```

**Root Cause:** Azure Front Door or Azure Storage is returning an invalid CORS header value of `**` instead of `*` or a specific origin.

---

## ? Immediate Fix (5 Minutes)

### Step 1: Run Enhanced CORS Configuration

```powershell
# Basic fix - configure Storage CORS
.\configure-cors.ps1

# Advanced fix - also configure Front Door
.\configure-cors.ps1 -FixFrontDoor
```

### Step 2: Purge Azure Front Door Cache

**Option A: Using Azure Portal**
1. Go to Azure Portal ? Your Front Door
2. Navigate to "Overview" ? "Purge cache"
3. Select "All" or enter path: `/*`
4. Click "Purge"

**Option B: Using Azure CLI**
```powershell
# Replace with your values
$resourceGroup = "LiveStreamApp-RG"
$profileName = "your-frontdoor-profile"
$endpointName = "your-endpoint"

az afd endpoint purge `
  --resource-group $resourceGroup `
  --profile-name $profileName `
  --endpoint-name $endpointName `
  --content-paths "/*"
```

### Step 3: Clear Browser Cache

**CRITICAL:** Browser may have cached the bad CORS response

```powershell
# Hard refresh
Windows/Linux: Ctrl + Shift + R
Mac: Cmd + Shift + R

# Or use incognito/private window
Ctrl+Shift+N (Chrome)
Ctrl+Shift+P (Firefox)
```

### Step 4: Restart Application

```powershell
# Stop server (Ctrl+C)
cd Server
dotnet run
```

### Step 5: Test

1. Open broadcaster in **incognito window**
2. Press F12 ? Console
3. Start broadcast
4. Look for CORS errors - should be gone

---

## ?? Understanding the Error

### Invalid CORS Header

**Problem:**
```http
Access-Control-Allow-Origin: **
```

**This is INVALID because:**
- `**` is not a valid CORS value
- Valid values are:
  - `*` (wildcard - allow all origins)
  - `https://specific-origin.com` (specific origin)

**Should be:**
```http
Access-Control-Allow-Origin: *
```

---

## ? Expected Behavior After Fix

### Browser Console:

**Before Fix:**
```
? Access to XMLHttpRequest blocked by CORS policy
? Failed to load resource: net::ERR_FAILED
```

**After Fix:**
```
? Manifest parsed successfully
? Fragment loaded: 0
? Fragment loaded: 1
```

---

**Date:** 2024-01-15  
**Version:** 2.1
