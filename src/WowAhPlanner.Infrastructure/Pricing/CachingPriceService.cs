namespace WowAhPlanner.Infrastructure.Pricing;

using Microsoft.EntityFrameworkCore;
using WowAhPlanner.Core.Domain;
using WowAhPlanner.Core.Ports;
using WowAhPlanner.Infrastructure.Persistence;

public sealed class CachingPriceService(
    IDbContextFactory<AppDbContext> dbContextFactory,
    IEnumerable<IPriceProvider> providers,
    PricingOptions options) : IPriceService
{
    private readonly IReadOnlyDictionary<string, IPriceProvider> _providersByName =
        providers.ToDictionary(p => p.Name, StringComparer.OrdinalIgnoreCase);

    public async Task<PriceSnapshot> GetPricesAsync(
        RealmKey realmKey,
        IReadOnlyCollection<int> itemIds,
        PriceMode priceMode,
        CancellationToken cancellationToken)
    {
        var provider = ResolveProvider(options.PrimaryProviderName) ?? _providersByName.Values.First();
        var attempted = new List<(IPriceProvider Provider, PriceProviderResult Result)>();

        foreach (var p in EnumerateProviderAttempts(provider))
        {
            var result = await TryGetFromProvider(p, realmKey, itemIds, priceMode, cancellationToken);
            attempted.Add((p, result));

            if (result.Success)
            {
                await UpsertAsync(realmKey, result, cancellationToken);
                return await BuildSnapshotFromCacheAsync(realmKey, result.ProviderName, itemIds, isStale: false, errorMessage: null, cancellationToken);
            }
        }

        var last = attempted[^1];
        var error = last.Result.ErrorMessage ?? "Price provider failed.";
        var providerName = last.Provider.Name;

        return await BuildSnapshotFromCacheAsync(realmKey, providerName, itemIds, isStale: true, errorMessage: error, cancellationToken);
    }

    private IEnumerable<IPriceProvider> EnumerateProviderAttempts(IPriceProvider primary)
    {
        yield return primary;

        if (!string.IsNullOrWhiteSpace(options.FallbackProviderName) &&
            !string.Equals(options.FallbackProviderName, primary.Name, StringComparison.OrdinalIgnoreCase) &&
            ResolveProvider(options.FallbackProviderName) is { } fallback)
        {
            yield return fallback;
        }
    }

    private IPriceProvider? ResolveProvider(string? name)
    {
        if (string.IsNullOrWhiteSpace(name)) return null;
        return _providersByName.TryGetValue(name, out var p) ? p : null;
    }

    private static async Task<PriceProviderResult> TryGetFromProvider(
        IPriceProvider provider,
        RealmKey realmKey,
        IReadOnlyCollection<int> itemIds,
        PriceMode priceMode,
        CancellationToken cancellationToken)
    {
        try
        {
            return await provider.GetPricesAsync(realmKey, itemIds, priceMode, cancellationToken);
        }
        catch (Exception ex)
        {
            return new PriceProviderResult(
                Success: false,
                ProviderName: provider.Name,
                SnapshotTimestampUtc: DateTime.UtcNow,
                Prices: new Dictionary<int, PriceSummary>(),
                ErrorCode: "exception",
                ErrorMessage: ex.Message);
        }
    }

    private async Task UpsertAsync(RealmKey realmKey, PriceProviderResult result, CancellationToken cancellationToken)
    {
        await using var db = await dbContextFactory.CreateDbContextAsync(cancellationToken);

        foreach (var summary in result.Prices.Values)
        {
            var key = realmKey.ToString();
            var existing = await db.ItemPriceSummaries.FindAsync(
                key,
                result.ProviderName,
                summary.ItemId,
                cancellationToken);

            if (existing is null)
            {
                db.ItemPriceSummaries.Add(new ItemPriceSummaryEntity
                {
                    RealmKey = key,
                    ProviderName = result.ProviderName,
                    ItemId = summary.ItemId,
                    MinBuyoutCopper = summary.MinBuyoutCopper,
                    MedianCopper = summary.MedianCopper,
                    SnapshotTimestampUtc = summary.SnapshotTimestampUtc,
                    CachedAtUtc = DateTime.UtcNow,
                });
            }
            else
            {
                existing.MinBuyoutCopper = summary.MinBuyoutCopper;
                existing.MedianCopper = summary.MedianCopper;
                existing.SnapshotTimestampUtc = summary.SnapshotTimestampUtc;
                existing.CachedAtUtc = DateTime.UtcNow;
            }
        }

        await db.SaveChangesAsync(cancellationToken);
    }

    private async Task<PriceSnapshot> BuildSnapshotFromCacheAsync(
        RealmKey realmKey,
        string providerName,
        IReadOnlyCollection<int> itemIds,
        bool isStale,
        string? errorMessage,
        CancellationToken cancellationToken)
    {
        await using var db = await dbContextFactory.CreateDbContextAsync(cancellationToken);

        var key = realmKey.ToString();
        var entities = await db.ItemPriceSummaries
            .AsNoTracking()
            .Where(x => x.RealmKey == key && x.ProviderName == providerName && itemIds.Contains(x.ItemId))
            .ToListAsync(cancellationToken);

        var snapshotTs = entities.Count == 0
            ? DateTime.UtcNow
            : entities.Max(x => x.SnapshotTimestampUtc);

        var dict = entities.ToDictionary(
            x => x.ItemId,
            x => new PriceSummary(
                ItemId: x.ItemId,
                MinBuyoutCopper: x.MinBuyoutCopper,
                MedianCopper: x.MedianCopper,
                SnapshotTimestampUtc: x.SnapshotTimestampUtc,
                SourceProvider: x.ProviderName));

        return new PriceSnapshot(
            RealmKey: realmKey,
            ProviderName: providerName,
            SnapshotTimestampUtc: snapshotTs,
            IsStale: isStale,
            ErrorMessage: errorMessage,
            Prices: dict);
    }
}
