namespace WowAhPlanner.Web.Services;

using WowAhPlanner.Core.Domain;

public sealed class PlannerPreferences(LocalStorageService localStorage)
{
    private const string StorageKey = "WowAhPlanner.PlannerPreferences.v1";
    private bool _loaded;
    private Dictionary<string, HashSet<string>> _excludedRecipeIdsByKey = new(StringComparer.OrdinalIgnoreCase);

    public async Task EnsureLoadedAsync()
    {
        if (_loaded) return;
        _loaded = true;

        try
        {
            var stored = await localStorage.GetAsync<PreferencesDto>(StorageKey);
            if (stored is null) return;

            _excludedRecipeIdsByKey = stored.ExcludedRecipeIdsByKey?
                .ToDictionary(
                    kvp => kvp.Key,
                    kvp => new HashSet<string>(kvp.Value ?? [], StringComparer.OrdinalIgnoreCase),
                    StringComparer.OrdinalIgnoreCase)
                ?? new Dictionary<string, HashSet<string>>(StringComparer.OrdinalIgnoreCase);
        }
        catch
        {
        }
    }

    public IReadOnlySet<string> GetExcludedRecipeIds(GameVersion version, int professionId)
    {
        var key = GetKey(version, professionId);
        return _excludedRecipeIdsByKey.TryGetValue(key, out var set) ? set : [];
    }

    public async Task SetRecipeExcludedAsync(GameVersion version, int professionId, string recipeId, bool excluded)
    {
        await EnsureLoadedAsync();

        var key = GetKey(version, professionId);
        if (!_excludedRecipeIdsByKey.TryGetValue(key, out var set))
        {
            set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            _excludedRecipeIdsByKey[key] = set;
        }

        if (excluded)
        {
            set.Add(recipeId);
        }
        else
        {
            set.Remove(recipeId);
            if (set.Count == 0)
            {
                _excludedRecipeIdsByKey.Remove(key);
            }
        }

        await PersistAsync();
    }

    private async Task PersistAsync()
    {
        try
        {
            await localStorage.SetAsync(
                StorageKey,
                new PreferencesDto(
                    _excludedRecipeIdsByKey.ToDictionary(
                        kvp => kvp.Key,
                        kvp => kvp.Value.OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToArray(),
                        StringComparer.OrdinalIgnoreCase)));
        }
        catch
        {
        }
    }

    private static string GetKey(GameVersion version, int professionId) => $"{version}:{professionId}";

    private sealed record PreferencesDto(Dictionary<string, string[]>? ExcludedRecipeIdsByKey);
}

