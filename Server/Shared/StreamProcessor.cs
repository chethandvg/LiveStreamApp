using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text;

namespace Server.Shared
{
    public class StreamProcessor
    {
        private readonly string _streamId;
        private readonly BlockingCollection<byte[]> _inputBuffer;
        private readonly IConfiguration _configuration;
        private readonly ILogger _logger;
        private Process? _ffmpegProcess;
        private readonly string _outputDirectory;
        private FileSystemWatcher? _fileWatcher;
        private BlobContainerClient? _blobContainer;
        private readonly HashSet<string> _uploadedFiles = new();
        private readonly object _uploadLock = new object();

        public bool IsCompleted { get; private set; }

        public StreamProcessor(
            string streamId,
            BlockingCollection<byte[]> inputBuffer,
            IConfiguration configuration,
            ILogger logger)
        {
            _streamId = streamId;
            _inputBuffer = inputBuffer;
            _configuration = configuration;
            _logger = logger;
            _outputDirectory = Path.Combine(Path.GetTempPath(), "livestreams", streamId);
            Directory.CreateDirectory(_outputDirectory);
        }

        public async Task ProcessStreamAsync(CancellationToken cancellationToken)
        {
            try
            {
                _logger.LogInformation($"Starting stream processor for {_streamId}");

                // Initialize Azure Blob Storage
                var connectionString = _configuration["AzureStorage:ConnectionString"];
                var containerName = _configuration["AzureStorage:ContainerName"] ?? "livestreams";

                if (string.IsNullOrEmpty(connectionString))
                {
                    _logger.LogError("Azure Storage connection string is missing!");
                    return;
                }

                var blobServiceClient = new BlobServiceClient(connectionString);
                _blobContainer = blobServiceClient.GetBlobContainerClient(containerName);
                await _blobContainer.CreateIfNotExistsAsync(PublicAccessType.Blob, cancellationToken: cancellationToken);

                _logger.LogInformation($"Connected to Azure Blob Storage container: {containerName}");

                // Start file watcher to upload segments as they're created
                StartFileWatcher();

                // Start FFmpeg process
                StartFFmpegProcess();

                // Give FFmpeg a moment to start, then check for initial manifest
                _ = Task.Run(async () =>
                {
                    await Task.Delay(5000); // Wait 5 seconds for FFmpeg to create initial files
                    
                    var manifestPath = Path.Combine(_outputDirectory, "index.m3u8");
                    if (File.Exists(manifestPath))
                    {
                        _logger.LogInformation("Initial manifest file found after 5 seconds, uploading...");
                        await OnFileCreatedAsync(manifestPath);
                    }
                    else
                    {
                        _logger.LogWarning("Manifest file not found after 5 seconds. Waiting for FFmpeg...");
                    }
                    
                    // Check again after 10 seconds
                    await Task.Delay(5000);
                    if (File.Exists(manifestPath))
                    {
                        _logger.LogInformation("Manifest file found after 10 seconds, uploading...");
                        await OnFileCreatedAsync(manifestPath);
                    }
                }, cancellationToken);

                // Feed data to FFmpeg
                await FeedDataToFFmpegAsync(cancellationToken);

                _logger.LogInformation($"Stream {_streamId} processing completed");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error processing stream {_streamId}");
            }
            finally
            {
                CleanUp();
                IsCompleted = true;
            }
        }

