var builder = WebApplication.CreateBuilder(args);

// YARP reverse proxy — routes and clusters are defined in the
// "ReverseProxy" section of appsettings.json.
builder.Services.AddReverseProxy()
    .LoadFromConfig(builder.Configuration.GetSection("ReverseProxy"));
builder.Services.AddCors(o => o.AddPolicy("allow-all", p => p.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod()));
builder.Services.AddOpenApi();

var app = builder.Build();
if (app.Environment.IsDevelopment()) app.MapOpenApi();

app.UseCors("allow-all");
app.MapGet("/health", () => Results.Ok(new { status = "Healthy", service = "ApiGateway" }));
app.MapReverseProxy();
app.Run();
