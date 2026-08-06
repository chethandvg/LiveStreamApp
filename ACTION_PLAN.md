# ?? Action Plan - Fix Buffer Stall Errors

## ? Quick Start (Do This Now!)

### 1. Stop Current Server
```powershell
# Press Ctrl+C in your server terminal
```

### 2. ?? CRITICAL: Clear Browser Cache
**THIS IS ESSENTIAL!** Old JavaScript is likely cached.

```powershell
# Method 1: Hard Refresh (Recommended)
Windows/Linux: Ctrl + Shift + R
Mac: Cmd + Shift + R

# Method 2: Incognito/Private Window
Ctrl+Shift+N (Chrome) or Ctrl+Shift+P (Firefox)

# Method 3: Clear All Browser Data
Chrome: Settings ? Privacy ? Clear browsing data ? Cached images and files
```

### 3. Restart Server
```powershell
cd Server
dotnet run
```

### 4. Test Streaming

**Broadcaster:**
1. Open: `https://localhost:7119/broadcast`
2. Click "Start Broadcast"
3. Allow camera/microphone
4. Wait 15 seconds (important!)

**Viewer:**
1. Copy the stream URL from broadcaster
2. Open in NEW incognito window (to ensure fresh cache)
3. Press F12 to open console
4. Watch for log messages

---

## ?? What to Look For

### ? Good Signs (Success):

**Browser Console:**
```javascript
? Manifest parsed successfully
Fragment loaded: 0
Fragment loaded: 1
Level loaded, segments: 6
Buffer ahead: 12.5s                    ? Should grow over time
?? Buffer nudge on stall (1/15)        ? Occasional, auto-recovering
Buffer appending - reducing error counts
Fragment loaded: 2
```

**Server Logs:**
```
[INFO] FFmpeg process started (PID: 1234)
[INFO] ? MANIFEST UPLOADED SUCCESSFULLY!
[INFO] ? Uploaded segment_000.ts (456789 bytes)
[INFO] Periodic check: Uploading updated manifest
[INFO] ? Uploaded segment_001.ts (458123 bytes)  ? Every ~3 seconds
```

---

### ? Problem Signs:

**Browser Console:**
```javascript
? HLS error: Object                   ? Still getting fatal errors
Buffer ahead: 0.5s                     ? Buffer not growing
?? bufferStalledError (15/20)          ? Too many stalls
```

**Server Logs:**
```
[ERROR] FFmpeg not found!
[WARN] FFmpeg issue: error...
[INFO] ? Uploaded segment_000.ts
(long pause > 5 seconds)
[INFO] ? Uploaded segment_001.ts         ? Segments too slow
```

---

## ?? Verification Checklist

### Before You Start:

- [ ] Server is stopped (Ctrl+C)
- [ ] Browser cache cleared (Ctrl+Shift+R or incognito)
- [ ] FFmpeg installed (`ffmpeg -version` works)
- [ ] CORS configured (`.\configure-cors.ps1`)
- [ ] Diagnostic tools ready (`.\diagnose-stream.ps1`)

### After Starting:

- [ ] Server starts without errors
- [ ] Can access broadcaster page
- [ ] Camera/microphone permission granted
- [ ] See "Stream started" message
- [ ] Server logs show FFmpeg started
- [ ] Server logs show segments uploading every 3 seconds
- [ ] Viewer can connect
- [ ] Browser console shows fragments loading
- [ ] Buffer grows to 5+ seconds
- [ ] Playback is smooth

---

## ?? Troubleshooting

### Problem: Browser still shows old errors

**Cause:** Browser cache not cleared

**Solution:**
1. Close ALL browser tabs with your app
2. Clear cache: `Ctrl+Shift+R` or Settings ? Clear browsing data
3. Or use incognito: `Ctrl+Shift+N`
4. Reopen broadcaster and viewer

---

### Problem: Segments not uploading

**Check Server Logs:**
```
[ERROR] Azure Storage connection string is missing!
```

**Solution:**
```powershell
# Check configuration
cat Server/appsettings.json

# Verify connection string exists and is valid
# Run diagnostics
.\diagnose-stream.ps1
```

---

### Problem: FFmpeg not found

**Check:**
```powershell
ffmpeg -version
```

**If error:**
```powershell
# Windows (with Chocolatey)
choco install ffmpeg

# Windows (manual)
# Download from https://ffmpeg.org/download.html
# Add to PATH

# macOS
brew install ffmpeg

# Linux
sudo apt install ffmpeg
```

---

### Problem: Segments uploading slowly (> 5 seconds apart)

**Possible Causes:**
1. CPU overload
2. Slow network to Azure
3. FFmpeg struggling

**Check CPU:**
```powershell
# Windows
Get-Process | Where-Object { $_.ProcessName -eq "ffmpeg" } | Select-Object CPU

# Should be < 80%
```

**Check Network:**
```powershell
# Test upload speed to Azure
.\diagnose-stream.ps1 -StreamId "your_stream_id"
```

**Solutions:**
- Close other applications
- Reduce video quality in broadcaster
- Check internet connection
- Verify Azure Storage is accessible

---

### Problem: Buffer not growing above 3 seconds

**Causes:**
1. Viewer's network too slow
2. CDN too slow
3. Segments not being generated fast enough

**Test Download Speed:**
```javascript
// Run in browser console
const start = Date.now();
fetch('https://your-cdn.azurefd.net/livestreams/your_stream_id/segment_000.ts')
    .then(r => r.blob())
    .then(b => {
        const secs = (Date.now() - start) / 1000;
        console.log(`Downloaded ${(b.size/1024).toFixed(0)}KB in ${secs.toFixed(2)}s`);
    });
```

