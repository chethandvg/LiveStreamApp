# ?? URGENT: CORS Error Fix - Invalid Header Value

## Your Current Error

```
? Access to XMLHttpRequest blocked by CORS policy:
   The 'Access-Control-Allow-Origin' header contains the invalid value '**'.
```

This is **BLOCKING ALL STREAMING** - must be fixed immediately.

---

## ? Fix It Now (3 Steps - 5 Minutes)

### Step 1: Run CORS Fix Script

```powershell
# This will fix both Storage and Front Door
.\configure-cors.ps1 -FixFrontDoor
```

**What it does:**
- Clears invalid CORS rules
- Sets correct CORS: `*` (not `**`)
- Configures Front Door to pass through headers
- Tests configuration

---

### Step 2: Purge Azure Front Door Cache

**Critical:** Front Door cached the bad headers!

#### Option A: Azure Portal (Easiest)
1. Open: https://portal.azure.com
2. Go to your Front Door resource
3. Click "Overview" ? "Purge cache"
4. Content paths: `/*`
5. Click "Purge"
6. **Wait 2 minutes**

#### Option B: Azure CLI
```powershell
# Find your Front Door
az afd profile list --resource-group "LiveStreamApp-RG"

# Purge (replace with your names)
az afd endpoint purge `
  --resource-group "LiveStreamApp-RG" `
  --profile-name "livestream-signalr-service" `
  --endpoint-name "cgbaanhtf0athweb" `
  --content-paths "/*"
```

---

### Step 3: Clear Browser Cache & Test

```powershell
# 1. Close ALL browser tabs with your app

# 2. Clear browser cache
#    Windows/Linux: Ctrl + Shift + Delete ? Check "Cached images and files" ? Clear

# 3. Or use incognito window
#    Ctrl + Shift + N (Chrome)

# 4. Restart server
cd Server
dotnet run

# 5. Test in incognito window
#    Open: https://localhost:7119/broadcast
#    Press F12 to see console
#    Start broadcast
```

---

## ?? Verify It's Fixed

### Check Browser Console (F12)

**? Before Fix:**
```
Access to XMLHttpRequest blocked by CORS policy:
The 'Access-Control-Allow-Origin' header contains the invalid value '**'.
Failed to load resource: net::ERR_FAILED
```

**? After Fix:**
```
Initializing player for: https://livestream-signalr-service-cgbaanhtf0athweb...
Using HLS.js for playback
Manifest parsed successfully
Fragment loaded: 0
```

---

### Test CORS Headers

**Run in PowerShell:**
```powershell
# Replace with your storage account
$storage = "livestreamtrial"
$url = "https://$storage.blob.core.windows.net/livestreams/"

# Test CORS
curl -I -H "Origin: https://localhost:7119" `
     -H "Access-Control-Request-Method: GET" `
     $url
```

**Look for:**
```http
HTTP/1.1 200 OK
Access-Control-Allow-Origin: *              ? Should be * (NOT **)
Access-Control-Allow-Methods: GET, HEAD, OPTIONS
Access-Control-Allow-Headers: *
```

---

## ?? Still Seeing Error?

### 1. Wait Longer for Cache Purge

Front Door cache can take up to 5 minutes:

```powershell
# Check every minute
for ($i=1; $i -le 5; $i++) {
    Write-Host "Attempt $i..."
    curl -I "https://livestream-signalr-service-cgbaanhtf0athweb.z03.azurefd.net/livestreams/"
    Start-Sleep -Seconds 60
}
```

---

### 2. Manually Verify CORS in Azure Portal

1. **Azure Portal ? Storage Account ? Settings ? Resource sharing (CORS)**
2. **Check Blob service tab:**
   - Allowed origins: Should be `*` (not `**`)
   - Allowed methods: `GET`, `HEAD`, `OPTIONS`
   - Allowed headers: `*`
   - Exposed headers: `*`

3. **If you see `**`:**
   - Delete the rule
   - Add new rule with `*`
   - Save

---

### 3. Check Front Door Origin Configuration

1. **Azure Portal ? Front Door ? Origins**
2. **Verify:**
   - Origin hostname: `livestreamtrial.blob.core.windows.net`
   - Origin host header: Same as hostname
   - HTTPS: Enabled

3. **Go to Routes:**
   - Check "Patterns to match" includes `/*`
   - HTTPS redirect: Enabled

---

### 4. Nuclear Option: Reconfigure Everything

