using Microsoft.EntityFrameworkCore;
using ProductService.Data;
using ProductService.Repositories;
using Microsoft.OpenApi.Models;

var builder = WebApplication.CreateBuilder(args);
var cs = builder.Configuration.GetConnectionString("DefaultConnection")
         ?? Environment.GetEnvironmentVariable("ConnectionStrings__DefaultConnection")
         ?? "Server=sqlserver;Database=ProductServiceDB;User=sa;Password=Hitesh12@;TrustServerCertificate=True;";

builder.Services.AddDbContext<ProductDbContext>(o => o.UseSqlServer(cs));
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
    var logger = scope.ServiceProvider.GetRequiredService<ILoggerFactory>().CreateLogger("Migrations");
    
    try
    {
        var retries = 10;
        // Ensure database is created even if migrations are pending
        while (retries > 0)
        {
            try
            {
                db.Database.Migrate();
                break;
            }
            catch
            {
                retries--;
                Console.WriteLine("Waiting for SQL Server...");
                Thread.Sleep(5000);
            }
        }
        logger.LogInformation("Database created or already exists");

        // Seed the database
        await ProductDbSeeder.SeedAsync(db, logger);
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "An error occurred while initializing the database");
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
