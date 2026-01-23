namespace WowAhPlanner.Core.Domain;

public sealed record PriceSummary(
    int ItemId,
    long MinBuyoutCopper,
    long? MedianCopper,
    DateTime SnapshotTimestampUtc,
    string SourceProvider);