**Expected:** < 2 seconds  
**Problem:** > 3 seconds

**Solutions:**
- Check viewer's internet speed (need 3+ Mbps)
- Verify CDN configuration
- Check Azure Front Door status
- Try different network

---

## ?? Monitor Buffer Level

### Real-Time Buffer Monitor (Browser Console):

```javascript
// Paste this in browser console (F12) while playing
let stallCount = 0;
let nudgeCount = 0;

setInterval(() => {
    const video = document.getElementById('hlsPlayer');
    if (video && video.buffered.length > 0) {
        const buffered = video.buffered.end(0) - video.currentTime;
        
        let status = '?';
        if (buffered < 1) {
            status = '? CRITICAL';
            stallCount++;
        } else if (buffered < 3) {
            status = '?? WARNING';
        } else if (buffered < 5) {
            status = '? LOW';
        }
        
        console.log(`${status} Buffer: ${buffered.toFixed(1)}s | Stalls: ${stallCount} | Nudges: ${nudgeCount}`);
    }
}, 1000);
```

**Interpretation:**
- **? Buffer > 5s:** Healthy
- **? Buffer 3-5s:** Acceptable
- **?? Buffer 1-3s:** Warning - may stall soon
- **? Buffer < 1s:** Critical - likely to stall

---

## ?? Expected Timeline

### Stream Startup:
```
0:00 - Start broadcast
0:01 - FFmpeg starts
0:03 - First segment uploaded
0:06 - Second segment uploaded
0:09 - Third segment uploaded
0:10 - Manifest has 3-4 segments
0:10 - Viewer can start playing
0:15 - Buffer at 5-10 seconds
0:30 - Buffer at 10-20 seconds
0:45 - Buffer stable at 15-30 seconds
```

### If Slower:
```
0:00 - Start broadcast
0:05 - FFmpeg still starting        ? Check FFmpeg logs
0:10 - No segments yet              ? Problem - check CPU
0:15 - First segment appears        ? Very slow
```

**If this happens:** FFmpeg is struggling or not configured correctly.

---

## ?? Getting Help

### Collect Diagnostics:

```powershell
# 1. General health check
.\diagnose-stream.ps1 > health-check.txt

# 2. Stream-specific check (if you have a stream ID)
.\diagnose-stream.ps1 -StreamId "your_stream_id" > stream-diagnostics.txt

# 3. FFmpeg info
ffmpeg -version > ffmpeg-info.txt

# 4. System info
Get-ComputerInfo | Select-Object CsName, OsName, OsArchitecture, CsProcessors > system-info.txt
```

### Information to Provide:

1. ? Output of diagnostic scripts
2. ? Server console logs (copy/paste)
3. ? Browser console logs (F12, copy/paste)
4. ? Screenshot of errors
5. ? FFmpeg version
6. ? Operating system
7. ? Network speed (upload/download)

### Review Documentation:

- **`BUFFER_STALL_RESOLUTION.md`** - Comprehensive buffer stall guide
- **`HLS_TROUBLESHOOTING.md`** - General HLS errors  
- **`V2.1_BUFFER_STALL_FIX_SUMMARY.md`** - Complete change summary
- **`QUICK_FIX_GUIDE.md`** - Quick reference

---

## ? Success Checklist

After 5 minutes of streaming, you should see:

- [ ] ? No fatal HLS errors in browser console
- [ ] ? Buffer level stays above 5 seconds
- [ ] ? Nudge errors < 5 per minute
- [ ] ? Buffer stalled errors < 2 per minute
- [ ] ? Segments uploading every 3 seconds
- [ ] ? Manifest updating every 1 second
- [ ] ? Smooth, continuous playback
- [ ] ? No FFmpeg errors in server logs

**If all checked:** ?? Success! Your streaming is working properly.

**If some unchecked:** See troubleshooting section above or run diagnostics.

---

## ?? Quick Commands Reference

```powershell
# Stop server
Ctrl+C

# Clear browser cache
Ctrl+Shift+R (hard refresh)
Ctrl+Shift+N (incognito)

# Start server
cd Server && dotnet run

# Run diagnostics
.\diagnose-stream.ps1

# Configure CORS
.\configure-cors.ps1

# Check FFmpeg
ffmpeg -version

# Monitor buffer (browser console)
setInterval(() => {
    const v = document.getElementById('hlsPlayer');
    if (v && v.buffered.length) {
        console.log(`Buffer: ${(v.buffered.end(0) - v.currentTime).toFixed(1)}s`);
    }
}, 1000);
```

---

## ?? Final Pre-Flight Checklist

Before testing:

1. [ ] ? Server stopped
2. [ ] ? Browser cache cleared (Ctrl+Shift+R)
3. [ ] ? FFmpeg installed (`ffmpeg -version`)
4. [ ] ? CORS configured (`.\configure-cors.ps1`)
5. [ ] ? No other instances running
6. [ ] ? Good internet connection (3+ Mbps upload)
7. [ ] ? Camera/microphone working
8. [ ] ? Ports not blocked by firewall

After starting:

9. [ ] ? Server starts without errors
10. [ ] ? FFmpeg process starts
11. [ ] ? Segments upload every 3 seconds
12. [ ] ? Manifest updates every 1 second
13. [ ] ? Viewer connects successfully
14. [ ] ? Buffer grows to 5+ seconds
15. [ ] ? Playback is smooth

---

**If all checked:** You're good to go! ??  
**If issues persist:** Run diagnostics and review documentation.

---

**Version:** 2.1  
**Last Updated:** 2024-01-15  
**Status:** Ready to Deploy
