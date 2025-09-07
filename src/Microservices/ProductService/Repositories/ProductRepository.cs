using Microsoft.EntityFrameworkCore;
using ProductService.Data;
using ProductService.Models;

namespace ProductService.Repositories;

public class ProductRepository(ProductDbContext ctx) : IProductRepository
{
    private readonly ProductDbContext _ctx = ctx;
    public async Task<Product> AddAsync(Product product)
    {
        product.CreatedAt = DateTime.UtcNow;
        product.UpdatedAt = product.CreatedAt;
        _ctx.Products.Add(product);
        await _ctx.SaveChangesAsync();
        return product;
    }
    public async Task<bool> DeleteAsync(int id)
    {
        var p = await _ctx.Products.FindAsync(id);
        if (p == null) return false;
        _ctx.Remove(p);
        await _ctx.SaveChangesAsync();
        return true;
    }
    public async Task<IEnumerable<Product>> GetAllAsync() => await _ctx.Products.AsNoTracking().ToListAsync();
    public async Task<Product?> GetByIdAsync(int id) => await _ctx.Products.AsNoTracking().FirstOrDefaultAsync(p => p.Id == id);
    public async Task<Product?> UpdateAsync(Product product)
    {
        var existing = await _ctx.Products.FindAsync(product.Id);
        if (existing == null) return null;
        existing.Name = product.Name;
        existing.Description = product.Description;
        existing.Price = product.Price;
        existing.StockQuantity = product.StockQuantity;
        existing.UpdatedAt = DateTime.UtcNow;
        await _ctx.SaveChangesAsync();
        return existing;
    }
}
