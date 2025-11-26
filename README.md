# 🎥 LiveStream App - Complete Setup Guide

A production-ready live video streaming application built with .NET 8, Blazor WebAssembly, Azure Storage, Azure CDN, and SignalR.

## 📋 Table of Contents
- [Features](#features)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start (5 Minutes)](#quick-start-5-minutes)
- [Detailed Setup](#detailed-setup)
- [File Structure](#file-structure)
- [Configuration](#configuration)
- [Deployment](#deployment)
- [Troubleshooting](#troubleshooting)

---

## ✨ Features

- ✅ **Live Video Streaming** - Browser-based broadcasting to thousands of viewers
- ✅ **HLS (HTTP Live Streaming)** - Scalable adaptive bitrate streaming
- ✅ **Real-time Chat** - SignalR-powered live chat for broadcaster-viewer interaction
- ✅ **Azure CDN** - Global content delivery for low-latency streaming
- ✅ **Mobile Support** - Works on iOS and Android browsers
- ✅ **No External Streaming Engine** - Custom-built solution with FFmpeg
- ✅ **Broadcast Management** - Start/stop streams with metadata tracking
- ✅ **Viewer Analytics** - Real-time viewer count and stream statistics

---

## 🏗️ Architecture

```
Browser (Broadcaster) 
    ↓ (MediaRecorder API - WebM chunks)
.NET Server (StreamIngestController)
    ↓ (Binary chunks to buffer)
TranscodingService (FFmpeg)
    ↓ (Converts to HLS: .m3u8 + .ts files)
Azure Blob Storage
    ↓ (Files uploaded)
Azure CDN
    ↓ (Global distribution)
Browser (Viewers) - HLS.js player
```

**Chat:** SignalR Hub → Real-time messaging separate from video stream

---

## 📦 Prerequisites

### Required Software
- [.NET 8.0 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) or later
- [FFmpeg](https://ffmpeg.org/download.html) (must be in PATH)
- [Visual Studio 2022](https://visualstudio.microsoft.com/) or [VS Code](https://code.visualstudio.com/)
- [Azure Account](https://azure.microsoft.com/free/) (free tier available)

### Azure Resources Needed
1. **Azure Storage Account** ($0.02/GB/month)
2. **Azure CDN** ($0.081/GB)
3. **Azure SignalR Service** (Free tier: 20 connections)

### Verify FFmpeg Installation
```bash
ffmpeg -version
```
If not found, [install FFmpeg](https://ffmpeg.org/download.html) and add to PATH.

---

## 🚀 Quick Start (5 Minutes)

### Step 1: Create Solution Structure

**Windows (PowerShell):**
```powershell
# Run the setup script from artifacts
# This creates the complete project structure
```

**Mac/Linux (Bash):**
```bash
# Create solution
dotnet new sln -n LiveStreamApp

# Create projects
dotnet new webapi -n LiveStreamApp.Server
dotnet new blazorwasm -n LiveStreamApp.Client

# Add to solution
dotnet sln add LiveStreamApp.Server/LiveStreamApp.Server.csproj
dotnet sln add LiveStreamApp.Client/LiveStreamApp.Client.csproj

# Add reference
dotnet add LiveStreamApp.Server/LiveStreamApp.Server.csproj reference LiveStreamApp.Client/LiveStreamApp.Client.csproj

# Install packages
cd LiveStreamApp.Server
dotnet add package Azure.Storage.Blobs --version 12.19.1
dotnet add package Microsoft.Azure.SignalR --version 1.22.0
dotnet add package Microsoft.AspNetCore.SignalR.Client --version 8.0.0
dotnet add package Microsoft.AspNetCore.ResponseCompression --version 2.2.0
dotnet add package Microsoft.AspNetCore.Components.WebAssembly.Server --version 8.0.0

cd ../LiveStreamApp.Client
dotnet add package Microsoft.AspNetCore.SignalR.Client --version 8.0.0
```

### Step 2: Copy Files from Artifacts

Copy all the code files from the artifacts into your project:

**Server Files:**
```
LiveStreamApp.Server/
├── Controllers/
│   └── StreamIngestController.cs
├── Services/
│   └── TranscodingService.cs
├── Hubs/
│   └── ChatHub.cs
├── Program.cs
└── appsettings.json
```

**Client Files:**
```
LiveStreamApp.Client/
├── Pages/
│   ├── Home.razor
│   ├── Broadcaster.razor
│   └── Viewer.razor
├── Shared/
│   ├── MainLayout.razor
│   └── NavMenu.razor
├── wwwroot/
│   ├── index.html
│   ├── css/
│   │   └── app.css
│   └── js/
│       └── stream.js
├── App.razor
├── _Imports.razor
└── Program.cs
```

### Step 3: Configure Azure (15 minutes)

#### 3.1 Create Azure Storage Account
```bash
# Using Azure CLI (or use Azure Portal)
az login

az storage account create \
  --name livestreamstorage123 \
  --resource-group MyResourceGroup \
  --location eastus \
  --sku Standard_LRS

# Create container
az storage container create \
  --name livestreams \
  --account-name livestreamstorage123 \
  --public-access blob

# Get connection string
az storage account show-connection-string \
  --name livestreamstorage123 \
  --resource-group MyResourceGroup
```

#### 3.2 Create Azure CDN
```bash
# Create CDN profile
az cdn profile create \
  --name livestream-cdn \
  --resource-group MyResourceGroup \
  --sku Standard_Microsoft

# Create CDN endpoint
az cdn endpoint create \
  --name mystream-cdn \
  --profile-name livestream-cdn \
  --resource-group MyResourceGroup \
  --origin livestreamstorage123.blob.core.windows.net \
  --origin-path /livestreams
```

Your CDN URL will be: `https://mystream-cdn.azureedge.net`

#### 3.3 Create Azure SignalR Service
```bash
az signalr create \
  --name livestream-signalr \
  --resource-group MyResourceGroup \
  --sku Free_F1
  
# Get connection string
az signalr key list \
  --name livestream-signalr \
  --resource-group MyResourceGroup
```

### Step 4: Update Configuration

Edit `LiveStreamApp.Server/appsettings.json`:

```json
{
  "AzureStorage": {
    "ConnectionString": "YOUR_STORAGE_CONNECTION_STRING_HERE",
    "ContainerName": "livestreams"
  },
  "Azure": {
    "SignalR": {
      "ConnectionString": "YOUR_SIGNALR_CONNECTION_STRING_HERE"
    },
    "CDN": {
      "BaseUrl": "https://mystream-cdn.azureedge.net/livestreams"
    }
  }
}
```

**🔒 Security Note:** For production, use [Azure Key Vault](https://docs.microsoft.com/azure/key-vault/) or User Secrets:

```bash
cd LiveStreamApp.Server
dotnet user-secrets init
dotnet user-secrets set "AzureStorage:ConnectionString" "YOUR_CONNECTION_STRING"
dotnet user-secrets set "Azure:SignalR:ConnectionString" "YOUR_SIGNALR_CONNECTION"
```

### Step 5: Run Locally

```bash
# Navigate to server project
cd LiveStreamApp.Server

# Run the application
dotnet run
```

Open browser:
- **Broadcaster:** https://localhost:7001/broadcast
- **Viewer:** https://localhost:7001/watch/[stream-id]

---

## 📁 File Structure

```
LiveStreamApp/
├── LiveStreamApp.sln
├── Dockerfile
├── docker-compose.yml
├── README.md
│
├── LiveStreamApp.Server/
│   ├── Controllers/
│   │   └── StreamIngestController.cs      # Receives video chunks from broadcaster
│   ├── Services/
│   │   └── TranscodingService.cs          # FFmpeg transcoding + Azure upload
│   ├── Hubs/
│   │   └── ChatHub.cs                     # SignalR real-time chat
│   ├── Program.cs                         # Server configuration
│   ├── appsettings.json                   # Configuration (secrets go here)
│   └── LiveStreamApp.Server.csproj
│
└── LiveStreamApp.Client/
    ├── Pages/
    │   ├── Home.razor                     # Landing page with active streams
    │   ├── Broadcaster.razor              # Broadcasting interface
    │   └── Viewer.razor                   # Stream viewing interface
    ├── Shared/
    │   ├── MainLayout.razor               # App layout
    │   └── NavMenu.razor                  # Navigation menu
    ├── wwwroot/
    │   ├── index.html                     # HTML entry point
    │   ├── css/
    │   │   └── app.css                    # Custom styles
    │   └── js/
    │       └── stream.js                  # MediaRecorder + HLS.js logic
    ├── App.razor                          # Root component
    ├── _Imports.razor                     # Global using statements
    ├── Program.cs                         # Client startup
    └── LiveStreamApp.Client.csproj
```

---

## ⚙️ Configuration Details

### appsettings.json Explained

```json
{
  "AzureStorage": {
    "ConnectionString": "...",           // Azure Storage connection string
    "ContainerName": "livestreams"       // Container where .ts/.m3u8 files are stored
  },
  "Azure": {
    "SignalR": {
      "ConnectionString": "..."          // SignalR connection string
    },
    "CDN": {
      "BaseUrl": "https://[cdn-name].azureedge.net/livestreams"  // CDN endpoint
    }
  },
  "Streaming": {
    "MaxConcurrentStreams": 10,          // Limit simultaneous broadcasts
    "MaxStreamDurationMinutes": 240,     // 4 hours max per stream
    "ChunkSizeKB": 512,                  // WebM chunk size from browser
    "SegmentDurationSeconds": 2          // HLS segment duration
  }
}
```

### FFmpeg Settings (TranscodingService.cs)

Current settings optimize for:
- **Video:** H.264, 30fps, 1280x720
- **Audio:** AAC, 128kbps
- **Latency:** 15-30 seconds
- **Segment:** 2-second chunks

To adjust quality, edit `TranscodingService.cs`:

```csharp
arguments.Append("-c:v libx264 ");           // Video codec
arguments.Append("-preset ultrafast ");      // Encoding speed (faster = lower quality)
arguments.Append("-b:v 2500k ");             // Video bitrate (higher = better quality)
arguments.Append("-r 30 ");                  // Frame rate
arguments.Append("-hls_time 2 ");            // Segment duration (lower = less latency)
```

---

## 🚢 Deployment

### Option 1: Docker (Recommended)

**Create Dockerfile** (already provided in artifacts):

```bash
# Build image
docker build -t livestream-app:latest .

# Run locally with Docker
docker run -p 8080:80 -p 8081:443 \
  -e AzureStorage__ConnectionString="YOUR_CONNECTION_STRING" \
  -e Azure__SignalR__ConnectionString="YOUR_SIGNALR_CONNECTION" \
  livestream-app:latest
```

### Option 2: Azure Container Instances

```bash
# Create Azure Container Registry
az acr create --name myregistry --resource-group MyResourceGroup --sku Basic

# Build and push
az acr build --registry myregistry --image livestream-app:latest .

# Deploy to Azure Container Instances
az container create \
  --name livestream-container \
  --resource-group MyResourceGroup \
  --image myregistry.azurecr.io/livestream-app:latest \
  --cpu 2 --memory 4 \
  --dns-name-label my-livestream-app \
  --ports 80 443 \
  --environment-variables \
    AzureStorage__ConnectionString="YOUR_CONNECTION" \
    Azure__SignalR__ConnectionString="YOUR_SIGNALR_CONNECTION"
```

### Option 3: Azure App Service

```bash
# Create App Service Plan (Linux)
az appservice plan create \
  --name livestream-plan \
  --resource-group MyResourceGroup \
  --is-linux --sku B2

# Create Web App
az webapp create \
  --name my-livestream-app \
  --resource-group MyResourceGroup \
  --plan livestream-plan \
  --deployment-container-image-name myregistry.azurecr.io/livestream-app:latest

# Configure app settings
az webapp config appsettings set \
  --name my-livestream-app \
  --resource-group MyResourceGroup \
  --settings \
    AzureStorage__ConnectionString="YOUR_CONNECTION" \
    Azure__SignalR__ConnectionString="YOUR_SIGNALR_CONNECTION"
```

---

## 🐛 Troubleshooting

### Issue 1: FFmpeg Not Found
```
Error: No such file or directory: ffmpeg
```
**Solution:**
- Windows: Download from https://ffmpeg.org, extract to `C:\ffmpeg`, add `C:\ffmpeg\bin` to PATH
- Mac: `brew install ffmpeg`
- Linux: `sudo apt-get install ffmpeg`
- Verify: `ffmpeg -version`

### Issue 2: Stream Not Playing After 30+ Seconds
**Check:**
1. Are `.m3u8` and `.ts` files being created in Azure Blob Storage?
   - Go to Azure Portal → Storage Account → Containers → livestreams → [stream-id]
2. Is CDN URL correct in `appsettings.json`?
3. Browser console errors? (F12 → Console)
4. Try CDN URL directly: `https://[cdn].azureedge.net/livestreams/[stream-id]/index.m3u8`

### Issue 3: CORS Errors
```
Access to fetch at '...' from origin '...' has been blocked by CORS policy
```
**Solution:** Verify `Program.cs` has CORS configured:
```csharp
app.UseCors("AllowBlazor");  // Must be BEFORE app.UseAuthorization()
```

### Issue 4: SignalR Connection Failed
```
Failed to start the connection
```
**Solutions:**
1. Check SignalR connection string in `appsettings.json`
2. Verify SignalR service is running in Azure Portal
3. Check firewall rules allow WebSocket connections
4. For App Service: Enable **Web Sockets** in Configuration

### Issue 5: High Memory Usage on Server
**Solutions:**
1. Limit concurrent streams in `appsettings.json`: `"MaxConcurrentStreams": 5`
2. Reduce buffer size in `StreamIngestController.cs`: `boundedCapacity: 50`
3. Upgrade App Service plan to higher tier (B2 → S1)

### Issue 6: Video Quality is Poor
**Solutions:**
1. Increase bitrate in `TranscodingService.cs`: `-b:v 5000k` (5 Mbps)
2. Change preset: `-preset faster` (slower encoding = better quality)
3. Check broadcaster's upload speed
4. Ensure camera resolution is 720p or higher

---

## 💰 Cost Estimation

| Service | Tier | Monthly Cost (Light Usage) |
|---------|------|----------------------------|
| Azure Storage | Standard LRS | ~$2-5 |
| Azure CDN | Standard Microsoft | ~$10-30 |
| Azure SignalR | Free | $0 (up to 20 connections) |
| Azure App Service | B2 (2 cores, 3.5GB RAM) | ~$73 |
| **Total** | | **~$85-110/month** |

**Heavy Usage (100+ concurrent viewers):**
- CDN bandwidth: $50-200/month
- SignalR: Upgrade to Standard ($50/month for 1000 connections)
- **Total: ~$200-300/month**

---

## 📊 Testing Checklist

- [ ] Single broadcaster can start stream
- [ ] Video chunks appear in Azure Blob Storage
- [ ] `.m3u8` and `.ts` files are created
- [ ] CDN serves files correctly
- [ ] Viewer can watch stream (wait 20-30 seconds)
- [ ] Multiple viewers can watch simultaneously
- [ ] Chat messages appear in real-time
- [ ] Broadcaster can stop stream cleanly
- [ ] Old segments are deleted from storage
- [ ] Works on mobile (iOS Safari, Chrome Android)
- [ ] Network interruption handled gracefully

---

## 🎓 Next Steps

1. **Add Authentication:** Protect broadcasting with JWT or Azure AD
2. **Stream Recording:** Save broadcasts to Azure Storage for replay
3. **Multiple Quality Levels:** Implement adaptive bitrate streaming
4. **Analytics:** Add Application Insights for monitoring
5. **Moderation:** Add chat moderation and user blocking
6. **Monetization:** Integrate payment processing for premium streams

---

## 📚 Resources

- [FFmpeg Documentation](https://ffmpeg.org/documentation.html)
- [HLS.js GitHub](https://github.com/video-dev/hls.js/)
- [Azure CDN Best Practices](https://docs.microsoft.com/azure/cdn/cdn-best-practices)
- [SignalR Documentation](https://docs.microsoft.com/aspnet/core/signalr/)
- [Blazor Documentation](https://docs.microsoft.com/aspnet/core/blazor/)

---

## 📝 License

This project is provided as-is for educational purposes.

---

## 🆘 Support

Having issues? Check:
1. Azure Portal logs (App Service → Log stream)
2. Browser console (F12 → Console)
3. Server logs (`dotnet run` output)
4. Azure Storage Explorer (verify files are uploaded)

**Common Issues:**
- Wait 20-30 seconds for stream to start (HLS latency is normal)
- Ensure FFmpeg is in PATH
- Verify all Azure connection strings are correct
- Check blob container has public access enabled

---

## 🎉 You're Ready!

Your live streaming application is now set up and ready to use. Start broadcasting and enjoy! 🚀

For questions or issues, review the troubleshooting section above.