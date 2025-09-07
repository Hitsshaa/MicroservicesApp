using Microsoft.EntityFrameworkCore;
using UserService.Models;

namespace UserService.Data;

public class UserRepository(UserDbContext ctx) : IUserRepository
{
    private readonly UserDbContext _ctx = ctx;

    public async Task<User> AddAsync(User user)
    {
        user.CreatedAt = DateTime.UtcNow;
        user.UpdatedAt = user.CreatedAt;
        _ctx.Users.Add(user);
        await _ctx.SaveChangesAsync();
        return user;
    }

    public async Task<bool> DeleteAsync(int id)
    {
        var entity = await _ctx.Users.FindAsync(id);
        if (entity == null) return false;
        _ctx.Users.Remove(entity);
        await _ctx.SaveChangesAsync();
        return true;
    }

    public async Task<IEnumerable<User>> GetAllAsync() => await _ctx.Users.AsNoTracking().ToListAsync();

    public async Task<User?> GetByIdAsync(int id) => await _ctx.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == id);

    public async Task<User?> UpdateAsync(User user)
    {
        var existing = await _ctx.Users.FindAsync(user.Id);
        if (existing == null) return null;
        existing.FirstName = user.FirstName;
        existing.LastName = user.LastName;
        existing.Email = user.Email;
        existing.UpdatedAt = DateTime.UtcNow;
        await _ctx.SaveChangesAsync();
        return existing;
    }
}
