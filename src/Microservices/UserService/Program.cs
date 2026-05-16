using Microsoft.EntityFrameworkCore;
using UserService.Data;
using Microsoft.OpenApi.Models;

var builder = WebApplication.CreateBuilder(args);

var cs = builder.Configuration.GetConnectionString("DefaultConnection")
         ?? Environment.GetEnvironmentVariable("ConnectionStrings__DefaultConnection")
         ?? "Host=postgres;Port=5432;Database=userservicedb;Username=postgres;Password=postgres";

builder.Services.AddDbContext<UserDbContext>(o => o.UseNpgsql(cs));
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
        await UserDbSeeder.SeedAsync(db, logger);
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
        c.SwaggerEndpoint("/swagger/v1/swagger.json", "User Service v1");
    });
}

app.UseCors("allow-all");
app.MapControllers();
app.MapHealthChecks("/health");

app.Run();