```powershell
# 1. Clear CORS
$storage = "livestreamtrial"
$rg = "LiveStreamApp-RG"
$key = (az storage account keys list --account-name $storage --resource-group $rg --query "[0].value" -o tsv)

az storage cors clear --services b --account-name $storage --account-key $key

# 2. Add correct CORS
az storage cors add `
  --services b `
  --methods GET HEAD OPTIONS `
  --origins "*" `
  --allowed-headers "*" `
  --exposed-headers "*" `
  --max-age 3600 `
  --account-name $storage `
  --account-key $key

# 3. Verify
az storage cors list --services b --account-name $storage --account-key $key

# 4. Purge Front Door
az afd endpoint purge `
  --resource-group $rg `
  --profile-name "livestream-signalr-service" `
  --endpoint-name "cgbaanhtf0athweb" `
  --content-paths "/*"

# 5. Wait 2 minutes

# 6. Test
curl -I -H "Origin: https://localhost:7119" `
     "https://livestreamtrial.blob.core.windows.net/livestreams/"
```

---

## ?? Timeline

**Typical fix time:**
- Step 1 (CORS script): 2 minutes
- Step 2 (Purge cache): 2-5 minutes (waiting)
- Step 3 (Test): 1 minute
- **Total: 5-8 minutes**

---

## ?? Checklist

Before you proceed:
- [ ] ? Ran `.\configure-cors.ps1 -FixFrontDoor`
- [ ] ? Saw "CORS configuration complete!" message
- [ ] ? Purged Front Door cache
- [ ] ? Waited at least 2 minutes
- [ ] ? Cleared browser cache (or using incognito)
- [ ] ? Closed all browser tabs
- [ ] ? Restarted server
- [ ] ? Tested in incognito window
- [ ] ? Checked F12 console for CORS errors

If all checked and still failing:
- [ ] ? Verified CORS in Portal shows `*` not `**`
- [ ] ? Waited 5 minutes total after purge
- [ ] ? Tested CORS headers with curl (shows `*`)

---

## ?? Success Indicators

### You'll know it's fixed when:

1. **Browser Console (F12):**
   ```
   ? Initializing player for: https://...
   ? Using HLS.js for playback
   ? Manifest parsed successfully
   ```

2. **curl Test:**
   ```http
   Access-Control-Allow-Origin: *
   ```

3. **Video Player:**
   - No CORS errors
   - Manifest loads
   - Fragments load
   - Video plays

---

## ?? Emergency Help

If still broken after all steps:

### Collect Info:

```powershell
# 1. Storage CORS config
az storage cors list --services b --account-name livestreamtrial --account-key "your-key" > cors-config.txt

# 2. Test CORS
curl -I -H "Origin: https://localhost:7119" "https://livestreamtrial.blob.core.windows.net/livestreams/" > cors-test.txt

# 3. Front Door config
az afd profile show --name "livestream-signalr-service" --resource-group "LiveStreamApp-RG" > frontdoor.txt

# 4. Browser console
# F12 ? Console ? Copy all errors

# 5. Network tab
# F12 ? Network ? Find failed request ? Copy headers
```

### Check These Files:

1. `cors-config.txt` - Should show `"allowedOrigins": ["*"]`
2. `cors-test.txt` - Should show `Access-Control-Allow-Origin: *`
3. Browser console - Should NOT show CORS errors
4. Network tab - Response headers should show `Access-Control-Allow-Origin: *`

---

## ?? Related Docs

- **`CORS_ERROR_FIX.md`** - Detailed CORS troubleshooting
- **`configure-cors.ps1`** - Automated fix script
- **`diagnose-stream.ps1`** - Full diagnostics

---

## ? Quick Command Summary

```powershell
# Fix CORS
.\configure-cors.ps1 -FixFrontDoor

# Purge cache
az afd endpoint purge --resource-group "LiveStreamApp-RG" --profile-name "livestream-signalr-service" --endpoint-name "cgbaanhtf0athweb" --content-paths "/*"

# Test CORS
curl -I -H "Origin: https://localhost:7119" "https://livestreamtrial.blob.core.windows.net/livestreams/"

# Restart
cd Server && dotnet run
```

---

**This is a critical blocking issue - streaming will NOT work until CORS is fixed!**

**Follow the 3 steps above to resolve it in 5 minutes.** ??

---

**Date:** 2024-01-15  
**Priority:** ?? CRITICAL  
**Estimated Fix Time:** 5-8 minutes
