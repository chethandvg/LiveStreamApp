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

// Add SignalR with Azure SignalR Service
var signalRConnectionString = builder.Configuration["Azure:SignalR:ConnectionString"];
if (string.IsNullOrEmpty(signalRConnectionString))
{
    // Fallback to in-memory SignalR if connection string is not provided
    builder.Services.AddSignalR();
    Console.WriteLine("WARNING: Azure SignalR connection string not found. Using in-memory SignalR.");
}
else if (signalRConnectionString.Contains("azure.msi"))
{
    // Using Managed Identity
    builder.Services.AddSignalR()
        .AddAzureSignalR(options =>
        {
            options.ConnectionString = signalRConnectionString;
        });
    Console.WriteLine("INFO: Azure SignalR configured with Managed Identity authentication.");
}
else
{
    // Using Access Key
    builder.Services.AddSignalR()
        .AddAzureSignalR(options =>
        {
            options.ConnectionString = signalRConnectionString;
        });
    Console.WriteLine("INFO: Azure SignalR configured with Access Key authentication.");
}

// Register the background transcoding service
builder.Services.AddHostedService<TranscodingService>();

// Configure CORS for Blazor WASM
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowBlazor", policy =>
    {
        if (builder.Environment.IsDevelopment())
        {
            policy
                .WithOrigins("https://localhost:7195")
                .AllowAnyMethod()
                .AllowAnyHeader()
                .AllowCredentials();
        }
        else
        {
            policy
                .WithOrigins("https://yourdomain.com")
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

// Enable CORS
app.UseCors("AllowBlazor");

app.UseAuthorization();

app.MapControllers();
app.MapHub<ChatHub>("/chathub");
app.MapFallbackToFile("index.html");
app.Run();
