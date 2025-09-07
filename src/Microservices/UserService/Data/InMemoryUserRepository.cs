using System.Collections.Concurrent;
using UserService.Models;

namespace UserService.Data;

public class InMemoryUserRepository : IUserRepository
{
    private readonly ConcurrentDictionary<int, User> _store = new();
    private int _id = 0;

    public Task<User> AddAsync(User user)
    {
        var id = Interlocked.Increment(ref _id);
        user.Id = id;
        user.CreatedAt = DateTime.UtcNow;
        user.UpdatedAt = user.CreatedAt;
        _store[id] = user;
        return Task.FromResult(user);
    }

    public Task<bool> DeleteAsync(int id)
    {
        return Task.FromResult(_store.TryRemove(id, out _));
    }

    public Task<IEnumerable<User>> GetAllAsync()
        => Task.FromResult(_store.Values.AsEnumerable());

    public Task<User?> GetByIdAsync(int id)
    {
        _store.TryGetValue(id, out var user);
        return Task.FromResult(user);
    }

    public Task<User?> UpdateAsync(User user)
    {
        if (!_store.ContainsKey(user.Id)) return Task.FromResult<User?>(null);
        user.UpdatedAt = DateTime.UtcNow;
        _store[user.Id] = user;
        return Task.FromResult<User?>(user);
    }
}
