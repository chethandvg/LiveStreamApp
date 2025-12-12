# Scalar API Documentation

This project uses **Scalar** for interactive API documentation, providing a modern and user-friendly interface to explore and test the Live Stream API.

## Accessing Scalar API Documentation

### Development Environment

When running the application in **Development** mode, Scalar is automatically enabled and accessible at:

```
https://localhost:<port>/scalar/v1
```

For example, if your API is running on port 7001:
```
https://localhost:7001/scalar/v1
```

### Features Enabled

The Scalar implementation includes:

? **Interactive API Reference** - Test endpoints directly from the browser  
? **Purple Theme** - Modern, visually appealing interface  
? **Code Samples** - Default C# HttpClient examples  
? **Models View** - Clear view of request/response models  
? **Search** - Press `Ctrl+K` or `Cmd+K` for quick search  
? **Download OpenAPI Spec** - Download button for API specification  
? **Sidebar Navigation** - Easy navigation through endpoints  

## API Endpoints Documented

### Stream Management (`/api/StreamIngest`)

1. **POST** `/api/StreamIngest/start/{streamId}` - Start a new live stream
2. **POST** `/api/StreamIngest/upload/{streamId}` - Upload video chunk
3. **POST** `/api/StreamIngest/stop/{streamId}` - Stop an active stream
4. **GET** `/api/StreamIngest/status/{streamId}` - Get stream status
5. **GET** `/api/StreamIngest/active` - Get all active streams

## OpenAPI Specification

The OpenAPI specification is also available at:
```
https://localhost:<port>/openapi/v1.json
```

## Configuration

The Scalar configuration can be found in `Server/Program.cs`:

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

You can customize Scalar by modifying the options:

- **Theme**: `Purple`, `Blue`, `Green`, `Orange`, `Default`, `Moon`, `Mars`
- **HTTP Client**: `CSharp`, `JavaScript`, `Python`, `Go`, `PHP`, etc.
- **Search Hotkey**: Change the keyboard shortcut (default: "k")

## Production Deployment

By default, Scalar is only enabled in Development mode for security. To enable in production:

1. Remove the `if (app.Environment.IsDevelopment())` condition
2. Consider adding authentication/authorization
3. Update the CORS policy if needed

```csharp
// Enable in all environments (use with caution)
app.MapOpenApi();
app.MapScalarApiReference();
```

## Additional Resources

- [Scalar Documentation](https://github.com/scalar/scalar)
- [ASP.NET Core OpenAPI](https://learn.microsoft.com/aspnet/core/fundamentals/openapi)