        private void StartFFmpegProcess()
        {
            try
            {
                // Check if FFmpeg is available
                var ffmpegPath = FindFFmpegPath();
                if (string.IsNullOrEmpty(ffmpegPath))
                {
                    _logger.LogError("FFmpeg not found! Please install FFmpeg and ensure it's in the system PATH.");
                    throw new FileNotFoundException("FFmpeg executable not found");
                }

                _logger.LogInformation($"Found FFmpeg at: {ffmpegPath}");

                // FFmpeg command to convert WebM input to HLS output
                var arguments = new StringBuilder();
                arguments.Append("-f webm ");                          // Input format
                arguments.Append("-i pipe:0 ");                        // Read from stdin
                
                // Video encoding - optimized for speed and reliability
                arguments.Append("-c:v libx264 ");                     // Video codec H.264
                arguments.Append("-preset veryfast ");                 // Changed from ultrafast for better reliability
                arguments.Append("-tune zerolatency ");                // Minimize latency
                arguments.Append("-profile:v baseline ");              // Baseline profile for compatibility
                arguments.Append("-level 3.0 ");                       // H.264 level 3.0
                
                // Audio encoding
                arguments.Append("-c:a aac ");                         // Audio codec AAC
                arguments.Append("-b:a 128k ");                        // Audio bitrate
                arguments.Append("-ar 44100 ");                        // Audio sample rate
                
                // Video quality and rate control
                arguments.Append("-r 30 ");                            // Frame rate
                arguments.Append("-g 60 ");                            // GOP size (2 seconds at 30fps)
                arguments.Append("-keyint_min 60 ");                   // Minimum keyframe interval
                arguments.Append("-sc_threshold 0 ");                  // Disable scene change detection
                arguments.Append("-b:v 2500k ");                       // Video bitrate
                arguments.Append("-maxrate 3000k ");                   // Max bitrate
                arguments.Append("-bufsize 6000k ");                   // Buffer size (2x maxrate)
                
                // Fast startup
                arguments.Append("-probesize 32 ");                    // Reduce probe size
                arguments.Append("-analyzeduration 0 ");               // Reduce analyze time
                arguments.Append("-fflags nobuffer ");                 // Disable buffering
                arguments.Append("-flags low_delay ");                 // Low delay mode
                
                // HLS specific settings - optimized for live streaming
                arguments.Append("-f hls ");                           // Output format HLS
                arguments.Append("-hls_time 3 ");                      // Increased to 3-second segments for stability
                arguments.Append("-hls_list_size 6 ");                 // Keep last 6 segments (18 seconds)
                arguments.Append("-hls_flags delete_segments+append_list+program_date_time+independent_segments ");
                arguments.Append("-hls_allow_cache 0 ");               // Disable caching for live content
                arguments.Append("-hls_segment_type mpegts ");         // Use MPEG-TS format
                arguments.Append("-start_number 0 ");                  // Start segment numbering from 0
                arguments.Append("-hls_init_time 3 ");                 // Initial segment duration
                arguments.Append("-hls_segment_filename ");
                arguments.Append($"\"{Path.Combine(_outputDirectory, "segment_%03d.ts")}\" ");
                arguments.Append($"\"{Path.Combine(_outputDirectory, "index.m3u8")}\"");

                _logger.LogInformation($"FFmpeg arguments: {arguments}");

                _ffmpegProcess = new Process
                {
                    StartInfo = new ProcessStartInfo
                    {
                        FileName = ffmpegPath,
                        Arguments = arguments.ToString(),
                        UseShellExecute = false,
                        RedirectStandardInput = true,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        CreateNoWindow = true
                    }
                };

                _ffmpegProcess.OutputDataReceived += (s, e) =>
                {
                    if (!string.IsNullOrEmpty(e.Data))
                        _logger.LogDebug($"FFmpeg output: {e.Data}");
                };

                _ffmpegProcess.ErrorDataReceived += (s, e) =>
                {
                    if (!string.IsNullOrEmpty(e.Data))
                    {
                        _logger.LogDebug($"FFmpeg: {e.Data}");
                        
                        // Log important warnings/errors at higher level
                        if (e.Data.Contains("error", StringComparison.OrdinalIgnoreCase) ||
                            e.Data.Contains("failed", StringComparison.OrdinalIgnoreCase))
                        {
                            _logger.LogWarning($"FFmpeg issue: {e.Data}");
                        }
                    }
                };

                _ffmpegProcess.Start();
                _ffmpegProcess.BeginOutputReadLine();
                _ffmpegProcess.BeginErrorReadLine();

                _logger.LogInformation($"FFmpeg process started for stream {_streamId} (PID: {_ffmpegProcess.Id})");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to start FFmpeg process");
                throw;
            }
        }

        private string? FindFFmpegPath()
        {
            // Try common locations
            var paths = new[]
            {
                "ffmpeg", // In PATH
                "ffmpeg.exe", // In PATH (Windows)
                "/usr/bin/ffmpeg", // Linux
                "/usr/local/bin/ffmpeg", // macOS
                @"C:\ffmpeg\bin\ffmpeg.exe", // Common Windows location
            };

            foreach (var path in paths)
            {
                try
                {
                    var process = Process.Start(new ProcessStartInfo
                    {
                        FileName = path,
                        Arguments = "-version",
                        UseShellExecute = false,
                        RedirectStandardOutput = true,
                        CreateNoWindow = true
                    });
                    
                    if (process != null)
                    {
                        process.WaitForExit(1000);
                        if (process.ExitCode == 0)
                        {
                            return path;
                        }
                    }
                }
                catch
                {
                    continue;
                }
            }

            return null;
        }

