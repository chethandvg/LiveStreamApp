# Buffer Stalled Error - Resolution Guide

## ?? Problem Analysis

You're experiencing:
- **bufferNudgeOnStall** errors
- **bufferStalledError** errors  
- **Low buffer situations** (< 0.1 seconds)

These occur when the HLS player runs out of video data to play because:
1. FFmpeg isn't generating segments fast enough
2. Network latency in segment delivery
3. Browser can't download segments quickly enough

---

## ? Fixes Applied

### 1. Enhanced HLS.js Buffer Configuration

**Changes Made:**
```javascript
// Increased buffer capacity
maxBufferLength: 45 seconds         // Was: 30 seconds
maxMaxBufferLength: 90 seconds      // Was: 60 seconds
maxBufferSize: 120MB                // Was: 60MB
maxBufferHole: 1.0 second           // Was: 0.5 seconds

// Better nudge handling
nudgeOffset: 0.1 seconds            // Small nudge when stalling
nudgeMaxRetry: 10                   // More retries

// Live streaming optimization
liveSyncDurationCount: 3            // Keep 3 segments in sync
liveMaxLatencyDurationCount: 10    // Allow 10 segments latency

// More aggressive retry policy
fragLoadingTimeOut: 30 seconds      // Was: 20 seconds
fragLoadingMaxRetry: 10             // Was: 6
```

**What This Does:**
- ? Player maintains larger buffer (up to 45-90 seconds)
- ? More tolerant of temporary slowdowns
- ? Automatic nudging when playback stalls
- ? Better handling of live streaming latency
- ? More retries before giving up

---

### 2. Optimized FFmpeg Segment Generation

**Changes Made:**
```bash
# Increased segment duration
-hls_time 3                    # Was: 2 seconds

# Better preset for reliability
-preset veryfast               # Was: ultrafast

# Bitrate control for stability
-b:v 2500k                     # Set video bitrate
-maxrate 3000k                 # Max bitrate
-bufsize 6000k                 # 2x buffer

# Smaller playlist for faster updates
-hls_list_size 6               # Was: 10 segments

# Better compatibility
-profile:v baseline            # H.264 baseline
-level 3.0                     # Level 3.0
```

**What This Does:**
- ? Longer segments = fewer segment transitions = fewer stall opportunities
- ? `veryfast` preset = better quality/speed balance
- ? Bitrate control = consistent segment sizes
- ? Smaller playlist = faster manifest downloads
- ? Baseline profile = better browser compatibility

---

### 3. Faster Manifest Updates

**Changes Made:**
```csharp
// Check every 1 second (was 2 seconds)
await Task.Delay(1000);

// Always re-upload manifests
foreach (var oldKey in oldKeys) {
    _uploadedFiles.Remove(oldKey);
}
```

**What This Does:**
- ? Viewers get fresh playlists more frequently
- ? Reduced chance of stale manifests
- ? Better live streaming experience

---

### 4. Enhanced Error Handling

**Changes Made:**
```javascript
// Track different error types separately
let bufferStalledCount = 0;
let nudgeOnStallCount = 0;

// Handle nudge errors
if (data.details === Hls.ErrorDetails.BUFFER_NUDGE_ON_STALL) {
    console.log('HLS.js is automatically handling the stall');
}

// Manual nudge if needed
if (bufferStalledCount > 5 && video.currentTime > 0) {
    video.currentTime += 0.1;  // Skip forward slightly
}

// Progressive counter reduction on success
hlsInstance.on(Hls.Events.BUFFER_APPENDED, function (event, data) {
    bufferStalledCount = Math.max(0, Math.floor(bufferStalledCount / 2));
});
```

**What This Does:**
- ? Different strategies for different error types
- ? Automatic playhead nudging
- ? Rewards successful buffer fills
- ? Better logging for debugging

---

## ?? How to Apply

### Step 1: Restart Server

The code changes are already applied. You need to restart:

```powershell
# Stop current server (Ctrl+C)

# Restart
cd Server
dotnet run
```

### Step 2: Clear Browser Cache

Important! Old HLS.js code may be cached:

```powershell
# Hard refresh: Ctrl+Shift+R (Windows) or Cmd+Shift+R (Mac)
# Or open in incognito/private window
```

### Step 3: Test Streaming

