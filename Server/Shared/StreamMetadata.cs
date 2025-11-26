namespace Server.Shared
{
    public class StreamMetadata
    {
        public string StreamId { get; set; } = string.Empty;
        public DateTime StartTime { get; set; }
        public DateTime? EndTime { get; set; }
        public DateTime? LastChunkTime { get; set; }
        public string Status { get; set; } = "inactive";
        public long TotalBytesReceived { get; set; }
        public int ChunksReceived { get; set; }
        public TimeSpan? Duration { get; set; }
    }

}
