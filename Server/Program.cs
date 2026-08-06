using Microsoft.AspNetCore.ResponseCompression;
using Scalar.AspNetCore;
using Server.Hubs;
using Server.Services;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddOpenApi(options =>
{
    options.AddDocumentTransformer((document, context, cancellationToken) =>
    {
        document.Info.Title = "Live Stream API";
        document.Info.Version = "v1";
        document.Info.Description = "API for managing live streaming, chat, and transcoding services";
        return Task.CompletedTask;
    });
});

// Add Health Checks
builder.Services.AddHealthChecks();

// Add SignalR with Azure SignalR Service
var signalRConnectionString = builder.Configuration["Azure:SignalR:ConnectionString"];
var useLocalSignalR = builder.Configuration.GetValue<bool>("Azure:SignalR:UseLocal");

if (useLocalSignalR || string.IsNullOrEmpty(signalRConnectionString))
{
    // Fallback to in-memory SignalR if connection string is not provided or UseLocal is true
    builder.Services.AddSignalR(hubOptions =>
    {
        hubOptions.EnableDetailedErrors = true;
        hubOptions.ClientTimeoutInterval = TimeSpan.FromSeconds(60);
        hubOptions.KeepAliveInterval = TimeSpan.FromSeconds(15);
    });
    if (useLocalSignalR)
    {
        Console.WriteLine("INFO: Using local SignalR (Azure:SignalR:UseLocal is true).");
    }
    else
    {
        Console.WriteLine("WARNING: Azure SignalR connection string not found. Using in-memory SignalR.");
    }
}
else if (signalRConnectionString.Contains("azure.msi"))
{
    // Using Managed Identity
    builder.Services.AddSignalR()
        .AddAzureSignalR(options =>
        {
            options.ConnectionString = signalRConnectionString;
            options.ServerStickyMode = Microsoft.Azure.SignalR.ServerStickyMode.Required;
        });
    Console.WriteLine("INFO: Azure SignalR configured with Managed Identity authentication.");
}
else
{
    // Using Access Key
    builder.Services.AddSignalR(hubOptions =>
    {
        hubOptions.EnableDetailedErrors = true;
        hubOptions.ClientTimeoutInterval = TimeSpan.FromSeconds(60);
        hubOptions.KeepAliveInterval = TimeSpan.FromSeconds(15);
    })
    .AddAzureSignalR(options =>
    {
        options.ConnectionString = signalRConnectionString;
        options.ServerStickyMode = Microsoft.Azure.SignalR.ServerStickyMode.Required;
        options.ConnectionCount = 5;
        options.GracefulShutdown.Mode = Microsoft.Azure.SignalR.GracefulShutdownMode.WaitForClientsClose;
        options.GracefulShutdown.Timeout = TimeSpan.FromSeconds(30);
    });
    Console.WriteLine("INFO: Azure SignalR configured with Access Key authentication.");
}

// Register the background transcoding service
builder.Services.AddHostedService<TranscodingService>();

// Configure CORS for Blazor WASM with environment-specific origins
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowBlazor", policy =>
    {
        if (builder.Environment.IsDevelopment())
        {
            policy
                .WithOrigins("https://localhost:7195", "http://localhost:5000")
                .AllowAnyMethod()
                .AllowAnyHeader()
                .AllowCredentials();
        }
        else
        {
            // Production origins - update these with your actual domains
            var allowedOrigins = new List<string>();
            
            var appServiceUrl = builder.Configuration["AllowedOrigins:AppService"];
            var cdnUrl = builder.Configuration["AllowedOrigins:CDN"];
            var customDomain = builder.Configuration["AllowedOrigins:CustomDomain"];
            
            if (!string.IsNullOrEmpty(appServiceUrl)) allowedOrigins.Add(appServiceUrl);
            if (!string.IsNullOrEmpty(cdnUrl)) allowedOrigins.Add(cdnUrl);
            if (!string.IsNullOrEmpty(customDomain)) allowedOrigins.Add(customDomain);
            
            // Fallback to default if no origins configured
            if (allowedOrigins.Count == 0)
            {
                allowedOrigins.Add("https://yourdomain.com");
            }
            
            policy
                .WithOrigins(allowedOrigins.ToArray())
                .AllowAnyMethod()
                .AllowAnyHeader()
                .AllowCredentials();
        }
    });
});

// Add response compression for SignalR
builder.Services.AddResponseCompression(opts =>
{
    opts.MimeTypes = ResponseCompressionDefaults.MimeTypes.Concat(
        new[] { "application/octet-stream" });
});

var app = builder.Build();

// Configure the HTTP request pipeline
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
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
    app.UseWebAssemblyDebugging();
}
else
{
    app.UseExceptionHandler("/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseBlazorFrameworkFiles();
app.UseStaticFiles();

app.UseRouting();

// Enable CORS before authorization
app.UseCors("AllowBlazor");

app.UseAuthorization();

// Map health check endpoint
app.MapHealthChecks("/health");

app.MapControllers();
app.MapHub<ChatHub>("/chathub");
app.MapFallbackToFile("index.html");

app.Run();
