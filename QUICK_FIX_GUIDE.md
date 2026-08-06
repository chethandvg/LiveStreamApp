# Quick Start - Fixing HLS Streaming Issues

## ?? Immediate Actions (5 minutes)

### Step 1: Stop Current Server
```powershell
# Press Ctrl+C in server terminal to stop
```

### Step 2: Clear Browser Cache
```powershell
# IMPORTANT: Hard refresh to clear old JavaScript
# Windows/Linux: Ctrl+Shift+R
# Mac: Cmd+Shift+R
# Or open in incognito/private window
```

### Step 3: Run Diagnostics
```powershell
# Check what's wrong
.\diagnose-stream.ps1
```

### Step 4: Configure CORS (if needed)
```powershell
# Fix CORS issues
.\configure-cors.ps1
```

### Step 5: Restart Server
```powershell
cd Server
dotnet run
```

### Step 6: Test Streaming
1. Open: `https://localhost:7119/broadcast`
2. Click "Start Broadcast"
3. Wait 10-15 seconds for segments to generate
4. Open viewer in new tab/window
5. Check browser console (F12) - should see fewer errors

---

## ? What Was Fixed

### v2.1 - Buffer Stall Optimization

Your error logs showed:
- ? **bufferNudgeOnStall** errors
- ? **bufferStalledError** errors  
- ? **Low buffer** (0.079 seconds)

### Latest Fixes Applied (v2.1):

#### 1. **Increased Buffer Capacity**
```javascript
maxBufferLength: 45 seconds        // Was: 30 seconds
maxMaxBufferLength: 90 seconds     // Was: 60 seconds
maxBufferSize: 120MB               // Was: 60MB
```

#### 2. **Longer Segments**
```csharp
-hls_time 3                        // Was: 2 seconds
```
- Fewer segment transitions = fewer stall opportunities

#### 3. **Better FFmpeg Preset**
```csharp
-preset veryfast                   // Was: ultrafast
-profile:v baseline                // Better compatibility
-b:v 2500k -maxrate 3000k         // Bitrate control
```

#### 4. **Faster Manifest Updates**
```csharp
await Task.Delay(1000);            // Was: 2000ms
```

#### 5. **Enhanced Nudge Handling**
```javascript
nudgeOffset: 0.1
nudgeMaxRetry: 10
// Automatic playhead nudging when stalling
```

---

## ?? Expected Results

### Before (v2.0):
```
Fragment loaded: 11
? HLS error: Object
?? bufferNudgeOnStall
?? bufferStalledError
   Low buffer: 0.079 seconds
? Playback fails
```

### After (v2.1):
```
Fragment loaded: 11
?? Buffer nudge on stall (1/15)
   HLS.js is automatically handling the stall
? Buffer appending
? Buffer ahead: 15.3 seconds
? Fragment loaded: 12
? Playback continues smoothly
```

---

## ?? Verify Changes Applied

### Check JavaScript (Browser Console):
```javascript
// Should see new settings
console.log('maxBufferLength:', 45);
console.log('maxBufferSize:', 120000000);
console.log('nudgeOffset:', 0.1);
```

### Check Server Logs:
```
[INFO] FFmpeg arguments: ... -hls_time 3 ... -preset veryfast ...
[INFO] ? Uploaded segment_000.ts (every 3 seconds)
[INFO] Periodic check: Uploading updated manifest (every 1 second)
```

---

## ?? Still Having Issues?

### 1. Check Buffer in Real-Time

**Run this in browser console while playing:**
```javascript
setInterval(() => {
    const video = document.getElementById('hlsPlayer');
    if (video && video.buffered.length > 0) {
        const buffered = video.buffered.end(0) - video.currentTime;
        console.log(`Buffer: ${buffered.toFixed(1)}s`);
    }
}, 1000);
```

**Healthy:** 5-20 seconds  
**Warning:** < 3 seconds  
**Problem:** < 1 second

---

### 2. Run Stream-Specific Diagnostics
```powershell
.\diagnose-stream.ps1 -StreamId "your_stream_id"
```

---

### 3. Check FFmpeg is Generating Segments

**Server logs should show:**
```
10:00:00 ? Uploaded segment_000.ts
10:00:03 ? Uploaded segment_001.ts
10:00:06 ? Uploaded segment_002.ts
```

**If segments are slow (> 5 seconds apart):**
- Check server CPU usage
- Verify FFmpeg version: `ffmpeg -version`
- Check for FFmpeg errors in logs

---

### 4. Test Network Speed

```powershell
# Test segment download speed
$url = "https://your-cdn.azurefd.net/livestreams/your_stream_id/segment_000.ts"
Measure-Command { Invoke-WebRequest -Uri $url -OutFile "test.ts" }
```

**Should be:** < 2 seconds for a 3-second segment

---

## ?? Documentation

- **`BUFFER_STALL_RESOLUTION.md`** - Detailed buffer stall guide
- **`HLS_TROUBLESHOOTING.md`** - General HLS errors
- **`COMPLETE_SOLUTION.md`** - Full technical details

---

## ?? Key Points

1. **Clear browser cache!** Old JS may be cached
2. **Wait 10-15 seconds** after starting broadcast
3. **Monitor buffer** should be 5-20 seconds ahead
4. **Nudge errors are normal** - HLS.js is auto-handling them
5. **Check server logs** for segment upload frequency

---

## ? Quick Commands

```powershell
# Health check
.\diagnose-stream.ps1

# Fix CORS
.\configure-cors.ps1

# Start server
cd Server && dotnet run

# Check FFmpeg
ffmpeg -version

# Monitor buffer (in browser console)
setInterval(() => {
    const v = document.getElementById('hlsPlayer');
    if (v && v.buffered.length > 0) {
        console.log(`Buffer: ${(v.buffered.end(0) - v.currentTime).toFixed(1)}s`);
    }
}, 1000);
```

---

## ?? Success Criteria

? Broadcaster can start streaming without errors  
? Viewers can watch within 10-15 seconds  
? Buffer stays above 5 seconds  
? Nudge errors auto-recover  
? Playback is smooth  
? Segments upload every 3 seconds  

---

**Version:** 2.1 (Buffer Stall Optimization)  
**Last Updated:** 2024-01-15  
**Your streaming should now be much more stable! ??**
