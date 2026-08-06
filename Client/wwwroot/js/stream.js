// ==========================================
// BROADCASTER FUNCTIONS
// ==========================================

let mediaRecorder = null;
let stream = null;
let uploadInterval = null;
let bytesCallback = null; // Callback to notify Blazor about bytes sent

async function startCapture(streamId, dotnetHelper) {
    try {
        console.log('Starting capture for stream:', streamId);
        console.log('DotNet helper received:', dotnetHelper ? 'YES' : 'NO');

        // Store the .NET reference for callbacks
        if (dotnetHelper) {
            bytesCallback = dotnetHelper;
            console.log('✅ Callback registered successfully');
        } else {
            console.warn('⚠️ No DotNet helper provided - bytes tracking will not work');
        }

        // Request user media with optimal settings
        const constraints = {
            video: {
                width: { ideal: 1280 },
                height: { ideal: 720 },
                frameRate: { ideal: 30 }
            },
            audio: {
                echoCancellation: true,
                noiseSuppression: true,
                autoGainControl: true
            }
        };

        stream = await navigator.mediaDevices.getUserMedia(constraints);

        // Display local preview
        const videoElement = document.getElementById('localVideo');
        if (videoElement) {
            videoElement.srcObject = stream;
        }

        // Check codec support
        const mimeType = getSupportedMimeType();
        if (!mimeType) {
            throw new Error('No supported video codec found');
        }

        console.log('Using MIME type:', mimeType);

        // Create MediaRecorder
        const options = {
            mimeType: mimeType,
            videoBitsPerSecond: 2500000, // 2.5 Mbps
            audioBitsPerSecond: 128000    // 128 kbps
        };

        mediaRecorder = new MediaRecorder(stream, options);

        // Handle data available event
        mediaRecorder.ondataavailable = async (event) => {
            if (event.data && event.data.size > 0) {
                console.log('Chunk size:', event.data.size, 'bytes');
                await uploadChunk(streamId, event.data);
            }
        };

        mediaRecorder.onerror = (event) => {
            console.error('MediaRecorder error:', event.error);
            alert('Recording error: ' + event.error.name);
        };

        mediaRecorder.onstart = () => {
            console.log('MediaRecorder started');
        };

        mediaRecorder.onstop = () => {
            console.log('MediaRecorder stopped');
        };

        // Start recording with 1-second chunks
        mediaRecorder.start(1000);

        return true;
    } catch (err) {
        console.error('Error starting capture:', err);
        alert('Failed to access camera/microphone: ' + err.message);
        return false;
    }
}

function getSupportedMimeType() {
    const types = [
        'video/webm;codecs=vp9,opus',
        'video/webm;codecs=vp8,opus',
        'video/webm;codecs=h264,opus',
        'video/webm',
        'video/mp4'
    ];

    for (const type of types) {
        if (MediaRecorder.isTypeSupported(type)) {
            return type;
        }
    }

    return null;
}

async function uploadChunk(streamId, blob) {
    try {
        // Convert Blob to ArrayBuffer
        const arrayBuffer = await blob.arrayBuffer();
        
        console.log(`📤 Uploading chunk: ${arrayBuffer.byteLength} bytes`);

        // Upload via Fetch API
        const response = await fetch(`/api/streamingest/upload/${streamId}`, {
            method: 'POST',
            body: arrayBuffer,
            headers: {
                'Content-Type': 'application/octet-stream'
            }
        });

        if (!response.ok) {
            const errorText = await response.text();
            console.error('Upload failed:', response.status, errorText);

            // If buffer is full (429), slow down
            if (response.status === 429) {
                console.warn('Server buffer full, pausing briefly...');
                await new Promise(resolve => setTimeout(resolve, 2000));
            }
        } else {
            const result = await response.json();
            console.log('✅ Uploaded:', result.received, 'bytes');
            
            // Notify Blazor component about bytes sent
            if (bytesCallback) {
                try {
                    console.log(`🔔 Calling UpdateBytesSent with ${result.received} bytes`);
                    await bytesCallback.invokeMethodAsync('UpdateBytesSent', result.received);
                    console.log('✅ Blazor callback completed successfully');
                } catch (err) {
                    console.error('❌ Error calling .NET callback:', err);
                }
            } else {
                console.warn('⚠️ No callback registered - cannot update Blazor component');
            }
        }
    } catch (error) {
        console.error('Upload error:', error);
        // Don't alert on every error to avoid spam
        // Just log and continue
    }
}

