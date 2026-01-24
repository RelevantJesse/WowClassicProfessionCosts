namespace WowAhPlanner.Infrastructure.Persistence;

public sealed class OwnedMaterialEntity
{
    public required string RealmKey { get; init; }
    public required string UserId { get; init; }
    public required int ItemId { get; init; }

    public required long Quantity { get; set; }
    public required DateTime UpdatedAtUtc { get; set; }
}

