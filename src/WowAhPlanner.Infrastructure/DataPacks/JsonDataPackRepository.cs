namespace WowAhPlanner.Infrastructure.DataPacks;

using System.Text.Json;
using WowAhPlanner.Core.Domain;
using WowAhPlanner.Core.Ports;

public sealed class JsonDataPackRepository : IRecipeRepository, IItemRepository, IVendorPriceRepository
{
    private readonly Dictionary<GameVersion, IReadOnlyList<Profession>> _professionsByVersion = new();
    private readonly Dictionary<(GameVersion Version, int ProfessionId), IReadOnlyList<Recipe>> _recipes = new();
    private readonly Dictionary<GameVersion, IReadOnlyDictionary<int, string>> _itemsByVersion = new();
    private readonly Dictionary<GameVersion, IReadOnlyDictionary<int, long>> _vendorPricesByVersion = new();

    public JsonDataPackRepository(DataPackOptions options)
    {
        LoadAll(options.RootPath);
    }

    public Task<IReadOnlyList<Profession>> GetProfessionsAsync(GameVersion gameVersion, CancellationToken cancellationToken)
    {
        _professionsByVersion.TryGetValue(gameVersion, out var professions);
        professions ??= [];
        return Task.FromResult(professions);
    }

    public Task<IReadOnlyList<Recipe>> GetRecipesAsync(GameVersion gameVersion, int professionId, CancellationToken cancellationToken)
    {
        _recipes.TryGetValue((gameVersion, professionId), out var recipes);
        recipes ??= [];
        return Task.FromResult(recipes);
    }

    public Task<IReadOnlyDictionary<int, string>> GetItemsAsync(GameVersion gameVersion, CancellationToken cancellationToken)
    {
        _itemsByVersion.TryGetValue(gameVersion, out var items);
        items ??= new Dictionary<int, string>();
        return Task.FromResult(items);
    }

    public async Task<string?> GetItemNameAsync(GameVersion gameVersion, int itemId, CancellationToken cancellationToken)
    {
        var items = await GetItemsAsync(gameVersion, cancellationToken);
        return items.TryGetValue(itemId, out var name) ? name : null;
    }

    public Task<IReadOnlyDictionary<int, long>> GetVendorPricesAsync(GameVersion gameVersion, CancellationToken cancellationToken)
    {
        _vendorPricesByVersion.TryGetValue(gameVersion, out var vendor);
        vendor ??= new Dictionary<int, long>();
        return Task.FromResult(vendor);
    }

    public async Task<long?> GetVendorPriceCopperAsync(GameVersion gameVersion, int itemId, CancellationToken cancellationToken)
    {
        var vendor = await GetVendorPricesAsync(gameVersion, cancellationToken);
        return vendor.TryGetValue(itemId, out var v) ? v : null;
    }

    private void LoadAll(string rootPath)
    {
        if (!Directory.Exists(rootPath))
        {
            throw new DataPackValidationException($"Data pack root not found: {rootPath}");
        }

        foreach (var versionDir in Directory.EnumerateDirectories(rootPath))
        {
            var name = Path.GetFileName(versionDir);
            if (!Enum.TryParse<GameVersion>(name, ignoreCase: true, out var version))
            {
                continue;
            }

            var (items, vendorPrices) = LoadItems(versionDir);
            _itemsByVersion[version] = items;
            _vendorPricesByVersion[version] = vendorPrices;

            var professionsDir = Path.Combine(versionDir, "professions");
            if (!Directory.Exists(professionsDir))
            {
                _professionsByVersion[version] = [];
                continue;
            }

            var professions = new List<Profession>();

            foreach (var professionFile in Directory.EnumerateFiles(professionsDir, "*.json", SearchOption.TopDirectoryOnly))
            {
                var pack = LoadProfessionPack(professionFile, _itemsByVersion[version]);
                professions.Add(new Profession(pack.ProfessionId, pack.ProfessionName!));
                _recipes[(version, pack.ProfessionId)] = pack.RecipesDomain;
            }

            _professionsByVersion[version] = professions.OrderBy(p => p.ProfessionId).ToArray();
        }
    }

