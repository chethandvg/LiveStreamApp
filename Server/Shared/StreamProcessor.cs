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
                // Initialize Azure Blob Storage
                var connectionString = _configuration["AzureStorage:ConnectionString"];
                var containerName = _configuration["AzureStorage:ContainerName"] ?? "livestreams";

                var blobServiceClient = new BlobServiceClient(connectionString);
                _blobContainer = blobServiceClient.GetBlobContainerClient(containerName);
                await _blobContainer.CreateIfNotExistsAsync(PublicAccessType.Blob, cancellationToken: cancellationToken);

                // Start file watcher to upload segments as they're created
                StartFileWatcher();

                // Start FFmpeg process
                StartFFmpegProcess();

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
            // FFmpeg command to convert WebM input to HLS output
            var arguments = new StringBuilder();
            arguments.Append("-f webm ");                          // Input format
            arguments.Append("-i pipe:0 ");                        // Read from stdin
            arguments.Append("-c:v libx264 ");                     // Video codec H.264
            arguments.Append("-preset ultrafast ");                // Fast encoding for live streaming
            arguments.Append("-tune zerolatency ");                // Minimize latency
            arguments.Append("-c:a aac ");                         // Audio codec AAC
            arguments.Append("-b:a 128k ");                        // Audio bitrate
            arguments.Append("-ar 44100 ");                        // Audio sample rate
            arguments.Append("-r 30 ");                            // Frame rate
            arguments.Append("-g 60 ");                            // GOP size (2 seconds at 30fps)
            arguments.Append("-sc_threshold 0 ");                  // Disable scene change detection
            arguments.Append("-f hls ");                           // Output format HLS
            arguments.Append("-hls_time 2 ");                      // 2-second segments
            arguments.Append("-hls_list_size 10 ");                // Keep last 10 segments in playlist
            arguments.Append("-hls_flags delete_segments+append_list ");  // Delete old segments
            arguments.Append("-hls_segment_filename ");
            arguments.Append($"\"{Path.Combine(_outputDirectory, "segment_%03d.ts")}\" ");
            arguments.Append($"\"{Path.Combine(_outputDirectory, "index.m3u8")}\"");

            _ffmpegProcess = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = "ffmpeg",  // Ensure FFmpeg is in PATH or use full path
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
                    _logger.LogDebug($"FFmpeg error: {e.Data}");
            };

            _ffmpegProcess.Start();
            _ffmpegProcess.BeginOutputReadLine();
            _ffmpegProcess.BeginErrorReadLine();

            _logger.LogInformation($"FFmpeg process started for stream {_streamId}");
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

                foreach (var chunk in _inputBuffer.GetConsumingEnumerable(cancellationToken))
                {
                    await stdin.WriteAsync(chunk, 0, chunk.Length, cancellationToken);
                    await stdin.FlushAsync(cancellationToken);
                }

                _logger.LogInformation($"Finished feeding data to FFmpeg for stream {_streamId}");
            }
            catch (OperationCanceledException)
            {
                _logger.LogInformation($"Stream {_streamId} feed cancelled");
            }
        }

        private void StartFileWatcher()
        {
            _fileWatcher = new FileSystemWatcher(_outputDirectory)
            {
                Filter = "*.*",
                NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite
            };

            _fileWatcher.Created += async (s, e) => await OnFileCreatedAsync(e.FullPath);
            _fileWatcher.Changed += async (s, e) => await OnFileCreatedAsync(e.FullPath);
            _fileWatcher.EnableRaisingEvents = true;

            _logger.LogInformation($"File watcher started for {_outputDirectory}");
        }

        private async Task OnFileCreatedAsync(string filePath)
        {
            try
            {
                var fileName = Path.GetFileName(filePath);
                _logger.LogInformation($"Detected new file: {fileName}");

                // Wait for file to be fully written
                await Task.Delay(500);

                // Upload to Azure Blob Storage
                if (_blobContainer != null)
                {
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
                            CacheControl = "max-age=2"  // Short cache for live content
                        }
                    };

                    await using var fileStream = File.OpenRead(filePath);
                    await blobClient.UploadAsync(fileStream, options, cancellationToken: CancellationToken.None);

                    _logger.LogInformation($"Uploaded {fileName} to Azure Blob Storage at {blobPath}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error uploading file {filePath}");
            }
        }

        private void CleanUp()
        {
            _fileWatcher?.Dispose();

            if (_ffmpegProcess != null && !_ffmpegProcess.HasExited)
            {
                _ffmpegProcess.Kill();
                _ffmpegProcess.Dispose();
            }

            try
            {
                if (Directory.Exists(_outputDirectory))
                {
                    Directory.Delete(_outputDirectory, true);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, $"Failed to clean up directory {_outputDirectory}");
            }
        }
    }
}
