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
        // Treat this as a full replacement snapshot for (realmKey, userId).
        // Items not present in the incoming set will be deleted so stale rows don't linger.

        await using var db = await dbContextFactory.CreateDbContextAsync(cancellationToken);
        await SqliteSchemaBootstrapper.EnsureAppSchemaAsync(db, cancellationToken);

        var incoming = items
            .Where(x => x.ItemId > 0 && x.Quantity > 0)
            .GroupBy(x => x.ItemId)
            .Select(g => (ItemId: g.Key, Quantity: g.Max(x => x.Quantity)))
            .ToDictionary(x => x.ItemId, x => x.Quantity);

        var existingRows = await db.OwnedMaterials
            .Where(x => x.RealmKey == realmKey && x.UserId == userId)
            .ToListAsync(cancellationToken);

        var existingByItemId = existingRows.ToDictionary(x => x.ItemId);
        var incomingItemIds = incoming.Keys.ToHashSet();

        foreach (var row in existingRows)
        {
            if (!incomingItemIds.Contains(row.ItemId))
            {
                db.OwnedMaterials.Remove(row);
            }
        }

        foreach (var (itemId, qty) in incoming)
        {
            if (existingByItemId.TryGetValue(itemId, out var row))
            {
                row.Quantity = qty;
                row.UpdatedAtUtc = DateTime.UtcNow;
            }
            else
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
        }

        await db.SaveChangesAsync(cancellationToken);
        return incoming.Count;
    }
}