    private static (IReadOnlyDictionary<int, string> Items, IReadOnlyDictionary<int, long> VendorPrices) LoadItems(string versionDir)
    {
        var path = Path.Combine(versionDir, "items.json");
        if (!File.Exists(path))
        {
            throw new DataPackValidationException($"Missing items.json in {versionDir}");
        }

        try
        {
            var json = File.ReadAllText(path);
            var items = JsonSerializer.Deserialize<List<ItemDto>>(json, JsonDefaults.Options);
            if (items is null || items.Count == 0)
            {
                throw new DataPackValidationException($"items.json is empty/invalid in {versionDir}");
            }

            var dict = new Dictionary<int, string>();
            var vendor = new Dictionary<int, long>();
            foreach (var item in items)
            {
                if (item.ItemId <= 0) throw new DataPackValidationException($"Invalid itemId in {path}.");
                if (string.IsNullOrWhiteSpace(item.Name)) throw new DataPackValidationException($"Missing item name in {path} (itemId={item.ItemId}).");
                dict[item.ItemId] = item.Name!;

                if (item.VendorPriceCopper is long v)
                {
                    if (v < 0) throw new DataPackValidationException($"Invalid vendorPriceCopper in {path} (itemId={item.ItemId}).");
                    vendor[item.ItemId] = v;
                }
            }

            return (dict, vendor);
        }
        catch (JsonException ex)
        {
            throw new DataPackValidationException($"Invalid JSON in {path}: {ex.Message}");
        }
    }

    private static ProfessionPack LoadProfessionPack(string path, IReadOnlyDictionary<int, string> items)
    {
        try
        {
            var json = File.ReadAllText(path);
            var pack = JsonSerializer.Deserialize<ProfessionPack>(json, JsonDefaults.Options);
            if (pack is null)
            {
                throw new DataPackValidationException($"Invalid JSON (null) in {path}");
            }

            pack.Validate(path);

            foreach (var outItemId in pack.RecipesDomain.Select(r => r.Output?.ItemId).OfType<int>().Distinct())
            {
                if (!items.ContainsKey(outItemId))
                {
                    throw new DataPackValidationException($"Unknown output itemId {outItemId} in {path} (missing from items.json).");
                }
            }

            foreach (var itemId in pack.RecipesDomain.SelectMany(r => r.Reagents).Select(r => r.ItemId).Distinct())
            {
                if (!items.ContainsKey(itemId))
                {
                    throw new DataPackValidationException($"Unknown reagent itemId {itemId} in {path} (missing from items.json).");
                }
            }

            foreach (var recipe in pack.RecipesDomain)
            {
                if (recipe.ProfessionId != pack.ProfessionId)
                {
                    throw new DataPackValidationException($"Recipe professionId mismatch in {path} (recipeId={recipe.RecipeId}).");
                }
            }

            return pack;
        }
        catch (JsonException ex)
        {
            throw new DataPackValidationException($"Invalid JSON in {path}: {ex.Message}");
        }
    }

    private static class JsonDefaults
    {
        public static readonly JsonSerializerOptions Options = new()
        {
            PropertyNameCaseInsensitive = true,
            ReadCommentHandling = JsonCommentHandling.Skip,
            AllowTrailingCommas = true,
        };
    }

    private sealed class ItemDto
    {
        public int ItemId { get; set; }
        public string? Name { get; set; }
        public long? VendorPriceCopper { get; set; }
    }

    private sealed class ProfessionPack
    {
        public int ProfessionId { get; set; }
        public string? ProfessionName { get; set; }
        public List<RecipeDto>? Recipes { get; set; }

        public IReadOnlyList<Recipe> RecipesDomain =>
            (Recipes ?? []).Select(r => r.ToDomain()).ToArray();

