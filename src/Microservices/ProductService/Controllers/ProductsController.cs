using Microsoft.AspNetCore.Mvc;
using ProductService.DTOs;
using ProductService.Models;
using ProductService.Repositories;

namespace ProductService.Controllers;

[ApiController]
[Route("api/[controller]")]
public class ProductsController(IProductRepository repo, ILogger<ProductsController> logger) : ControllerBase
{
    private readonly IProductRepository _repo = repo;
    private readonly ILogger<ProductsController> _logger = logger;

    [HttpGet]
    public async Task<ActionResult<IEnumerable<ProductDto>>> GetAll()
        => Ok((await _repo.GetAllAsync()).Select(Map));

    [HttpGet("{id}")]
    public async Task<ActionResult<ProductDto>> Get(int id)
    {
        var product = await _repo.GetByIdAsync(id);
        return product == null ? NotFound() : Ok(Map(product));
    }

    [HttpPost]
    public async Task<ActionResult<ProductDto>> Create([FromBody] CreateProductDto dto)
    {
        if (!ModelState.IsValid) return ValidationProblem(ModelState);
        var entity = new Product
        {
            Name = dto.Name,
            Description = dto.Description,
            Price = dto.Price,
            StockQuantity = dto.StockQuantity
        };
        var created = await _repo.AddAsync(entity);
        return CreatedAtAction(nameof(Get), new { id = created.Id }, Map(created));
    }

    [HttpPut("{id}")]
    public async Task<ActionResult<ProductDto>> Update(int id, [FromBody] CreateProductDto dto)
    {
        if (!ModelState.IsValid) return ValidationProblem(ModelState);
        var entity = new Product { Id = id, Name = dto.Name, Description = dto.Description, Price = dto.Price, StockQuantity = dto.StockQuantity };
        var updated = await _repo.UpdateAsync(entity);
        return updated == null ? NotFound() : Ok(Map(updated));
    }

    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(int id)
        => await _repo.DeleteAsync(id) ? NoContent() : NotFound();

    private static ProductDto Map(Product p) => new()
    {
        Id = p.Id,
        Name = p.Name,
        Description = p.Description,
        Price = p.Price,
        StockQuantity = p.StockQuantity,
        CreatedAt = p.CreatedAt,
        UpdatedAt = p.UpdatedAt
    };
}