function stopCapture() {
    console.log('Stopping capture');

    if (mediaRecorder && mediaRecorder.state !== 'inactive') {
        mediaRecorder.stop();
    }

    if (stream) {
        stream.getTracks().forEach(track => {
            track.stop();
            console.log('Stopped track:', track.kind);
        });
        stream = null;
    }

    // Clear local video
    const videoElement = document.getElementById('localVideo');
    if (videoElement) {
        videoElement.srcObject = null;
    }

    mediaRecorder = null;
    bytesCallback = null; // Clear the callback
}

// ==========================================
// VIEWER FUNCTIONS (HLS PLAYER)
// ==========================================

let hlsInstance = null;

function initPlayer(streamUrl, videoElementId) {
    console.log('Initializing player for:', streamUrl);

    const video = document.getElementById(videoElementId);
    if (!video) {
        console.error('Video element not found:', videoElementId);
        return false;
    }

    // Destroy existing HLS instance if any
    if (hlsInstance) {
        hlsInstance.destroy();
        hlsInstance = null;
    }

    // Check for HLS.js support
    if (Hls.isSupported()) {
        console.log('Using HLS.js for playback');

        hlsInstance = new Hls({
            debug: false,
            enableWorker: true,
            lowLatencyMode: false,
            
            // Buffer configuration - more aggressive
            backBufferLength: 90,
            maxBufferLength: 45,          // Increased from 30 to 45 seconds
            maxMaxBufferLength: 90,       // Increased from 60 to 90 seconds
            maxBufferSize: 120 * 1000 * 1000,  // Increased to 120MB
            maxBufferHole: 1.0,           // Increased from 0.5 to 1.0 second
            nudgeOffset: 0.1,             // Small nudge when stalling
            nudgeMaxRetry: 10,            // More retries for nudging
            
            // Manifest/Level loading
            manifestLoadingTimeOut: 15000,     // Increased timeout
            manifestLoadingMaxRetry: 30,       // More retries
            manifestLoadingRetryDelay: 2000,
            levelLoadingTimeOut: 15000,        // Increased timeout
            levelLoadingMaxRetry: 15,          // More retries
            levelLoadingRetryDelay: 1000,
            
            // Fragment loading - more aggressive
            fragLoadingTimeOut: 30000,         // Increased to 30 seconds
            fragLoadingMaxRetry: 10,           // More retries
            fragLoadingRetryDelay: 1000,
            startFragPrefetch: true,
            
            // Live streaming specific
            liveSyncDurationCount: 3,          // Keep 3 segments in sync
            liveMaxLatencyDurationCount: 10,   // Allow up to 10 segments latency
            liveDurationInfinity: true,        // Treat as infinite live stream
            
            // Additional optimizations
            enableSoftwareAES: true,           // Fallback for AES
            startLevel: -1,                    // Auto select start level
            
            xhrSetup: function (xhr, url) {
                xhr.withCredentials = false;
            }
        });

        let fatalErrorCount = 0;
        let bufferStalledCount = 0;
        let nudgeOnStallCount = 0;
        const maxFatalErrors = 5;              // Increased from 3
        const maxBufferStalledErrors = 20;     // Increased from 10
        const maxNudgeOnStallErrors = 15;      // Handle nudge errors

        // Error handling
        hlsInstance.on(Hls.Events.ERROR, function (event, data) {
            console.error('HLS error:', data);

            if (data.fatal) {
                fatalErrorCount++;
                
                switch (data.type) {
                    case Hls.ErrorTypes.NETWORK_ERROR:
                        console.error('Fatal network error:', data.details);
                        
                        if (data.response && data.response.code === 404) {
                            console.warn('Stream manifest not found (404). Stream may not have started yet.');
                            console.log(`Attempt ${fatalErrorCount}/${maxFatalErrors}: Will retry automatically...`);
                        } else if (data.response && data.response.code === 0) {
                            console.error('CORS or network connectivity issue detected');
                            console.error('Please ensure Azure Front Door CORS is properly configured');
                        }
                        
                        if (fatalErrorCount < maxFatalErrors) {
                            console.log('Attempting to recover from network error...');
                            setTimeout(() => {
                                hlsInstance.startLoad();
                            }, 2000);
                        } else {
                            console.error(`Failed after ${maxFatalErrors} attempts. Giving up.`);
                        }
                        break;
                        
                    case Hls.ErrorTypes.MEDIA_ERROR:
                        console.error('Fatal media error, trying to recover...');
                        if (fatalErrorCount < maxFatalErrors) {
                            hlsInstance.recoverMediaError();
                        }
                        break;
                        
                    default:
                        console.error('Fatal error, cannot recover:', data.type);
                        if (fatalErrorCount >= maxFatalErrors) {
                            hlsInstance.destroy();
                        }
                        break;
                }
            } else {
                // Non-fatal errors - handle more gracefully
                if (data.details === Hls.ErrorDetails.BUFFER_STALLED_ERROR) {
                    bufferStalledCount++;
                    console.warn(`Non-fatal buffer stalled error (${bufferStalledCount}/${maxBufferStalledErrors})`);
                    console.log(`Current buffer info:`, data.buffer);
                    
                    // Try to recover by seeking slightly forward
                    if (bufferStalledCount > 5 && video.currentTime > 0) {
                        console.log('Attempting to nudge playback forward by 0.1 seconds');
                        video.currentTime += 0.1;
                    }
                    
                    // Only treat as fatal if it happens too frequently
                    if (bufferStalledCount >= maxBufferStalledErrors) {
                        console.error('Too many buffer stalled errors, attempting recovery...');
                        if (hlsInstance) {
                            hlsInstance.recoverMediaError();
                        }
                        bufferStalledCount = 0; // Reset counter after recovery attempt
                    }
                } else if (data.details === Hls.ErrorDetails.BUFFER_NUDGE_ON_STALL) {
                    nudgeOnStallCount++;
                    console.warn(`Buffer nudge on stall (${nudgeOnStallCount}/${maxNudgeOnStallErrors})`);
                    
                    // This is actually HLS.js trying to fix the stall - usually good
                    if (nudgeOnStallCount < maxNudgeOnStallErrors) {
                        console.log('HLS.js is automatically handling the stall by nudging playback');
                    } else {
                        console.error('Too many nudge attempts, trying media error recovery');
                        hlsInstance.recoverMediaError();
                        nudgeOnStallCount = 0;
                    }
                } else {
                    console.warn('Non-fatal HLS error:', data.type, data.details);
                }
                
                // Reset fatal error count on successful recovery from non-fatal errors
                if (data.type === Hls.ErrorTypes.NETWORK_ERROR && data.details === Hls.ErrorDetails.MANIFEST_LOAD_ERROR) {
                    console.log('Manifest load error, will retry...');
                }
            }
        });

        // Load stream
        hlsInstance.loadSource(streamUrl);
        hlsInstance.attachMedia(video);

        // Auto-play when manifest is parsed
        hlsInstance.on(Hls.Events.MANIFEST_PARSED, function () {
            console.log('✓ Manifest parsed successfully, starting playback');
            fatalErrorCount = 0;
            bufferStalledCount = 0;
            nudgeOnStallCount = 0;
            video.play().catch(e => {
                console.warn('Auto-play prevented:', e);
            });
        });

        // Monitor stream events
        hlsInstance.on(Hls.Events.FRAG_LOADED, function (event, data) {
            console.log('Fragment loaded:', data.frag.sn);
            fatalErrorCount = 0;
            bufferStalledCount = Math.max(0, bufferStalledCount - 1);
            nudgeOnStallCount = Math.max(0, nudgeOnStallCount - 1);
        });
        
        // Monitor level loaded (playlist updated)
        hlsInstance.on(Hls.Events.LEVEL_LOADED, function (event, data) {
            console.log('Level loaded, segments:', data.details.fragments.length);
        });

        // Monitor buffer events to diagnose stalling
        hlsInstance.on(Hls.Events.BUFFER_APPENDING, function () {
            if (bufferStalledCount > 0 || nudgeOnStallCount > 0) {
                console.log('Buffer appending - reducing error counts');
                bufferStalledCount = Math.max(0, bufferStalledCount - 1);
                nudgeOnStallCount = Math.max(0, nudgeOnStallCount - 1);
            }
        });
        
        // Monitor buffer appended
        hlsInstance.on(Hls.Events.BUFFER_APPENDED, function (event, data) {
            // Successfully appended data to buffer
            if (bufferStalledCount > 3 || nudgeOnStallCount > 3) {
                console.log('Buffer successfully appended, resetting error counters');
                bufferStalledCount = Math.max(0, Math.floor(bufferStalledCount / 2));
                nudgeOnStallCount = Math.max(0, Math.floor(nudgeOnStallCount / 2));
            }
        });
        
        // Monitor buffer flushing
        hlsInstance.on(Hls.Events.BUFFER_FLUSHING, function () {
            console.log('Buffer flushing...');
        });

        return true;
    }
    // Safari native HLS support
    else if (video.canPlayType('application/vnd.apple.mpegurl')) {
        console.log('Using native HLS support (Safari)');

        video.src = streamUrl;

        video.addEventListener('loadedmetadata', function () {
            console.log('Metadata loaded');
            video.play().catch(e => {
                console.warn('Auto-play prevented:', e);
            });
        });

        video.addEventListener('error', function (e) {
            console.error('Video error:', e);
            if (video.error) {
                console.error('Error code:', video.error.code);
                console.error('Error message:', video.error.message);
                
                if (video.error.code === 4) {
                    console.error('Media source not supported or file not found (404)');
                }
            }
        });

        return true;
    }
    else {
        console.error('HLS is not supported in this browser');
        alert('Your browser does not support HLS video streaming. Please use a modern browser.');
        return false;
    }
}

