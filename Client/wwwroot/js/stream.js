// ==========================================
// BROADCASTER FUNCTIONS
// ==========================================

let mediaRecorder = null;
let stream = null;
let uploadInterval = null;

async function startCapture(streamId) {
    try {
        console.log('Starting capture for stream:', streamId);

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
            console.log('Uploaded:', result.received, 'bytes');
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
            backBufferLength: 90,
            maxBufferLength: 30,
            maxMaxBufferLength: 60,
            manifestLoadingTimeOut: 10000,
            manifestLoadingMaxRetry: 4,
            manifestLoadingRetryDelay: 1000,
            levelLoadingTimeOut: 10000,
            levelLoadingMaxRetry: 4,
            levelLoadingRetryDelay: 1000
        });

        // Error handling
        hlsInstance.on(Hls.Events.ERROR, function (event, data) {
            console.error('HLS error:', data);

            if (data.fatal) {
                switch (data.type) {
                    case Hls.ErrorTypes.NETWORK_ERROR:
                        console.error('Fatal network error, trying to recover...');
                        hlsInstance.startLoad();
                        break;
                    case Hls.ErrorTypes.MEDIA_ERROR:
                        console.error('Fatal media error, trying to recover...');
                        hlsInstance.recoverMediaError();
                        break;
                    default:
                        console.error('Fatal error, cannot recover');
                        hlsInstance.destroy();
                        alert('Stream playback failed. Please refresh the page.');
                        break;
                }
            }
        });

        // Load stream
        hlsInstance.loadSource(streamUrl);
        hlsInstance.attachMedia(video);

        // Auto-play when manifest is parsed
        hlsInstance.on(Hls.Events.MANIFEST_PARSED, function () {
            console.log('Manifest parsed, starting playback');
            video.play().catch(e => {
                console.warn('Auto-play prevented:', e);
                // User needs to click play button
            });
        });

        // Monitor stream events
        hlsInstance.on(Hls.Events.FRAG_LOADED, function (event, data) {
            console.log('Fragment loaded:', data.frag.sn);
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
            alert('Stream playback failed. Please refresh the page.');
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