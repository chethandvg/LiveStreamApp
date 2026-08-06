# ?? LiveStream App - Complete Documentation

> **Version 2.0** | Last Updated: 2024-01-15

---

## ?? Table of Contents

1. [Quick Start](#-quick-start)
2. [Project Overview](#-project-overview)
3. [Configuration](#-configuration)
4. [PowerShell Scripts](#-powershell-scripts)
5. [Troubleshooting](#-troubleshooting)
6. [Deployment](#-deployment)
7. [API Documentation](#-api-documentation)

---

## ?? Quick Start

### Prerequisites
- [.NET 9.0 SDK](https://dotnet.microsoft.com/download/dotnet/9.0)
- [FFmpeg](https://ffmpeg.org/download.html) (must be in PATH)
- [Azure Account](https://azure.microsoft.com/free/)

### Setup in 5 Minutes

```powershell
# 1. Clone repository
git clone https://github.com/chethandvg/LiveStreamApp
cd LiveStreamApp

# 2. Verify environment
dotnet --version  # Should be 9.0+
ffmpeg -version   # Should be installed

# 3. Configure Azure Storage (edit Server/appsettings.json)
{
  "AzureStorage": {
    "ConnectionString": "YOUR_STORAGE_CONNECTION_STRING",
    "ContainerName": "livestreams"
  }
}

# 4. Run application
cd Server
dotnet run

# 5. Start broadcasting
# Open: https://localhost:7119/broadcast
```

### Common First-Time Issues

| Issue | Quick Fix |
|-------|----------|
| **Stream 404 Error** | Wait 15 seconds (auto-retries) |
| **CORS Error** | Run: `az storage cors add --services b --methods GET HEAD OPTIONS --origins "*" --allowed-headers "*"` |
| **SignalR Not Working** | Set `"Azure:SignalR:UseLocal": true` in appsettings.Development.json |
| **FFmpeg Not Found** | `choco install ffmpeg` or `winget install ffmpeg` |

---

## ?? Project Overview

### Features
- ? **Live Video Streaming** - Browser-based broadcasting
- ?? **HLS Streaming** - Adaptive bitrate, scalable to thousands
- ?? **Real-time Chat** - SignalR-powered live chat
- ?? **Global CDN** - Azure Front Door integration
- ?? **Mobile Support** - iOS and Android compatible
- ??? **Custom Pipeline** - FFmpeg-based transcoding

### Architecture

```
Browser ? MediaRecorder API ? Server ? FFmpeg ? HLS ? Azure Storage ? CDN ? Viewers
         ?
    SignalR Hub (Chat)
```

### Project Structure

```
LiveStreamApp/
??? Client/                          # Blazor WebAssembly
?   ??? Pages/
?   ?   ??? Broadcaster.razor       # Broadcasting UI
?   ?   ??? Viewer.razor            # Playback UI
?   ?   ??? StreamDiagnostics.razor # Diagnostics
?   ??? wwwroot/
?       ??? appsettings.json        # Client config
?       ??? js/stream.js            # MediaRecorder + HLS.js
?
??? Server/                          # ASP.NET Core API
?   ??? Controllers/
?   ?   ??? StreamIngestController.cs
?   ??? Services/
?   ?   ??? TranscodingService.cs   # FFmpeg background service
?   ??? Hubs/
?   ?   ??? ChatHub.cs              # SignalR
?   ??? appsettings.json            # Server config
?
??? *.ps1                            # PowerShell scripts
```

---

## ?? Configuration

### Server Configuration (`Server/appsettings.json`)

```json
{
  "AzureStorage": {
    "ConnectionString": "DefaultEndpointsProtocol=https;AccountName=...;AccountKey=...;",
    "ContainerName": "livestreams"
  },
  "Azure": {
    "CDN": {
      "BaseUrl": "https://your-frontdoor.azurefd.net/livestreams"
    },
    "SignalR": {
      "ConnectionString": "Endpoint=https://your-signalr.service.signalr.net;AccessKey=...;",
      "UseLocal": false
    }
  },
  "AllowedOrigins": {
    "AppService": "https://your-app.azurewebsites.net",
    "CDN": "https://your-frontdoor.azurefd.net",
    "Custom": "https://yourdomain.com"
  }
}
```

### Client Configuration (`Client/wwwroot/appsettings.json`)

```json
{
  "Azure": {
    "CDN": {
      "BaseUrl": "https://your-frontdoor.azurefd.net/livestreams"
    }
  }
}
```

### Development vs Production

**Development:**
```json
{
  "Azure": {
    "SignalR": {
      "UseLocal": true  // No Azure SignalR needed
    }
  }
}
```

**Production:**
```json
{
  "Azure": {
    "SignalR": {
      "ConnectionString": "Endpoint=...",
      "UseLocal": false
    }
  }
}
```

### Security Best Practices

**Use User Secrets (Development):**
```powershell
cd Server
dotnet user-secrets set "AzureStorage:ConnectionString" "YOUR_VALUE"
dotnet user-secrets set "Azure:SignalR:ConnectionString" "YOUR_VALUE"
```

**Use Azure Key Vault (Production):**
```csharp
builder.Configuration.AddAzureKeyVault(
    new Uri($"https://{keyVaultName}.vault.azure.net/"),
    new DefaultAzureCredential());
```

---

## ?? PowerShell Scripts

### Overview

| Script | Purpose | Time |
|--------|---------|------|
| `azure-deployment.ps1` | All-in-one Azure operations | 5-10 min |
| `test-signalr-connection.ps1` | Quick SignalR test | 30 sec |
| `verify-signalr-setup.ps1` | Comprehensive SignalR diagnostics | 1-2 min |
| `verify-frontdoor-setup.ps1` | Front Door verification | 1-2 min |

### azure-deployment.ps1 (Main Script)

**Actions:**
```powershell
# Check local environment
.\azure-deployment.ps1 -Action Check

# Configure Azure Storage CORS
.\azure-deployment.ps1 -Action Configure

# Setup Azure Front Door (CDN)
.\azure-deployment.ps1 -Action Setup

# Deploy to Azure Container Registry
.\azure-deployment.ps1 -Action Deploy

# Diagnose stream issues
.\azure-deployment.ps1 -Action Diagnose -StreamId "stream_xxxxx"
```

**Parameters:**
- `-ResourceGroupName` (default: "Trial")
- `-StorageAccountName` (default: "livestreamtrial")
- `-FrontDoorProfileName` (default: "livestream-cdn")
- `-Location` (default: "germanywestcentral")
- `-AcrName` (default: "livestreamacr")
- `-AppName` (default: "livestream-app")

### SignalR Scripts

**Quick Test:**
```powershell
.\test-signalr-connection.ps1
```

**Comprehensive Verification:**
```powershell
# Basic check
.\verify-signalr-setup.ps1

# With Azure resource details
.\verify-signalr-setup.ps1 -ResourceGroup "Trial" -SignalRName "livestream-signalr"

# Fix for development (use local SignalR)
.\verify-signalr-setup.ps1 -FixAppsettings
```

### Front Door Verification

```powershell
# Verify Front Door setup
.\verify-frontdoor-setup.ps1

# With custom names
.\verify-frontdoor-setup.ps1 -FrontDoorProfileName "my-cdn" -StorageAccountName "mystorage"
```

### Common Workflows

**Initial Setup:**
```powershell
.\azure-deployment.ps1 -Action Check
.\azure-deployment.ps1 -Action Configure
.\azure-deployment.ps1 -Action Setup
.\verify-frontdoor-setup.ps1
.\test-signalr-connection.ps1
```

**Troubleshooting:**
```powershell
.\azure-deployment.ps1 -Action Diagnose -StreamId "stream_xxxxx"
.\verify-frontdoor-setup.ps1
.\verify-signalr-setup.ps1
```

---

## ?? Troubleshooting

### Stream 404 Errors

**Symptom:** `404 Not Found` for `index.m3u8` file

**Quick Fix:** Wait 15 seconds - page auto-retries

**Diagnostic:**
```powershell
.\azure-deployment.ps1 -Action Diagnose -StreamId "stream_xxxxx"
```

**Root Causes:**
1. Viewer joined before broadcaster started
2. FFmpeg hasn't created manifest yet (5-10 seconds)
3. Manifest upload failed

**Timeline:**
```
0s:  Start broadcast
2s:  FFmpeg starts
7s:  Manifest created
9s:  Manifest uploaded
12s: Playback available
```

### CORS Issues

**Symptom:** `Access to fetch has been blocked by CORS policy`

**Quick Fix:**
```powershell
.\azure-deployment.ps1 -Action Configure
```

**Manual Configuration:**
```powershell
# Azure Storage CORS
az storage cors add \
  --services b \
  --methods GET HEAD OPTIONS \
  --origins "*" \
  --allowed-headers "*" \
  --exposed-headers "*" \
  --max-age 3600 \
  --account-name <storage-account-name>
```

### SignalR Connection Problems

**Symptom:** `502 Bad Gateway` or `Failed to complete negotiation`

**Quick Fixes:**

1. **Use Local SignalR (Development):**
   ```powershell
   .\verify-signalr-setup.ps1 -FixAppsettings
   ```

2. **Test Connection:**
   ```powershell
   .\test-signalr-connection.ps1
   ```

3. **Verify Azure SignalR:**
   ```powershell
   .\verify-signalr-setup.ps1 -ResourceGroup "Trial" -SignalRName "livestream-signalr"
   ```

**Common Causes:**
- Free tier limit (20 connections)
- WebSockets not enabled
- Invalid connection string
- Network/firewall issues

### FFmpeg Issues

**Symptom:** `No such file or directory: ffmpeg`

**Fix:**
```powershell
# Windows
choco install ffmpeg
# or
winget install ffmpeg

# Verify
ffmpeg -version
```

**Manifest Not Created:**
- Check server logs for FFmpeg errors
- Verify temp directory: `$env:TEMP\livestreams\`
- Check file permissions

### Video Playback Issues

**Poor Quality:**
Edit `Server/Shared/StreamProcessor.cs`:
```csharp
arguments.Append("-b:v 3500000 ");  // Increase bitrate
arguments.Append("-b:a 192k ");     // Increase audio
```

**High Latency:**
Reduce segment duration:
```csharp
arguments.Append("-hls_time 2 ");  // 2-second segments (default: 4)
```

### Diagnostic Endpoints

```
GET /health
GET /api/streamingest/status/{streamId}
GET /api/streamingest/diagnose/{streamId}
GET /api/streamingest/active
```

**Web Diagnostics:**
```
http://localhost:7119/diagnostics/{streamId}
```

---

## ?? Deployment

### Option 1: Azure App Service (Recommended)

**Prerequisites:**
- Azure CLI installed
- Logged in: `az login`
- Docker image built

**Steps:**

1. **Deploy using script:**
   ```powershell
   .\azure-deployment.ps1 -Action Deploy
   ```

2. **Create App Service:**
   ```bash
   az appservice plan create \
     --name livestream-plan \
     --resource-group Trial \
     --is-linux \
     --sku B2

   az webapp create \
     --name livestream-app \
     --resource-group Trial \
     --plan livestream-plan \
     --deployment-container-image-name <acr-name>.azurecr.io/livestreamapp:latest
   ```

3. **Configure App Settings:**
   ```bash
   az webapp config appsettings set \
     --name livestream-app \
     --resource-group Trial \
     --settings \
       ASPNETCORE_ENVIRONMENT=Production \
       WEBSITES_PORT=8080 \
       AzureStorage__ConnectionString='<value>' \
       Azure__SignalR__ConnectionString='<value>'
   ```

4. **Enable WebSockets:**
   ```bash
   az webapp config set \
     --name livestream-app \
     --resource-group Trial \
     --web-sockets-enabled true
   ```

### Option 2: Azure Container Instances

```bash
az container create \
  --resource-group Trial \
  --name livestream-app \
  --image <acr-name>.azurecr.io/livestreamapp:latest \
  --cpu 2 --memory 4 \
  --ports 8080 \
  --environment-variables \
    ASPNETCORE_ENVIRONMENT=Production \
    AzureStorage__ConnectionString='<value>'
```

### Option 3: Docker Compose (Local)

```bash
# Create .env file
cat > .env << EOF
AZURE_STORAGE_CONNECTION_STRING=<value>
AZURE_SIGNALR_CONNECTION_STRING=<value>
AZURE_CDN_BASE_URL=https://your-cdn.azurefd.net/livestreams
EOF

# Run
docker-compose up -d

# Check health
curl http://localhost:8080/health
```

### Post-Deployment Checklist

- [ ] Health endpoint returns 200 OK
- [ ] Stream ingest API accessible
- [ ] SignalR connection works
- [ ] Broadcast page loads
- [ ] Video playback works (wait 15-20 seconds)
- [ ] Chat functionality works
- [ ] Azure Storage receiving files
- [ ] CDN serving content

### Cost Estimation

| Service | Tier | Monthly Cost |
|---------|------|--------------|
| Azure Storage | Standard LRS | $2-5 |
| Azure Front Door | Standard | $10-30 |
| Azure SignalR | Free | $0 (up to 20 connections) |
| App Service | B2 | $73 |
| **Development Total** | | **$85-110/month** |
| **Production (100+ viewers)** | | **$200-300/month** |

---

## ?? API Documentation

### Accessing API Docs

The application uses **Scalar** for interactive API documentation.

**URL:** `https://localhost:7119/scalar/v1` (Development only)

**Features:**
- ? Interactive endpoint testing
- ?? Code samples (C# HttpClient)
- ?? Search (Ctrl+K)
- ?? Download OpenAPI spec

### Key Endpoints

**Stream Management:**
```
POST   /api/StreamIngest/start/{streamId}
POST   /api/StreamIngest/upload/{streamId}
POST   /api/StreamIngest/stop/{streamId}
GET    /api/StreamIngest/status/{streamId}
GET    /api/StreamIngest/active
```

**Diagnostics:**
```
GET    /health
GET    /api/StreamIngest/diagnose/{streamId}
```

**OpenAPI Spec:**
```
GET    /openapi/v1.json
```

### Example Requests

**Start Stream:**
```http
POST /api/StreamIngest/start/stream_12345
Content-Type: application/json

{
  "title": "My Stream",
  "description": "Test stream"
}
```

**Upload Chunk:**
```http
POST /api/StreamIngest/upload/stream_12345
Content-Type: video/webm

[binary data]
```

**Get Status:**
```http
GET /api/StreamIngest/status/stream_12345
```

**Response:**
```json
{
  "streamId": "stream_12345",
  "status": "active",
  "metadata": {
    "chunksReceived": 150,
    "totalBytesReceived": 28650432,
    "duration": 120
  }
}
```

---

## ?? Monitoring & Maintenance

### Application Insights

```bash
# Create Application Insights
az monitor app-insights component create \
  --app livestream-insights \
  --location eastus \
  --resource-group Trial

# Add to app settings
az webapp config appsettings set \
  --name livestream-app \
  --settings APPLICATIONINSIGHTS_CONNECTION_STRING="InstrumentationKey=..."
```

### Logging

**View Logs:**
```bash
az webapp log tail --name livestream-app --resource-group Trial
```

**Download Logs:**
```bash
az webapp log download --name livestream-app --log-file logs.zip
```

### Maintenance Tasks

**Clear Old Streams:**
- Azure Portal ? Storage Account ? Containers ? livestreams
- Delete old stream folders

**Monitor Costs:**
- Azure Portal ? Cost Management
- Set up budget alerts

**Update Configuration:**
```powershell
cd Server
dotnet user-secrets set "AzureStorage:ConnectionString" "NEW_VALUE"
```

---

## ?? Additional Resources

### Documentation
- **GitHub Repository:** https://github.com/chethandvg/LiveStreamApp
- **Azure App Service:** https://docs.microsoft.com/azure/app-service/
- **Azure Front Door:** https://docs.microsoft.com/azure/frontdoor/
- **Scalar API Docs:** https://github.com/scalar/scalar

### Support
- **GitHub Issues:** https://github.com/chethandvg/LiveStreamApp/issues
- **Azure Support:** https://azure.microsoft.com/support/

---

**Version:** 2.0  
**Last Updated:** 2024-01-15  
**License:** MIT