function destroyPlayer() {
    if (hlsInstance) {
        hlsInstance.destroy();
        hlsInstance = null;
        console.log('HLS instance destroyed');
    }
}

// ==========================================
// UTILITY FUNCTIONS
// ==========================================

function scrollChatToBottom() {
    const chatMessages = document.getElementById('chatMessages');
    if (chatMessages) {
        chatMessages.scrollTop = chatMessages.scrollHeight;
    }
}

// Check browser compatibility
function checkBrowserCompatibility() {
    const issues = [];

    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
        issues.push('getUserMedia not supported');
    }

    if (!window.MediaRecorder) {
        issues.push('MediaRecorder not supported');
    }

    if (!window.Hls && !document.createElement('video').canPlayType('application/vnd.apple.mpegurl')) {
        issues.push('HLS playback not supported');
    }

    if (issues.length > 0) {
        console.warn('Browser compatibility issues:', issues);
        return false;
    }

    return true;
}

// Initialize on page load
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
        checkBrowserCompatibility();
    });
} else {
    checkBrowserCompatibility();
}

// Export functions for Blazor
window.startCapture = startCapture;
window.stopCapture = stopCapture;
window.initPlayer = initPlayer;
window.destroyPlayer = destroyPlayer;
window.scrollChatToBottom = scrollChatToBottom;
window.checkBrowserCompatibility = checkBrowserCompatibility;