        public void Validate(string path)
        {
            if (ProfessionId <= 0) throw new DataPackValidationException($"Missing/invalid professionId in {path}.");
            if (string.IsNullOrWhiteSpace(ProfessionName)) throw new DataPackValidationException($"Missing professionName in {path}.");
            if (Recipes is null || Recipes.Count == 0) throw new DataPackValidationException($"Missing recipes[] in {path}.");

            var ids = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var recipe in Recipes)
            {
                recipe.Validate(path);
                if (!ids.Add(recipe.RecipeId!))
                {
                    throw new DataPackValidationException($"Duplicate recipeId '{recipe.RecipeId}' in {path}.");
                }
            }
        }
    }

    private sealed class RecipeDto
    {
        public string? RecipeId { get; set; }
        public int ProfessionId { get; set; }
        public string? Name { get; set; }
        public int? CreatesItemId { get; set; }
        public int? CreatesQuantity { get; set; }
        public bool? LearnedByTrainer { get; set; }
        public int MinSkill { get; set; }
        public int OrangeUntil { get; set; }
        public int YellowUntil { get; set; }
        public int GreenUntil { get; set; }
        public int GrayAt { get; set; }
        public List<ReagentDto>? Reagents { get; set; }

        public void Validate(string path)
        {
            if (string.IsNullOrWhiteSpace(RecipeId)) throw new DataPackValidationException($"Missing recipeId in {path}.");
            if (ProfessionId <= 0) throw new DataPackValidationException($"Missing/invalid professionId in {path} (recipeId={RecipeId}).");
            if (string.IsNullOrWhiteSpace(Name)) throw new DataPackValidationException($"Missing name in {path} (recipeId={RecipeId}).");
            if (CreatesItemId is int createsId && createsId <= 0) throw new DataPackValidationException($"Invalid createsItemId in {path} (recipeId={RecipeId}).");
            if (CreatesItemId is int && CreatesQuantity is int q && q <= 0) throw new DataPackValidationException($"Invalid createsQuantity in {path} (recipeId={RecipeId}).");
            if (MinSkill < 0) throw new DataPackValidationException($"Invalid minSkill in {path} (recipeId={RecipeId}).");
            if (OrangeUntil < MinSkill) throw new DataPackValidationException($"Invalid orangeUntil in {path} (recipeId={RecipeId}).");
            if (YellowUntil < OrangeUntil) throw new DataPackValidationException($"Invalid yellowUntil in {path} (recipeId={RecipeId}).");
            if (GreenUntil < YellowUntil) throw new DataPackValidationException($"Invalid greenUntil in {path} (recipeId={RecipeId}).");
            if (GrayAt <= GreenUntil) throw new DataPackValidationException($"Invalid grayAt in {path} (recipeId={RecipeId}).");
            if (Reagents is null || Reagents.Count == 0) throw new DataPackValidationException($"Missing reagents[] in {path} (recipeId={RecipeId}).");

            foreach (var reagent in Reagents)
            {
                reagent.Validate(path, RecipeId);
            }
        }

        public Recipe ToDomain() => new(
            RecipeId: RecipeId!,
            ProfessionId: ProfessionId,
            Name: Name!,
            MinSkill: MinSkill,
            OrangeUntil: OrangeUntil,
            YellowUntil: YellowUntil,
            GreenUntil: GreenUntil,
            GrayAt: GrayAt,
            Reagents: (Reagents ?? []).Select(r => r.ToDomain()).ToArray(),
            LearnedByTrainer: LearnedByTrainer,
            Output: CreatesItemId is int itemId && itemId > 0
                ? new RecipeOutput(itemId, CreatesQuantity is int q && q > 0 ? q : 1)
                : null);
    }

    private sealed class ReagentDto
    {
        public int ItemId { get; set; }
        public int Qty { get; set; }

        public void Validate(string path, string? recipeId)
        {
            if (ItemId <= 0) throw new DataPackValidationException($"Invalid reagent itemId in {path} (recipeId={recipeId}).");
            if (Qty <= 0) throw new DataPackValidationException($"Invalid reagent qty in {path} (recipeId={recipeId}, itemId={ItemId}).");
        }

        public Reagent ToDomain() => new(ItemId, Qty);
    }
}
