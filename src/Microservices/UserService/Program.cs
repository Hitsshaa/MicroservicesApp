using Microsoft.EntityFrameworkCore;
using UserService.Data;
using Microsoft.OpenApi.Models;

var builder = WebApplication.CreateBuilder(args);

var cs = builder.Configuration.GetConnectionString("DefaultConnection")
         ?? Environment.GetEnvironmentVariable("ConnectionStrings__DefaultConnection")
         ?? "Server=sqlserver;Database=MicroservicesDb;User=hitesh;Password=Hitesh12;TrustServerCertificate=True;";

builder.Services.AddDbContext<UserDbContext>(o => o.UseSqlServer(cs));
builder.Services.AddScoped<IUserRepository, UserRepository>();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "User Service", Version = "v1" });
});
builder.Services.AddControllers();
builder.Services.AddHealthChecks().AddDbContextCheck<UserDbContext>("db");
builder.Services.AddCors(o => o.AddPolicy("allow-all", p => p.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod()));

var app = builder.Build();

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<UserDbContext>();
    var logger = scope.ServiceProvider.GetRequiredService<ILoggerFactory>().CreateLogger("Migrations");
    
    try
    {
        // Ensure database is created even if migrations are pending
        var retries = 10;
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
        await UserDbSeeder.SeedAsync(db, logger);
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
        c.SwaggerEndpoint("/swagger/v1/swagger.json", "User Service v1");
    });
}

app.UseCors("allow-all");
app.MapControllers();
app.MapHealthChecks("/health");

app.Run();