1. Open broadcaster: `https://localhost:7119/broadcast`
2. Start broadcast
3. Wait 10-15 seconds for initial segments
4. Open viewer in another tab/window
5. Monitor browser console (F12)

---

## ?? Expected Behavior

### Before Fixes:
```
Fragment loaded: 11
?? Non-fatal HLS error: mediaError bufferNudgeOnStall
? HLS error: Object
?? Non-fatal HLS error: mediaError bufferStalledError
   Error: Playback stalling at @219.920086 due to low buffer ({"len": 0.0799})
? Playback fails
```

### After Fixes:
```
Fragment loaded: 11
?? Buffer nudge on stall (1/15)
   HLS.js is automatically handling the stall by nudging playback
? Buffer appending - reducing error counts
? Buffer successfully appended, resetting error counters
? Fragment loaded: 12
? Playback continues smoothly
```

---

## ?? Advanced Troubleshooting

### If Buffer Stalls Continue:

#### 1. Check FFmpeg Output

**Server console should show:**
```
[INFO] FFmpeg process started for stream stream_12345 (PID: 1234)
[DEBUG] FFmpeg: frame=  100 fps= 30 q=28.0 size=     512kB time=00:00:03.33
[INFO] ? MANIFEST UPLOADED SUCCESSFULLY!
[INFO] ? Uploaded segment_000.ts to Azure Blob Storage
[INFO]   ? Size: 367280 bytes
[INFO] ? Uploaded segment_001.ts to Azure Blob Storage
```

**If FFmpeg warnings:**
```
[WARN] FFmpeg issue: [libx264 @ 0x...] error...
```

**Solution:** FFmpeg may be struggling. Try:
- Reduce resolution in broadcaster
- Check CPU usage
- Ensure FFmpeg is latest version

---

#### 2. Check Segment Upload Speed

**Server logs should show uploads every 3 seconds:**
```
10:00:00 ? Uploaded segment_000.ts
10:00:03 ? Uploaded segment_001.ts  ? 3 seconds apart
10:00:06 ? Uploaded segment_002.ts
```

**If uploads are slow (> 5 seconds apart):**
- Check Azure Storage connectivity
- Check upload bandwidth
- Check for network issues

---

#### 3. Monitor Browser Buffer

**Add to browser console while playing:**
```javascript
setInterval(() => {
    const video = document.getElementById('hlsPlayer');
    if (video && video.buffered.length > 0) {
        const bufferedEnd = video.buffered.end(video.buffered.length - 1);
        const currentTime = video.currentTime;
        const bufferAhead = bufferedEnd - currentTime;
        console.log(`Buffer ahead: ${bufferAhead.toFixed(2)}s`);
    }
}, 1000);
```

**Healthy buffer:** 5-20 seconds ahead  
**Warning:** < 3 seconds ahead  
**Critical:** < 1 second ahead

---

#### 4. Reduce Segment Duration (If Needed)

If 3-second segments are still causing issues:

**Server/Shared/StreamProcessor.cs:**
```csharp
// Try 2-second segments
arguments.Append("-hls_time 2 ");
```

**Trade-off:**
- ? More frequent updates
- ? More overhead
- ? More segment transitions

---

#### 5. Check Network Latency

**Test CDN response time:**
```powershell
$streamId = "your_stream_id"
$url = "https://your-cdn.azurefd.net/livestreams/$streamId/segment_000.ts"

Measure-Command {
    Invoke-WebRequest -Uri $url -Method HEAD
}
```

**Acceptable:** < 200ms  
**Slow:** 200-500ms  
**Problem:** > 500ms

**If slow:**
- Check Azure Front Door configuration
- Consider Azure Front Door Premium
- Check viewer's internet connection

---

## ?? Optimization Checklist

### Server-Side:

- [x] FFmpeg using `veryfast` preset
- [x] 3-second segment duration
- [x] Bitrate control enabled
- [x] Manifest updates every 1 second
- [x] Fast blob uploads
- [ ] Check server CPU usage (should be < 80%)
- [ ] Check server network bandwidth
- [ ] Monitor FFmpeg logs for errors

### Client-Side:

