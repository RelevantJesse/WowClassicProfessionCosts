namespace WowAhPlanner.Web.Services;

using WowAhPlanner.Core.Domain;

public sealed class RealmCatalog
{
    private static readonly IReadOnlyDictionary<(Region Region, GameVersion Version), Realm[]> Realms = new Dictionary<(Region, GameVersion), Realm[]>
    {
        [(Region.US, GameVersion.Era)] =
        [
            new Realm("whitemane", "Whitemane"),
            new Realm("mankrik", "Mankrik"),
            new Realm("bloodsail-buccaneers", "Bloodsail Buccaneers"),
        ],
        [(Region.EU, GameVersion.Era)] =
        [
            new Realm("firemaw", "Firemaw"),
            new Realm("gehennas", "Gehennas"),
        ],
    };

    public IReadOnlyList<Realm> GetRealms(Region region, GameVersion version)
        => Realms.TryGetValue((region, version), out var realms) ? realms : [];
}

