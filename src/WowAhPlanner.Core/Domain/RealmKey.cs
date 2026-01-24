namespace WowAhPlanner.Core.Domain;

public sealed record RealmKey
{
    public RealmKey(Region region, GameVersion gameVersion, string realmSlug)
    {
        Region = region;
        GameVersion = gameVersion;
        RealmSlug = NormalizeRealmSlug(realmSlug);
    }

    public Region Region { get; init; }
    public GameVersion GameVersion { get; init; }
    public string RealmSlug { get; init; }

    public override string ToString() => $"{Region}-{GameVersion}-{RealmSlug}".ToLowerInvariant();

    private static string NormalizeRealmSlug(string realmSlug)
    {
        if (string.IsNullOrWhiteSpace(realmSlug))
        {
            return "";
        }

        return realmSlug.Trim().ToLowerInvariant();
    }
}