- [x] Large buffer configuration (45-90s)
- [x] Nudge handling enabled
- [x] Progressive error recovery
- [x] More retries before failing
- [ ] Browser cache cleared
- [ ] Using modern browser (Chrome 90+, Firefox 88+, Safari 14+)
- [ ] Good internet connection (3+ Mbps)

### Azure:

- [x] CORS configured
- [x] Blob access tier: Hot
- [x] CDN enabled
- [ ] Check Azure Storage performance metrics
- [ ] Check Azure Front Door cache hit ratio
- [ ] Monitor blob upload latency

---

## ?? Performance Targets

| Metric | Target | Acceptable | Problem |
|--------|--------|------------|---------|
| FFmpeg segment generation | 3s | < 5s | > 5s |
| Blob upload time | < 1s | < 2s | > 2s |
| Manifest update frequency | Every 1s | Every 2s | > 3s |
| Player buffer ahead | 10-30s | 5-10s | < 5s |
| Buffer stall events | 0 | < 5/min | > 10/min |
| CDN latency | < 100ms | < 300ms | > 500ms |

---

## ??? Diagnostic Commands

### Check Current Stream Health:
```powershell
# Run diagnostics
.\diagnose-stream.ps1 -StreamId "your_stream_id"

# Check FFmpeg
Get-Process | Where-Object { $_.ProcessName -eq "ffmpeg" }

# Monitor server logs
# Watch for "Uploaded segment_XXX.ts" every 3 seconds
```

### Test Segment Download Speed:
```powershell
$streamId = "your_stream_id"
$cdnUrl = "https://your-cdn.azurefd.net/livestreams"

# Download a segment and measure time
Measure-Command {
    Invoke-WebRequest -Uri "$cdnUrl/$streamId/segment_000.ts" -OutFile "test.ts"
}

# Should be < 2 seconds for a 3-second segment
```

---

## ?? Quick Fixes

### If Stalls Persist After Changes:

1. **Increase Buffer Even More:**
   ```javascript
   // In stream.js
   maxBufferLength: 60,        // Increase to 60 seconds
   maxMaxBufferLength: 120,    // Increase to 2 minutes
   ```

2. **Reduce Video Quality:**
   ```csharp
   // In StreamProcessor.cs
   arguments.Append("-b:v 1500k ");     // Lower bitrate
   arguments.Append("-s 1280x720 ");    // Ensure 720p max
   arguments.Append("-r 25 ");          // Lower frame rate
   ```

3. **Use Shorter Segments:**
   ```csharp
   // In StreamProcessor.cs
   arguments.Append("-hls_time 2 ");    // Back to 2 seconds
   ```

4. **Restart Everything:**
   ```powershell
   # Stop server
   # Clear browser cache
   # Restart server
   # Start new broadcast
   # Test with fresh viewer
   ```

---

## ?? Still Having Issues?

### Collect Detailed Diagnostics:

```powershell
# 1. Run diagnostics
.\diagnose-stream.ps1 -StreamId "your_stream_id" > diagnostics.txt

# 2. Collect logs
# Server console output
# Browser console (F12) output

# 3. Check FFmpeg
ffmpeg -version > ffmpeg-info.txt

# 4. Test network
Test-Connection livestream-signalr-service-cgbaanhtf0athweb.z03.azurefd.net >> diagnostics.txt
```

### Review Documentation:

- **`HLS_TROUBLESHOOTING.md`** - General HLS issues
- **`COMPLETE_SOLUTION.md`** - Full technical details
- **`QUICK_FIX_GUIDE.md`** - Quick reference

---

## ? Summary

**Key Changes:**
1. ? Larger player buffer (45-90 seconds)
2. ? 3-second segments for stability
3. ? Better FFmpeg encoding preset
4. ? Faster manifest updates
5. ? Enhanced error handling

**Expected Results:**
- Buffer stalls should be rare
- Automatic recovery when they occur
- Smoother playback experience
- Better logging for debugging

**Next Steps:**
1. Restart server
2. Clear browser cache
3. Test streaming
4. Monitor console logs
5. Check metrics against targets

---

**If buffer stalls continue, it likely indicates:**
- Network bandwidth issues (broadcaster or viewer)
- CPU constraints on server
- Azure Storage performance issues

**Run diagnostics and check the Performance Targets section above.**

---

**Date:** 2024-01-15  
**Version:** 2.1  
**Status:** ? Optimized for Low Buffer Situations
