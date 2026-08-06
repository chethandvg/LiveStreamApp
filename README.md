# 🎥 LiveStream App

Production-ready live video streaming application built with .NET 9, Blazor WebAssembly, Azure Storage, Azure Front Door, and SignalR.

## ✨ Features

- **Live Video Streaming** - Browser-based broadcasting to thousands of viewers
- **HLS (HTTP Live Streaming)** - Scalable adaptive bitrate streaming
- **Real-time Chat** - SignalR-powered live chat
- **Azure CDN** - Global content delivery with Azure Front Door
- **Mobile Support** - Works on iOS and Android
- **Custom FFmpeg Pipeline** - No external streaming services required

## 🚀 Quick Start

### Prerequisites
- [.NET 9.0 SDK](https://dotnet.microsoft.com/download/dotnet/9.0)
- [FFmpeg](https://ffmpeg.org/download.html) (must be in PATH)
- [Azure Account](https://azure.microsoft.com/free/)

### Run in 3 Steps

```powershell
# 1. Clone and configure
git clone https://github.com/chethandvg/LiveStreamApp
cd LiveStreamApp

# 2. Add Azure Storage connection string to Server/appsettings.json
{
  "AzureStorage": {
    "ConnectionString": "YOUR_STORAGE_CONNECTION_STRING",
    "ContainerName": "livestreams"
  }
}

# 3. Run
cd Server
dotnet run

# Open: https://localhost:7119/broadcast
```

## 📁 Project Structure

```
LiveStreamApp/
├── Client/                    # Blazor WebAssembly UI
│   ├── Pages/
│   │   ├── Broadcaster.razor # Broadcasting interface
│   │   └── Viewer.razor      # Viewing interface
│   └── wwwroot/js/stream.js  # MediaRecorder + HLS.js
│
├── Server/                    # ASP.NET Core backend
│   ├── Controllers/
│   │   └── StreamIngestController.cs
│   ├── Services/
│   │   └── TranscodingService.cs # FFmpeg background
│   └── Hubs/
│       └── ChatHub.cs        # SignalR chat
│
└── *.ps1                      # PowerShell automation scripts
```

## 🛠️ PowerShell Scripts

```powershell
# Diagnose streaming issues
.\diagnose-stream.ps1

# Diagnose specific stream
.\diagnose-stream.ps1 -StreamId "stream_xxxxx"

# Configure Azure Storage CORS
.\configure-cors.ps1

# Verify environment
.\azure-deployment.ps1 -Action Check

# Configure Azure Storage CORS (legacy)
.\azure-deployment.ps1 -Action Configure

# Setup Azure Front Door (CDN)
.\azure-deployment.ps1 -Action Setup

# Deploy to Azure
.\azure-deployment.ps1 -Action Deploy

# Diagnose stream issues (legacy)
.\azure-deployment.ps1 -Action Diagnose -StreamId "stream_xxxxx"
```

## 🐛 Common Issues

| Issue | Quick Fix |
|-------|----------|
| **CORS Error: Invalid value '\*\*'** | `.\configure-cors.ps1 -FixFrontDoor` then purge Front Door cache |
| Stream 404 Error | Wait 15 seconds (auto-retries) |
| CORS Error | `.\configure-cors.ps1` |
| HLS Buffer Stalled | Run `.\diagnose-stream.ps1 -StreamId "your_stream_id"` |
| SignalR Not Working | `.\verify-signalr-setup.ps1 -FixAppsettings` |
| FFmpeg Not Found | `choco install ffmpeg` or see [FFmpeg downloads](https://ffmpeg.org/download.html) |
| Stream Not Playing | Run `.\diagnose-stream.ps1` for detailed diagnostics |

## 📚 Documentation

📖 **[Complete Documentation](DOCS.md)** - Comprehensive guide covering:
- Configuration & Setup
- PowerShell Scripts Reference
- Troubleshooting Guide
- Deployment Instructions
- API Documentation
- Monitoring & Maintenance

## 🏗️ Architecture

```
Browser (Broadcaster)
    ↓ MediaRecorder API → WebM chunks
Server (StreamIngestController)
    ↓ In-memory buffer
TranscodingService (Background)
    ↓ FFmpeg → HLS conversion
Azure Blob Storage
    ↓ .m3u8 + .ts files
Azure Front Door (CDN)
    ↓ Global distribution
Browser (Viewers) - HLS.js player
```

## 💰 Cost Estimation

| Service | Tier | Monthly Cost |
|---------|------|--------------|
| Azure Storage | Standard LRS | ~$2-5 |
| Azure Front Door | Standard | ~$10-30 |
| Azure SignalR | Free | $0 (up to 20 connections) |
| **Development Total** | | **~$12-35/month** |
| **Production (100+ viewers)** | | **~$200-300/month** |

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## 📝 License

MIT License - See [LICENSE](LICENSE) for details.

## 🆘 Support

- **📖 Documentation:** [DOCS.md](DOCS.md)
- **🐛 Issues:** https://github.com/chethandvg/LiveStreamApp/issues

---

**Version:** 2.0  
**Last Updated:** 2024-01-15