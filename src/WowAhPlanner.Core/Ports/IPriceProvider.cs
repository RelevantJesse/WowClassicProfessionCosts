namespace WowAhPlanner.Core.Ports;

using WowAhPlanner.Core.Domain;

public interface IPriceProvider
{
    string Name { get; }

    Task<PriceProviderResult> GetPricesAsync(
        RealmKey realmKey,
        IReadOnlyCollection<int> itemIds,
        PriceMode priceMode,
        CancellationToken cancellationToken);
}

public sealed record PriceProviderResult(
    bool Success,
    string ProviderName,
    DateTime SnapshotTimestampUtc,
    IReadOnlyDictionary<int, PriceSummary> Prices,
    string? ErrorCode,
    string? ErrorMessage);

