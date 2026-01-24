namespace WowAhPlanner.Web.Services;

using WowAhPlanner.Core.Domain;

public sealed class SelectionState(LocalStorageService localStorage)
{
    private const string StorageKey = "WowAhPlanner.Selection.v1";
    private bool _loaded;

    public Region Region { get; set; } = Region.US;
    public GameVersion GameVersion { get; set; } = GameVersion.Era;
    public string RealmSlug { get; set; } = "whitemane";
    public int ProfessionId { get; set; } = 185;

    public async Task EnsureLoadedAsync()
    {
        if (_loaded) return;
        _loaded = true;

        try
        {
            var stored = await localStorage.GetAsync<SelectionDto>(StorageKey);
            if (stored is null) return;

            Region = stored.Region;
            GameVersion = stored.GameVersion;
            RealmSlug = stored.RealmSlug ?? RealmSlug;
            if (stored.ProfessionId > 0) ProfessionId = stored.ProfessionId;
        }
        catch
        {
        }
    }

    public async Task PersistAsync()
    {
        try
        {
            await localStorage.SetAsync(StorageKey, new SelectionDto(Region, GameVersion, RealmSlug.Trim().ToLowerInvariant(), ProfessionId));
        }
        catch
        {
        }
    }

    public RealmKey ToRealmKey() => new(Region, GameVersion, RealmSlug);

    private sealed record SelectionDto(Region Region, GameVersion GameVersion, string? RealmSlug, int ProfessionId);
}
