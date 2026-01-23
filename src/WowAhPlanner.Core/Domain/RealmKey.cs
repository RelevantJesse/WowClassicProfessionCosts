namespace WowAhPlanner.Core.Domain;

public sealed record RealmKey(Region Region, GameVersion GameVersion, string RealmSlug)
{
    public override string ToString() => $"{Region}-{GameVersion}-{RealmSlug}".ToLowerInvariant();
}

