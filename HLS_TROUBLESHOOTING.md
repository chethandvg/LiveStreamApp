# HLS Streaming Troubleshooting Guide

## Common HLS Errors and Solutions

### ?? Error: "HLS error" (Object)
**Location:** `stream.js:235`

**Cause:** Generic HLS.js error, often related to network or manifest issues.

**Solutions:**
1. Check browser console for more specific error details
2. Ensure the stream has started (broadcaster is actively streaming)
3. Wait 5-10 seconds for FFmpeg to generate initial manifest
4. Run diagnostics: `.\diagnose-stream.ps1 -StreamId "your_stream_id"`

---

### ?? Error: "mediaError bufferStalledError"
**Location:** `stream.js:278`

**Cause:** The HLS player cannot download segments fast enough, causing buffering.

**Root Causes:**
- FFmpeg is not generating segments quickly enough
- Network latency between Azure Storage and viewer
- CDN caching issues
- Insufficient upload bandwidth from broadcaster

**Solutions:**

#### 1. Immediate Actions
```powershell
# Run comprehensive diagnostics
.\diagnose-stream.ps1 -StreamId "your_stream_id"

# Check if CORS is configured
.\configure-cors.ps1
```

#### 2. Verify FFmpeg is Running
- Check server logs for FFmpeg process
- Ensure FFmpeg is in system PATH: `ffmpeg -version`
- Restart the stream if FFmpeg crashed

#### 3. Check Azure Storage
```powershell
# Verify files are being uploaded
# Check Azure Portal -> Storage Account -> Containers -> livestreams -> [your_stream_id]
```

**Expected files:**
- `index.m3u8` (manifest)
- `segment_000.ts`, `segment_001.ts`, etc. (video segments)

#### 4. Optimize Streaming Settings

**Server/appsettings.json:**
```json
{
  "Streaming": {
    "SegmentDurationSeconds": 2,  // Reduced from 4 for lower latency
    "ChunkSizeKB": 512
  }
}
```

#### 5. Check Browser Compatibility
```javascript
// Run in browser console
console.log('HLS.js supported:', Hls.isSupported());
console.log('Native HLS:', document.createElement('video').canPlayType('application/vnd.apple.mpegurl'));
```

---

### ?? Error: "Fatal network error" (404)
**Cause:** Stream manifest file not found at CDN URL

**Solutions:**

#### 1. Verify Stream is Active
```powershell
# Check if broadcaster started streaming
Invoke-RestMethod -Uri "https://localhost:7119/api/streamingest/status/your_stream_id"
```

#### 2. Check CDN Configuration
**Client/wwwroot/appsettings.json:**
```json
{
  "Azure": {
    "CDN": {
      "BaseUrl": "https://your-cdn.azurefd.net/livestreams"
    }
  }
}
```

**Common mistakes:**
- ? `https://your-cdn.azurefd.net` (missing `/livestreams`)
- ? `https://your-cdn.azurefd.net/livestreams/` (trailing slash)
- ? `https://your-cdn.azurefd.net/livestreams` (correct)

#### 3. Check Azure Front Door Origin
Ensure Azure Front Door is configured to point to:
```
Origin: your-storage-account.blob.core.windows.net
Origin Path: /livestreams
```

#### 4. Purge CDN Cache
```powershell
# Azure CLI
az afd endpoint purge `
  --resource-group "your-rg" `
  --profile-name "your-profile" `
  --endpoint-name "your-endpoint" `
  --content-paths "/*"
```

---

### ?? Error: "CORS" or "Access-Control-Allow-Origin"
**Cause:** CORS headers not configured on Azure Storage

**Solution:**
```powershell
# Automated CORS configuration
.\configure-cors.ps1

# Verify CORS
az storage cors list `
  --services b `
  --account-name "your-storage" `
  --account-key "your-key"
```

**Manual Configuration:**
1. Azure Portal ? Storage Account ? Resource sharing (CORS)
2. Blob service ? Add rule:
   - **Allowed origins:** `*`
   - **Allowed methods:** `GET, HEAD, OPTIONS`
   - **Allowed headers:** `*`
   - **Exposed headers:** `*`
   - **Max age:** `3600`

---

## Diagnostic Commands

### Quick Health Check
```powershell
# Check all components
.\diagnose-stream.ps1

# Check specific stream
.\diagnose-stream.ps1 -StreamId "stream_12345"
```

### Manual Checks

#### 1. Test Manifest URL Directly
```powershell
$streamId = "your_stream_id"
$cdnUrl = "https://your-cdn.azurefd.net/livestreams"
$manifestUrl = "$cdnUrl/$streamId/index.m3u8"

# Test accessibility
Invoke-WebRequest -Uri $manifestUrl -Method HEAD
```

#### 2. Check FFmpeg Process
```powershell
# Windows
Get-Process | Where-Object { $_.ProcessName -eq "ffmpeg" }

