namespace WowAhPlanner.Infrastructure.Persistence;

public sealed class ItemPriceSummaryEntity
{
    public required string RealmKey { get; init; }
    public required string ProviderName { get; init; }
    public required int ItemId { get; init; }

    public required long MinBuyoutCopper { get; set; }
    public long? MedianCopper { get; set; }

    public required DateTime SnapshotTimestampUtc { get; set; }
    public required DateTime CachedAtUtc { get; set; }
}