        private async Task FeedDataToFFmpegAsync(CancellationToken cancellationToken)
        {
            if (_ffmpegProcess?.StandardInput == null)
            {
                throw new InvalidOperationException("FFmpeg process not started");
            }

            try
            {
                await using var stdin = _ffmpegProcess.StandardInput.BaseStream;
                var chunkCount = 0;

                foreach (var chunk in _inputBuffer.GetConsumingEnumerable(cancellationToken))
                {
                    await stdin.WriteAsync(chunk, 0, chunk.Length, cancellationToken);
                    await stdin.FlushAsync(cancellationToken);
                    chunkCount++;

                    if (chunkCount % 10 == 0)
                    {
                        _logger.LogDebug($"Fed {chunkCount} chunks to FFmpeg for stream {_streamId}");
                    }
                }

                _logger.LogInformation($"Finished feeding data to FFmpeg for stream {_streamId}. Total chunks: {chunkCount}");
            }
            catch (OperationCanceledException)
            {
                _logger.LogInformation($"Stream {_streamId} feed cancelled");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error feeding data to FFmpeg for stream {_streamId}");
            }
        }

        private void StartFileWatcher()
        {
            _fileWatcher = new FileSystemWatcher(_outputDirectory)
            {
                Filter = "*.*",
                NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.CreationTime,
                IncludeSubdirectories = false
            };

            _fileWatcher.Created += async (s, e) => await OnFileCreatedAsync(e.FullPath);
            _fileWatcher.Changed += async (s, e) => await OnFileChangedAsync(e.FullPath);
            _fileWatcher.EnableRaisingEvents = true;

            _logger.LogInformation($"File watcher started for {_outputDirectory}");
            
            // Start periodic check for manifest file to ensure it gets uploaded
            _ = Task.Run(async () => await PeriodicManifestCheckAsync());
        }

