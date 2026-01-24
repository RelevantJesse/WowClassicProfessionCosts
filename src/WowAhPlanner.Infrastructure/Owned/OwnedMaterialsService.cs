namespace WowAhPlanner.Infrastructure.Owned;

using Microsoft.EntityFrameworkCore;
using WowAhPlanner.Infrastructure.Persistence;

public sealed class OwnedMaterialsService(IDbContextFactory<AppDbContext> dbContextFactory)
{
    public async Task<IReadOnlyDictionary<int, long>> GetOwnedAsync(
        string realmKey,
        string userId,
        CancellationToken cancellationToken = default)
    {
        await using var db = await dbContextFactory.CreateDbContextAsync(cancellationToken);
        await SqliteSchemaBootstrapper.EnsureAppSchemaAsync(db, cancellationToken);

        var rows = await db.OwnedMaterials
            .AsNoTracking()
            .Where(x => x.RealmKey == realmKey && x.UserId == userId)
            .ToListAsync(cancellationToken);

        return rows.ToDictionary(x => x.ItemId, x => x.Quantity);
    }

    public async Task<int> UpsertAsync(
        string realmKey,
        string userId,
        IReadOnlyCollection<(int ItemId, long Quantity)> items,
        CancellationToken cancellationToken = default)
    {
        if (items.Count == 0) return 0;

        await using var db = await dbContextFactory.CreateDbContextAsync(cancellationToken);
        await SqliteSchemaBootstrapper.EnsureAppSchemaAsync(db, cancellationToken);

        var updated = 0;
        foreach (var (itemId, qty) in items)
        {
            if (itemId <= 0) continue;
            if (qty < 0) continue;

            var existing = await db.OwnedMaterials.FindAsync([realmKey, userId, itemId], cancellationToken);
            if (existing is null)
            {
                db.OwnedMaterials.Add(new OwnedMaterialEntity
                {
                    RealmKey = realmKey,
                    UserId = userId,
                    ItemId = itemId,
                    Quantity = qty,
                    UpdatedAtUtc = DateTime.UtcNow,
                });
            }
            else
            {
                existing.Quantity = qty;
                existing.UpdatedAtUtc = DateTime.UtcNow;
            }

            updated++;
        }

        await db.SaveChangesAsync(cancellationToken);
        return updated;
    }
}