# Linux/Mac
ps aux | grep ffmpeg
```

#### 3. View Server Logs
```powershell
# Run server with verbose logging
cd Server
$env:ASPNETCORE_ENVIRONMENT="Development"
dotnet run
```

#### 4. Test CORS Headers
```powershell
Invoke-WebRequest `
  -Uri "https://your-storage.blob.core.windows.net/livestreams/" `
  -Method OPTIONS `
  -Headers @{
    "Origin" = "https://localhost:7119"
    "Access-Control-Request-Method" = "GET"
  }
```

---

## Performance Optimization

### For Low Latency (< 5 seconds)
?? Not recommended with current HLS implementation (typical latency: 15-30s)

### For Reliable Streaming (Recommended)
**Server/Shared/StreamProcessor.cs** already optimized with:
- `-preset ultrafast`: Fast encoding
- `-tune zerolatency`: Minimize latency
- `-hls_time 2`: 2-second segments
- `-hls_list_size 10`: Keep 10 segments

### For High Quality
Adjust in `StreamProcessor.cs`:
```csharp
arguments.Append("-preset medium ");  // Better quality, slower encoding
arguments.Append("-b:v 3500k ");      // Higher video bitrate
arguments.Append("-b:a 192k ");       // Higher audio bitrate
```

---

## Browser-Specific Issues

### Safari (iOS/macOS)
- Uses **native HLS** (not HLS.js)
- Check console for errors: `video.error.code`
- Error code 4 = Media not supported or not found

### Chrome/Edge/Firefox
- Uses **HLS.js**
- Check: `Hls.isSupported()` in console
- Enable debug mode: `debug: true` in HLS config

### Firefox
- May need HTTPS for certain features
- Check `about:config` ? `media.mediasource.enabled`

---

## Step-by-Step Resolution Process

### When a Stream Won't Play:

1. **Run Diagnostics**
   ```powershell
   .\diagnose-stream.ps1 -StreamId "your_stream_id"
   ```

2. **Check Browser Console** (F12)
   - Look for red errors
   - Note the error codes and messages

3. **Verify Broadcaster Started**
   - Broadcaster must click "Start Broadcast"
   - Check for "Stream started" message
   - Wait 5-10 seconds for initialization

4. **Test Manifest URL**
   ```powershell
   # Should return 200 OK
   Invoke-WebRequest -Uri "https://your-cdn.azurefd.net/livestreams/your_stream_id/index.m3u8"
   ```

5. **Check Azure Storage**
   - Portal ? Storage ? livestreams container
   - Should see folder with stream ID
   - Should contain `.m3u8` and `.ts` files

6. **Configure CORS** (if needed)
   ```powershell
   .\configure-cors.ps1
   ```

7. **Restart Components**
   ```powershell
   # Stop server (Ctrl+C)
   # Restart
   cd Server
   dotnet run
   ```

8. **Clear Browser Cache**
   - Hard refresh: `Ctrl+Shift+R` (Windows) or `Cmd+Shift+R` (Mac)
   - Or open in incognito/private window

---

## Advanced Debugging

### Enable HLS.js Debug Mode

**Client/wwwroot/js/stream.js:**
```javascript
hlsInstance = new Hls({
    debug: true,  // Enable detailed logging
    // ...other options
});
```

### Monitor Network Requests
1. Open browser DevTools (F12)
2. Go to Network tab
3. Filter by `.m3u8` and `.ts`
4. Check status codes and response times

### Check Server Logs
Look for these log entries:
- ? `Stream started: {streamId}`
- ? `FFmpeg process started`
- ? `MANIFEST UPLOADED SUCCESSFULLY`
- ? `Uploaded segment_XXX.ts`
- ? `FFmpeg not found`
- ? `Error uploading file`

---

## Contact & Support

If issues persist after following this guide:

1. **Collect Diagnostic Info**
   ```powershell
   .\diagnose-stream.ps1 -StreamId "your_stream_id" > diagnostics.txt
   ```

2. **Check Issues:** https://github.com/chethandvg/LiveStreamApp/issues

3. **Review Logs:**
   - Browser console errors
   - Server console output
   - Azure Storage logs

4. **Documentation:** See [DOCS.md](DOCS.md) for comprehensive guide

---

## Quick Reference

| Symptom | Likely Cause | Command |
|---------|-------------|---------|
| 404 on manifest | Stream not started or CDN misconfigured | `.\diagnose-stream.ps1 -StreamId "id"` |
| CORS error | Azure Storage CORS not configured | `.\configure-cors.ps1` |
| Buffer stalled | FFmpeg not generating segments fast enough | Check server logs, restart stream |
| "HLS not supported" | Old browser | Update browser or try Safari |
| Infinite loading | Firewall or network issue | Check network tab in DevTools |

---

**Last Updated:** 2024-01-15  
**Version:** 2.0
