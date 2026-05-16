using Microsoft.EntityFrameworkCore;
using ProductService.Data;
using ProductService.Repositories;
using Microsoft.OpenApi.Models;

var builder = WebApplication.CreateBuilder(args);
var cs = builder.Configuration.GetConnectionString("DefaultConnection")
         ?? Environment.GetEnvironmentVariable("ConnectionStrings__DefaultConnection")
         ?? "Host=postgres;Port=5432;Database=productservicedb;Username=postgres;Password=postgres";

builder.Services.AddDbContext<ProductDbContext>(o => o.UseNpgsql(cs));
builder.Services.AddScoped<IProductRepository, ProductRepository>();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "Product Service", Version = "v1" });
});
builder.Services.AddControllers();
builder.Services.AddHealthChecks().AddDbContextCheck<ProductDbContext>("db");
builder.Services.AddCors(o => o.AddPolicy("allow-all", p => p.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod()));

var app = builder.Build();

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<ProductDbContext>();
    var logger = scope.ServiceProvider.GetRequiredService<ILoggerFactory>().CreateLogger("Schema");

    var retries = 10;
    while (retries > 0)
    {
        try
        {
            db.Database.EnsureCreated();
            logger.LogInformation("Database schema ready");
            break;
        }
        catch (Exception ex)
        {
            retries--;
            logger.LogWarning(ex, "Waiting for PostgreSQL... ({Retries} retries left)", retries);
            Thread.Sleep(5000);
        }
    }

    try
    {
        await ProductDbSeeder.SeedAsync(db, logger);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Failed to seed database");
    }
}

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI(c =>
    {
        c.SwaggerEndpoint("/swagger/v1/swagger.json", "Product Service v1");
    });
}
app.UseCors("allow-all");
app.MapControllers();
app.MapHealthChecks("/health");
app.Run();