        private async Task PeriodicManifestCheckAsync()
        {
            while (!IsCompleted)
            {
                try
                {
                    await Task.Delay(1000); // Check every 1 second instead of 2
                    
                    var manifestPath = Path.Combine(_outputDirectory, "index.m3u8");
                    if (File.Exists(manifestPath))
                    {
                        var fileInfo = new FileInfo(manifestPath);
                        var key = $"index.m3u8_{fileInfo.Length}_{fileInfo.LastWriteTimeUtc.Ticks}";
                        
                        bool shouldUpload = false;
                        lock (_uploadLock)
                        {
                            if (!_uploadedFiles.Contains(key))
                            {
                                shouldUpload = true;
                                
                                // Also check if it's been more than 2 seconds since last upload
                                var oldKeys = _uploadedFiles.Where(k => k.StartsWith("index.m3u8_")).ToList();
                                if (oldKeys.Any())
                                {
                                    // Remove old manifest keys to force re-upload
                                    foreach (var oldKey in oldKeys)
                                    {
                                        _uploadedFiles.Remove(oldKey);
                                    }
                                }
                            }
                        }
                        
                        if (shouldUpload)
                        {
                            _logger.LogInformation("Periodic check: Uploading updated manifest");
                            await OnFileCreatedAsync(manifestPath);
                        }
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Error in periodic manifest check");
                }
            }
        }

        private async Task OnFileChangedAsync(string filePath)
        {
            // Always handle m3u8 file changes (playlist updates)
            if (Path.GetExtension(filePath).Equals(".m3u8", StringComparison.OrdinalIgnoreCase))
            {
                _logger.LogDebug($"Manifest file changed detected: {Path.GetFileName(filePath)}");
                await OnFileCreatedAsync(filePath);
            }
        }

        private async Task OnFileCreatedAsync(string filePath)
        {
            var fileName = Path.GetFileName(filePath);
            
            // Ignore temporary files created by FFmpeg (but log them for debugging)
            if (fileName.EndsWith(".tmp", StringComparison.OrdinalIgnoreCase))
            {
                _logger.LogDebug($"Ignoring temp file: {fileName}");
                return;
            }

            // Check if file exists before processing
            if (!File.Exists(filePath))
            {
                _logger.LogDebug($"File {fileName} no longer exists, skipping");
                return;
            }

            // Get file info once and safely
            FileInfo fileInfo;
            try
            {
                fileInfo = new FileInfo(filePath);
                
                // For manifest files, always log detection
                if (fileName.EndsWith(".m3u8", StringComparison.OrdinalIgnoreCase))
                {
                    _logger.LogInformation($"📄 Manifest file detected: {fileName} ({fileInfo.Length} bytes)");
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, $"Cannot access file {fileName}, skipping");
                return;
            }

            var key = $"{fileName}_{fileInfo.Length}";
            
            // Avoid duplicate uploads
            bool isNewFile = false;
            lock (_uploadLock)
            {
                if (!_uploadedFiles.Contains(key))
                {
                    _uploadedFiles.Add(key);
                    isNewFile = true;
                }
            }
            
            if (!isNewFile)
            {
                _logger.LogDebug($"File {fileName} with same size already uploaded, skipping");
                return;
            }

            try
            {
                _logger.LogInformation($"📤 Preparing to upload: {fileName}");

                // Wait for file to be fully written with retries
                var retries = 0;
                var maxRetries = fileName.EndsWith(".m3u8", StringComparison.OrdinalIgnoreCase) ? 10 : 5;
                
                while (retries < maxRetries)
                {
                    try
                    {
                        await Task.Delay(200 * (retries + 1)); // Progressive delay
                        
                        // Try to open the file
                        using var testStream = File.Open(filePath, FileMode.Open, FileAccess.Read, FileShare.Read);
                        _logger.LogDebug($"File {fileName} is ready to upload (attempt {retries + 1})");
                        break;
                    }
                    catch (IOException ex)
                    {
                        retries++;
                        if (retries >= maxRetries)
                        {
                            _logger.LogError($"File {fileName} still locked after {retries} retries: {ex.Message}");
                            throw;
                        }
                        _logger.LogDebug($"File {fileName} is locked, retry {retries}/{maxRetries}");
                    }
                }

                // Upload to Azure Blob Storage
                if (_blobContainer != null)
                {
                    // Important: Use correct path structure that matches CDN configuration
                    // Container is "livestreams", path should be "{streamId}/{fileName}"
                    // This results in URL: https://cdn.azurefd.net/livestreams/{streamId}/{fileName}
                    var blobPath = $"{_streamId}/{fileName}";
                    var blobClient = _blobContainer.GetBlobClient(blobPath);

                    // Set content type based on file extension
                    var contentType = fileName.EndsWith(".m3u8")
                        ? "application/vnd.apple.mpegurl"
                        : "video/MP2T";

                    var options = new BlobUploadOptions
                    {
                        HttpHeaders = new BlobHttpHeaders
                        {
                            ContentType = contentType,
                            CacheControl = fileName.EndsWith(".m3u8") ? "no-cache, no-store, must-revalidate" : "max-age=31536000",
                            ContentDisposition = "inline"
                        },
                        Conditions = null,
                        AccessTier = Azure.Storage.Blobs.Models.AccessTier.Hot
                    };

                    // Upload with retry
                    await using var fileStream = File.OpenRead(filePath);
                    await blobClient.UploadAsync(fileStream, options, cancellationToken: CancellationToken.None);

                    // Calculate full CDN URL for verification
                    var cdnUrl = $"{_blobContainer.Uri}/{blobPath}";
                    
                    if (fileName.EndsWith(".m3u8", StringComparison.OrdinalIgnoreCase))
                    {
                        _logger.LogInformation($"✅ MANIFEST UPLOADED SUCCESSFULLY!");
                        _logger.LogInformation($"  → Blob path: {blobPath}");
                        _logger.LogInformation($"  → Size: {fileStream.Length} bytes");
                        _logger.LogInformation($"  → Storage URL: {cdnUrl}");
                        _logger.LogInformation($"  → Content-Type: {contentType}");
                        _logger.LogInformation($"  → Cache-Control: no-cache (for live updates)");
                    }
                    else
                    {
                        _logger.LogInformation($"✓ Uploaded {fileName} to Azure Blob Storage");
                        _logger.LogInformation($"  → Blob path: {blobPath}");
                        _logger.LogInformation($"  → Size: {fileStream.Length} bytes");
                        _logger.LogInformation($"  → Storage URL: {cdnUrl}");
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"❌ Error uploading file {filePath}");
                
                // Remove from uploaded set so it can be retried
                lock (_uploadLock)
                {
                    _uploadedFiles.Remove(key);
                }
            }
        }

        private void CleanUp()
        {
            _logger.LogInformation($"Cleaning up stream {_streamId}");

            _fileWatcher?.Dispose();

            if (_ffmpegProcess != null && !_ffmpegProcess.HasExited)
            {
                try
                {
                    _ffmpegProcess.Kill();
                    _ffmpegProcess.WaitForExit(5000);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Error killing FFmpeg process");
                }
                _ffmpegProcess.Dispose();
            }

            try
            {
                if (Directory.Exists(_outputDirectory))
                {
                    Directory.Delete(_outputDirectory, true);
                    _logger.LogInformation($"Deleted temporary directory: {_outputDirectory}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, $"Failed to clean up directory {_outputDirectory}");
            }
        }
    }
}
