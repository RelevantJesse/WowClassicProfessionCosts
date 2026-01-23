namespace WowAhPlanner.Core.Domain;

public sealed record PriceSnapshot(
    RealmKey RealmKey,
    string ProviderName,
    DateTime SnapshotTimestampUtc,
    bool IsStale,
    string? ErrorMessage,
    IReadOnlyDictionary<int, PriceSummary> Prices);

