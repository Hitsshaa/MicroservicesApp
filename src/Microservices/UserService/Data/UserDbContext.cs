using Microsoft.EntityFrameworkCore;
using UserService.Models;

namespace UserService.Data;

public class UserDbContext(DbContextOptions<UserDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<User>().HasIndex(u => u.Email).IsUnique();
    }
}

public static class UserDbSeeder
{
    public static async Task SeedAsync(UserDbContext ctx, ILogger logger)
    {
        if (await ctx.Users.AnyAsync()) return;
        ctx.Users.AddRange(
            new User { FirstName = "Alice", LastName = "Anderson", Email = "alice@example.com", CreatedAt = DateTime.UtcNow, UpdatedAt = DateTime.UtcNow },
            new User { FirstName = "Bob", LastName = "Brown", Email = "bob@example.com", CreatedAt = DateTime.UtcNow, UpdatedAt = DateTime.UtcNow },
            new User { FirstName = "Charlie", LastName = "Clark", Email = "charlie@example.com", CreatedAt = DateTime.UtcNow, UpdatedAt = DateTime.UtcNow }
        );
        await ctx.SaveChangesAsync();
        logger.LogInformation("Seeded default users");
    }
}
