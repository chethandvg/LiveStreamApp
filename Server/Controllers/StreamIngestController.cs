using Microsoft.AspNetCore.Mvc;
using Server.Shared;
using System.Collections.Concurrent;

namespace Server.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class StreamIngestController : ControllerBase
    {
        private readonly ILogger<StreamIngestController> _logger;

        // Buffer between HTTP requests and FFmpeg process
        public static readonly ConcurrentDictionary<string, BlockingCollection<byte[]>> ActiveStreams = new();

        // Track stream metadata
        private static readonly ConcurrentDictionary<string, StreamMetadata> _streamMetadata = new();

        public StreamIngestController(ILogger<StreamIngestController> logger)
        {
            _logger = logger;
        }

        [HttpPost("start/{streamId}")]
        public IActionResult StartStream(string streamId)
        {
            // Validate streamId
            if (string.IsNullOrWhiteSpace(streamId) || streamId.Length > 50)
            {
                return BadRequest(new { error = "Invalid stream ID. Must be 1-50 characters." });
            }

            // Check if stream already exists
            if (ActiveStreams.ContainsKey(streamId))
            {
                return Conflict(new { error = "Stream already active", streamId });
            }

            try
            {
                // Create buffer for this stream (max 100 chunks in memory)
                var buffer = new BlockingCollection<byte[]>(boundedCapacity: 100);

                if (!ActiveStreams.TryAdd(streamId, buffer))
                {
                    return StatusCode(500, new { error = "Failed to initialize stream" });
                }

                // Store metadata
                _streamMetadata[streamId] = new StreamMetadata
                {
                    StreamId = streamId,
                    StartTime = DateTime.UtcNow,
                    Status = "active"
                };

                _logger.LogInformation($"Stream started: {streamId}");

                return Ok(new
                {
                    message = "Stream ingestion started",
                    streamId,
                    startTime = _streamMetadata[streamId].StartTime
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error starting stream {streamId}");
                return StatusCode(500, new { error = "Internal server error" });
            }
        }

        [HttpPost("upload/{streamId}")]
        [RequestSizeLimit(10_000_000)] // 10MB max per chunk
        public async Task<IActionResult> UploadChunk(string streamId)
        {
            // Validate stream exists
            if (!ActiveStreams.TryGetValue(streamId, out var buffer))
            {
                return NotFound(new { error = "Stream not active", streamId });
            }

            // Check if buffer is full
            if (buffer.Count >= 90) // 90% of capacity
            {
                _logger.LogWarning($"Buffer near capacity for stream {streamId}");
                return StatusCode(429, new { error = "Buffer full, slow down upload rate" });
            }

            try
            {
                using var ms = new MemoryStream();
                await Request.Body.CopyToAsync(ms);
                var data = ms.ToArray();

                if (data.Length == 0)
                {
                    return BadRequest(new { error = "Empty chunk received" });
                }

                if (data.Length > 5_000_000) // 5MB safety check
                {
                    _logger.LogWarning($"Large chunk received: {data.Length} bytes for stream {streamId}");
                }

                // Add to buffer (will block if full)
                if (!buffer.TryAdd(data, TimeSpan.FromSeconds(5)))
                {
                    return StatusCode(503, new { error = "Unable to process chunk, server busy" });
                }

                // Update metadata
                if (_streamMetadata.TryGetValue(streamId, out var metadata))
                {
                    metadata.TotalBytesReceived += data.Length;
                    metadata.ChunksReceived++;
                    metadata.LastChunkTime = DateTime.UtcNow;
                }

                return Ok(new { received = data.Length });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error uploading chunk for stream {streamId}");
                return StatusCode(500, new { error = "Failed to process chunk" });
            }
        }

        [HttpPost("stop/{streamId}")]
        public IActionResult StopStream(string streamId)
        {
            if (!ActiveStreams.TryGetValue(streamId, out var buffer))
            {
                return NotFound(new { error = "Stream not found", streamId });
            }

            try
            {
                // Signal that no more data is coming
                buffer.CompleteAdding();

                // Update metadata
                if (_streamMetadata.TryGetValue(streamId, out var metadata))
                {
                    metadata.EndTime = DateTime.UtcNow;
                    metadata.Status = "stopped";
                    metadata.Duration = metadata.EndTime.Value - metadata.StartTime;
                }

                _logger.LogInformation($"Stream stopped: {streamId}");

                return Ok(new
                {
                    message = "Stream stopped",
                    streamId,
                    metadata = _streamMetadata.GetValueOrDefault(streamId)
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error stopping stream {streamId}");
                return StatusCode(500, new { error = "Failed to stop stream" });
            }
        }

        [HttpGet("status/{streamId}")]
        public IActionResult GetStreamStatus(string streamId)
        {
            if (!_streamMetadata.TryGetValue(streamId, out var metadata))
            {
                return NotFound(new { error = "Stream not found", streamId });
            }

            var isActive = ActiveStreams.ContainsKey(streamId);

            return Ok(new
            {
                streamId,
                status = isActive ? "active" : "inactive",
                metadata
            });
        }

        [HttpGet("active")]
        public IActionResult GetActiveStreams()
        {
            var activeStreams = _streamMetadata
                .Where(m => m.Value.Status == "active")
                .Select(m => new
                {
                    m.Key,
                    m.Value.StartTime,
                    duration = DateTime.UtcNow - m.Value.StartTime,
                    m.Value.ChunksReceived,
                    m.Value.TotalBytesReceived
                })
                .ToList();

            return Ok(new { count = activeStreams.Count, streams = activeStreams });
        }

    }
}
