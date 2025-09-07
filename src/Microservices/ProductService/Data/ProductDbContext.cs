using Microsoft.EntityFrameworkCore;
using ProductService.Models;

namespace ProductService.Data;

public class ProductDbContext(DbContextOptions<ProductDbContext> options) : DbContext(options)
{
    public DbSet<Product> Products => Set<Product>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Product>().HasIndex(p => p.Name);
        modelBuilder.Entity<Product>().Property(p => p.Price).HasPrecision(18, 2);
    }
}

public static class ProductDbSeeder
{
    public static async Task SeedAsync(ProductDbContext ctx, ILogger logger)
    {
        if (await ctx.Products.AnyAsync()) return;
        ctx.Products.AddRange(
            new Product { Name = "Keyboard", Description = "Mechanical", Price = 89.99m, StockQuantity = 150, CreatedAt = DateTime.UtcNow, UpdatedAt = DateTime.UtcNow },
            new Product { Name = "Mouse", Description = "Wireless", Price = 49.50m, StockQuantity = 300, CreatedAt = DateTime.UtcNow, UpdatedAt = DateTime.UtcNow },
            new Product { Name = "Monitor", Description = "27'' 4K", Price = 399.00m, StockQuantity = 75, CreatedAt = DateTime.UtcNow, UpdatedAt = DateTime.UtcNow },
            new Product { Name = "Dock", Description = "USB-C Dock", Price = 129.00m, StockQuantity = 60, CreatedAt = DateTime.UtcNow, UpdatedAt = DateTime.UtcNow },
            new Product { Name = "Headset", Description = "Noise Cancelling", Price = 199.99m, StockQuantity = 90, CreatedAt = DateTime.UtcNow, UpdatedAt = DateTime.UtcNow }
        );
        await ctx.SaveChangesAsync();
        logger.LogInformation("Seeded default products");
    }
}
