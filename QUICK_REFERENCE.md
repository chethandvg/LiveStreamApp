# ?? Documentation Quick Reference

## ?? Documentation Files

| File | Purpose | Lines | Read Time |
|------|---------|-------|-----------|
| [README.md](README.md) | Project overview & quick start | ~100 | 2 min |
| [DOCS.md](DOCS.md) | Complete documentation | ~700 | 15 min |
| [API.md](API.md) | API reference & examples | ~250 | 5 min |

---

## ??? Find What You Need

### Getting Started
? **[README.md](README.md)** - Quick start in 3 steps

### Configuration
? **[DOCS.md § Configuration](DOCS.md#-configuration)** - Server & client setup

### PowerShell Scripts
? **[DOCS.md § PowerShell Scripts](DOCS.md#-powershell-scripts)** - Script reference

### Troubleshooting
? **[DOCS.md § Troubleshooting](DOCS.md#-troubleshooting)** - Common issues & fixes

### Deployment
? **[DOCS.md § Deployment](DOCS.md#-deployment)** - Azure deployment guide

### API Documentation
? **[API.md](API.md)** - Endpoints, examples, code samples

### Interactive API Docs
? `https://localhost:7119/scalar/v1` - Test endpoints

---

## ?? Common Tasks

| Task | Documentation |
|------|---------------|
| First-time setup | [README.md](README.md) |
| Fix stream 404 error | [DOCS.md § Troubleshooting](DOCS.md#stream-404-errors) |
| Fix CORS issues | [DOCS.md § Troubleshooting](DOCS.md#cors-issues) |
| Fix SignalR problems | [DOCS.md § Troubleshooting](DOCS.md#signalr-connection-problems) |
| Run PowerShell scripts | [DOCS.md § PowerShell Scripts](DOCS.md#-powershell-scripts) |
| Deploy to Azure | [DOCS.md § Deployment](DOCS.md#-deployment) |
| Configure Azure Storage | [DOCS.md § Configuration](DOCS.md#-configuration) |
| Use API endpoints | [API.md](API.md) |

---

## ?? Quick Commands

```powershell
# Verify environment
.\azure-deployment.ps1 -Action Check

# Configure CORS
.\azure-deployment.ps1 -Action Configure

# Setup CDN
.\azure-deployment.ps1 -Action Setup

# Deploy
.\azure-deployment.ps1 -Action Deploy

# Diagnose stream
.\azure-deployment.ps1 -Action Diagnose -StreamId "stream_xxxxx"

# Test SignalR
.\test-signalr-connection.ps1

# Verify SignalR
.\verify-signalr-setup.ps1

# Verify Front Door
.\verify-frontdoor-setup.ps1
```

---

## ?? Documentation Structure

```
LiveStreamApp/
??? README.md                      # Project overview
??? DOCS.md                        # Complete documentation
?   ??? Quick Start
?   ??? Project Overview
?   ??? Configuration
?   ??? PowerShell Scripts
?   ??? Troubleshooting
?   ??? Deployment
?   ??? API Documentation
?
??? API.md                         # API reference
?   ??? Endpoints
?   ??? Examples
?   ??? Code Samples
?   ??? Error Codes
?
??? CONSOLIDATION_COMPLETE.md      # This consolidation summary
```

---

## ?? Tips

- ?? **Start with README.md** for quick overview
- ?? **Use DOCS.md** as your main reference
- ?? **Check API.md** when integrating
- ?? **Use Ctrl+F** to search within docs
- ?? **Try `/scalar/v1`** for interactive API testing

---

**Updated:** 2024-01-15
