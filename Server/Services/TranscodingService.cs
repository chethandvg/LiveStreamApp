using Server.Controllers;
using Server.Shared;
using System.Collections.Concurrent;

namespace Server.Services
{
    public class TranscodingService : BackgroundService
    {
        private readonly ILogger<TranscodingService> _logger;
        private readonly IConfiguration _configuration;
        private readonly ConcurrentDictionary<string, StreamProcessor> _activeStreams = new();

        public TranscodingService(ILogger<TranscodingService> logger, IConfiguration configuration)
        {
            _logger = logger;
            _configuration = configuration;
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            _logger.LogInformation("TranscodingService started");

            while (!stoppingToken.IsCancellationRequested)
            {
                // Monitor for new streams from StreamIngestController
                foreach (var kvp in StreamIngestController.ActiveStreams)
                {
                    var streamId = kvp.Key;
                    var buffer = kvp.Value;

                    if (!_activeStreams.ContainsKey(streamId))
                    {
                        _logger.LogInformation($"Starting transcoding for stream: {streamId}");
                        var processor = new StreamProcessor(streamId, buffer, _configuration, _logger);
                        _activeStreams[streamId] = processor;

                        // Start processing in background
                        _ = Task.Run(() => processor.ProcessStreamAsync(stoppingToken), stoppingToken);
                    }
                }

                // Clean up completed streams
                var completedStreams = _activeStreams.Where(s => s.Value.IsCompleted).ToList();
                foreach (var stream in completedStreams)
                {
                    _activeStreams.TryRemove(stream.Key, out _);
                    StreamIngestController.ActiveStreams.TryRemove(stream.Key, out _);
                    _logger.LogInformation($"Cleaned up stream: {stream.Key}");
                }

                await Task.Delay(1000, stoppingToken);
            }
        }
    }
}
