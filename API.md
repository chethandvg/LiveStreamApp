# ?? API Documentation

## Accessing Interactive API Documentation

The LiveStream App uses **Scalar** for modern, interactive API documentation.

### Development Environment

When running in **Development** mode, access the interactive API docs at:

```
https://localhost:7119/scalar/v1
```

### Features

? **Interactive Testing** - Test endpoints directly in browser  
?? **Modern UI** - Purple theme with clean design  
?? **Code Samples** - C# HttpClient examples  
?? **Search** - Press `Ctrl+K` for quick search  
?? **Download Spec** - Export OpenAPI specification  
??? **Sidebar Navigation** - Easy endpoint browsing  

---

## API Endpoints

### Stream Management

#### Start Stream
```http
POST /api/StreamIngest/start/{streamId}
Content-Type: application/json

{
  "title": "My Live Stream",
  "description": "Optional description"
}
```

**Response:**
```json
{
  "streamId": "stream_12345",
  "status": "started",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

#### Upload Video Chunk
```http
POST /api/StreamIngest/upload/{streamId}
Content-Type: video/webm

[binary video data]
```

**Response:**
```json
{
  "success": true,
  "chunkNumber": 150,
  "bytesReceived": 65536
}
```

#### Stop Stream
```http
POST /api/StreamIngest/stop/{streamId}
```

**Response:**
```json
{
  "streamId": "stream_12345",
  "status": "stopped",
  "duration": 3600
}
```

#### Get Stream Status
```http
GET /api/StreamIngest/status/{streamId}
```

**Response:**
```json
{
  "streamId": "stream_12345",
  "status": "active",
  "metadata": {
    "chunksReceived": 202,
    "totalBytesReceived": 39347252,
    "duration": 120,
    "startTime": "2024-01-15T10:30:00Z"
  }
}
```

#### Get Active Streams
```http
GET /api/StreamIngest/active
```

**Response:**
```json
{
  "activeStreams": [
    {
      "streamId": "stream_12345",
      "title": "My Stream",
      "startTime": "2024-01-15T10:30:00Z",
      "viewers": 25
    }
  ],
  "count": 1
}
```

### Diagnostics

#### Health Check
```http
GET /health
```

**Response:**
```json
{
  "status": "Healthy",
  "checks": {
    "azureStorage": "Healthy",
    "signalR": "Healthy"
  }
}
```

#### Stream Diagnostics
```http
GET /api/StreamIngest/diagnose/{streamId}
```

**Response:**
```json
{
  "streamId": "stream_12345",
  "status": "active",
  "diagnostics": {
    "ffmpegRunning": true,
    "manifestExists": true,
    "segmentCount": 45,
    "lastSegmentTime": "2024-01-15T10:32:00Z",
    "storageConnected": true,
    "cdnAccessible": true
  },
  "issues": []
}
```

---

## OpenAPI Specification

Download the complete OpenAPI specification:

```
GET /openapi/v1.json
```

---

## Configuration

The Scalar API documentation is configured in `Server/Program.cs`:

```csharp
app.MapScalarApiReference(options =>
{
    options
        .WithTitle("Live Stream API Documentation")
        .WithTheme(ScalarTheme.Purple)
        .WithDefaultHttpClient(ScalarTarget.CSharp, ScalarClient.HttpClient)
        .WithSidebar(true)
        .WithModels(true)
        .WithDownloadButton(true)
        .WithSearchHotKey("k");
});
```

### Customization Options

**Available Themes:**
- `Purple` (default)
- `Blue`
- `Green`
- `Orange`
- `Moon`
- `Mars`
- `Default`

**HTTP Client Languages:**
- `CSharp`
- `JavaScript`
- `Python`
- `Go`
- `PHP`
- `Ruby`
- `Java`

---

## Production Deployment

By default, API documentation is **only enabled in Development** mode.

To enable in production:

```csharp
// Enable for all environments (use with caution)
app.MapOpenApi();
app.MapScalarApiReference();
```

?? **Security Considerations:**
- Add authentication/authorization
- Restrict access to internal networks
- Use API keys
- Configure CORS appropriately

---

## Example Usage

### C# HttpClient

```csharp
using var client = new HttpClient();
client.BaseAddress = new Uri("https://localhost:7119");

// Start stream
var startResponse = await client.PostAsJsonAsync(
    "/api/StreamIngest/start/stream_12345",
    new { title = "My Stream" });

// Upload chunk
var videoData = File.ReadAllBytes("chunk.webm");
var content = new ByteArrayContent(videoData);
content.Headers.ContentType = new MediaTypeHeaderValue("video/webm");

var uploadResponse = await client.PostAsync(
    "/api/StreamIngest/upload/stream_12345",
    content);

// Get status
var statusResponse = await client.GetAsync(
    "/api/StreamIngest/status/stream_12345");
var status = await statusResponse.Content.ReadFromJsonAsync<StreamStatus>();
```

### JavaScript Fetch

```javascript
// Start stream
const startResponse = await fetch(
  '/api/StreamIngest/start/stream_12345',
  {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title: 'My Stream' })
  }
);

// Upload chunk
const uploadResponse = await fetch(
  '/api/StreamIngest/upload/stream_12345',
  {
    method: 'POST',
    headers: { 'Content-Type': 'video/webm' },
    body: videoBlob
  }
);

// Get status
const statusResponse = await fetch(
  '/api/StreamIngest/status/stream_12345'
);
const status = await statusResponse.json();
```

---

## Rate Limiting

| Endpoint | Rate Limit |
|----------|------------|
| Upload | No limit (streaming) |
| Status | 100 requests/minute |
| Diagnostics | 60 requests/minute |
| Start/Stop | 10 requests/minute |

---

## Error Codes

| Status Code | Description |
|-------------|-------------|
| 200 | Success |
| 400 | Bad Request - Invalid stream ID or data |
| 404 | Stream not found |
| 409 | Conflict - Stream already started |
| 500 | Internal Server Error |
| 503 | Service Unavailable - Azure Storage issue |

---

## Additional Resources

- **Scalar Documentation:** https://github.com/scalar/scalar
- **ASP.NET Core OpenAPI:** https://learn.microsoft.com/aspnet/core/fundamentals/openapi
- **Complete Documentation:** [DOCS.md](DOCS.md)

---

**Version:** 2.0  
**Last Updated:** 2024-01-15
