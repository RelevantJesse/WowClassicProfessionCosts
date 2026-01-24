namespace WowAhPlanner.Web.Api;

using Microsoft.AspNetCore.Mvc;
using WowAhPlanner.Core.Domain;
using WowAhPlanner.Core.Domain.Planning;
using WowAhPlanner.Core.Ports;
using WowAhPlanner.Core.Services;
using WowAhPlanner.Web.Services;

public static class ApiEndpoints
{
    public static WebApplication MapWowAhPlannerApi(this WebApplication app)
    {
        var api = app.MapGroup("/api");

        api.MapGet("/meta/gameversions", () =>
            Enum.GetValues<GameVersion>().Select(v => new { id = v.ToString(), name = v.ToString() }));

        api.MapGet("/meta/regions", () =>
            Enum.GetValues<Region>().Select(r => new { id = r.ToString(), name = r.ToString() }));

        api.MapGet("/realms", (
            [FromQuery] string region,
            [FromQuery] string version,
            RealmCatalog realms) =>
        {
            if (!Enum.TryParse<Region>(region, true, out var r))
            {
                return Results.BadRequest(new { message = $"Invalid region '{region}'." });
            }

            if (!Enum.TryParse<GameVersion>(version, true, out var v))
            {
                return Results.BadRequest(new { message = $"Invalid version '{version}'." });
            }

            return Results.Ok(realms.GetRealms(r, v).Select(x => new { slug = x.Slug, name = x.Name }));
        });

        api.MapGet("/professions", async (
            [FromQuery] string version,
            IRecipeRepository repo,
            CancellationToken ct) =>
        {
            if (!Enum.TryParse<GameVersion>(version, true, out var v))
            {
                return Results.BadRequest(new { message = $"Invalid version '{version}'." });
            }

            var professions = await repo.GetProfessionsAsync(v, ct);
            return Results.Ok(professions.Select(p => new { professionId = p.ProfessionId, name = p.Name }));
        });

        api.MapGet("/recipes", async (
            [FromQuery] string version,
            [FromQuery] int professionId,
            IRecipeRepository repo,
            CancellationToken ct) =>
        {
            if (!Enum.TryParse<GameVersion>(version, true, out var v))
            {
                return Results.BadRequest(new { message = $"Invalid version '{version}'." });
            }

            var recipes = await repo.GetRecipesAsync(v, professionId, ct);
            return Results.Ok(recipes);
        });

        api.MapPost("/plan", async (
            [FromBody] PlanApiRequest request,
            PlannerService planner,
            CancellationToken ct) =>
        {
            var realmKey = new RealmKey(request.Region, request.GameVersion, request.RealmSlug);
            var result = await planner.BuildPlanAsync(
                new PlanRequest(
                    realmKey,
                    request.ProfessionId,
                    request.CurrentSkill,
                    request.TargetSkill,
                    request.PriceMode,
                    request.UseCraftIntermediates ?? true,
                    request.UseSmeltIntermediates ?? true),
                ct);

            if (result.Plan is null)
            {
                return Results.BadRequest(new
                {
                    error = result.ErrorMessage,
                    missingItemIds = result.MissingItemIds,
                    pricing = new
                    {
                        providerName = result.PriceSnapshot.ProviderName,
                        snapshotTimestampUtc = result.PriceSnapshot.SnapshotTimestampUtc,
                        isStale = result.PriceSnapshot.IsStale,
                        errorMessage = result.PriceSnapshot.ErrorMessage,
                    },
                });
            }

            return Results.Ok(new
            {
                plan = result.Plan,
                pricing = new
                {
                    providerName = result.PriceSnapshot.ProviderName,
                    snapshotTimestampUtc = result.PriceSnapshot.SnapshotTimestampUtc,
                    isStale = result.PriceSnapshot.IsStale,
                    errorMessage = result.PriceSnapshot.ErrorMessage,
                },
            });
        });

        api.MapGet("/scans/targets", async (
            [FromQuery] string version,
            [FromQuery] int? professionId,
            [FromQuery] int? currentSkill,
            [FromQuery] int? maxSkillDelta,
            [FromQuery] bool? useCraftIntermediates,
            [FromQuery] bool? useSmeltIntermediates,
            IRecipeRepository repo,
            IVendorPriceRepository vendorPriceRepository,
            IProducerRepository producerRepository,
            CancellationToken ct) =>
        {
            if (!Enum.TryParse<GameVersion>(version, true, out var v))
            {
                return Results.BadRequest(new { message = $"Invalid version '{version}'." });
            }

            var minSkill = currentSkill;
            var maxSkill = currentSkill is int cs
                ? cs + Math.Max(0, maxSkillDelta ?? 100)
                : (int?)null;

            var useCraft = useCraftIntermediates ?? false;
            var useSmelt = useSmeltIntermediates ?? true;

            var itemIds = new HashSet<int>();
            var vendorItemIds = (await vendorPriceRepository.GetVendorPricesAsync(v, ct)).Keys.ToHashSet();
            var smelt = BuildSmeltProducerIndex(await producerRepository.GetProducersAsync(v, ct));
            var allCraftables = useCraft ? await BuildCraftableProducerIndexAllAsync(repo, v, ct) : null;

            if (professionId is int pid)
            {
                var recipes = await repo.GetRecipesAsync(v, pid, ct);
                var craftables = allCraftables ?? BuildCraftableProducerIndex(recipes);
                recipes = FilterRecipes(recipes, minSkill, maxSkill);
                foreach (var reagent in recipes.SelectMany(r => r.Reagents))
                {
                    foreach (var leaf in ExpandScanItemIds(reagent.ItemId, pid, craftables, smelt, vendorItemIds, useCraft, useSmelt))
                    {
                        itemIds.Add(leaf);
                    }
                }
            }
            else
            {
                var professions = await repo.GetProfessionsAsync(v, ct);
                foreach (var prof in professions)
                {
                    var recipes = await repo.GetRecipesAsync(v, prof.ProfessionId, ct);
                    var craftables = allCraftables ?? BuildCraftableProducerIndex(recipes);
                    recipes = FilterRecipes(recipes, minSkill, maxSkill);
                    foreach (var reagent in recipes.SelectMany(r => r.Reagents))
                    {
                        foreach (var leaf in ExpandScanItemIds(reagent.ItemId, prof.ProfessionId, craftables, smelt, vendorItemIds, useCraft, useSmelt))
                        {
                            itemIds.Add(leaf);
                        }
                    }
                }
            }

            return Results.Ok(itemIds.OrderBy(x => x).ToArray());
        });

        api.MapGet("/scans/targets.lua", async (
            [FromQuery] string version,
            [FromQuery] int? professionId,
            [FromQuery] int? currentSkill,
            [FromQuery] int? maxSkillDelta,
            [FromQuery] bool? useCraftIntermediates,
            [FromQuery] bool? useSmeltIntermediates,
            IRecipeRepository repo,
            IVendorPriceRepository vendorPriceRepository,
            IProducerRepository producerRepository,
            CancellationToken ct) =>
        {
            if (!Enum.TryParse<GameVersion>(version, true, out var v))
            {
                return Results.BadRequest(new { message = $"Invalid version '{version}'." });
            }

            var minSkill = currentSkill;
            var maxSkill = currentSkill is int cs
                ? cs + Math.Max(0, maxSkillDelta ?? 100)
                : (int?)null;

            var useCraft = useCraftIntermediates ?? false;
            var useSmelt = useSmeltIntermediates ?? true;

            var itemIds = new HashSet<int>();
            var vendorItemIds = (await vendorPriceRepository.GetVendorPricesAsync(v, ct)).Keys.ToHashSet();
            var smelt = BuildSmeltProducerIndex(await producerRepository.GetProducersAsync(v, ct));
            var allCraftables = useCraft ? await BuildCraftableProducerIndexAllAsync(repo, v, ct) : null;

            if (professionId is int pid)
            {
                var recipes = await repo.GetRecipesAsync(v, pid, ct);
                var craftables = allCraftables ?? BuildCraftableProducerIndex(recipes);
                recipes = FilterRecipes(recipes, minSkill, maxSkill);
                foreach (var reagent in recipes.SelectMany(r => r.Reagents))
                {
                    foreach (var leaf in ExpandScanItemIds(reagent.ItemId, pid, craftables, smelt, vendorItemIds, useCraft, useSmelt))
                    {
                        itemIds.Add(leaf);
                    }
                }
            }
            else
            {
                var professions = await repo.GetProfessionsAsync(v, ct);
                foreach (var prof in professions)
                {
                    var recipes = await repo.GetRecipesAsync(v, prof.ProfessionId, ct);
                    var craftables = allCraftables ?? BuildCraftableProducerIndex(recipes);
                    recipes = FilterRecipes(recipes, minSkill, maxSkill);
                    foreach (var reagent in recipes.SelectMany(r => r.Reagents))
                    {
                        foreach (var leaf in ExpandScanItemIds(reagent.ItemId, prof.ProfessionId, craftables, smelt, vendorItemIds, useCraft, useSmelt))
                        {
                            itemIds.Add(leaf);
                        }
                    }
                }
            }

            var content = $"-- Generated by WowAhPlanner\r\nWowAhPlannerScan_TargetItemIds = {{ {string.Join(", ", itemIds.OrderBy(x => x))} }}\r\n";
            return Results.Text(content, "text/plain");
        });

        api.MapGet("/scans/recipeTargets.lua", async (
            [FromQuery] string version,
            [FromQuery] int professionId,
            [FromQuery] bool? useCraftIntermediates,
            [FromQuery] bool? useSmeltIntermediates,
            [FromQuery] string? region,
            [FromQuery] string? realmSlug,
            IRecipeRepository repo,
            IVendorPriceRepository vendorPriceRepository,
            IProducerRepository producerRepository,
            CancellationToken ct) =>
        {
            if (!Enum.TryParse<GameVersion>(version, true, out var v))
            {
                return Results.BadRequest(new { message = $"Invalid version '{version}'." });
            }

            var professionName = (await repo.GetProfessionsAsync(v, ct))
                .FirstOrDefault(p => p.ProfessionId == professionId)
                ?.Name;

            var recipes = await repo.GetRecipesAsync(v, professionId, ct);
            if (recipes.Count == 0)
            {
                return Results.NotFound(new { message = $"No recipes found for professionId={professionId} ({v})." });
            }

            recipes = FilterRecipes(recipes, minSkill: null, maxSkill: null);

            var vendorItemIds = (await vendorPriceRepository.GetVendorPricesAsync(v, ct)).Keys.ToHashSet();
            var craftables = (useCraftIntermediates ?? false)
                ? await BuildCraftableProducerIndexAllAsync(repo, v, ct)
                : BuildCraftableProducerIndex(recipes);
            var smelt = BuildSmeltProducerIndex(await producerRepository.GetProducersAsync(v, ct));
            return Results.Text(
                GenerateRecipeTargetsLua(
                    professionId,
                    professionName,
                    recipes,
                    craftables,
                    smelt,
                    vendorItemIds,
                    useCraftIntermediates ?? false,
                    useSmeltIntermediates ?? true,
                    v,
                    region,
                    realmSlug),
                "text/plain");
        });

        api.MapPost("/scans/installTargets", async (
            [FromBody] InstallTargetsRequest request,
            IRecipeRepository repo,
            IVendorPriceRepository vendorPriceRepository,
            IProducerRepository producerRepository,
            WowAddonInstaller installer,
            CancellationToken ct) =>
        {
            var version = request.GameVersion;
            if (!installer.TryResolveAddonFolder(version, out var addonFolder, out var err))
            {
                return Results.BadRequest(new { message = err });
            }

            var recipes = await repo.GetRecipesAsync(version, request.ProfessionId, ct);
            if (recipes.Count == 0)
            {
                return Results.NotFound(new { message = $"No recipes found for professionId={request.ProfessionId} ({version})." });
            }

            recipes = FilterRecipes(recipes, minSkill: null, maxSkill: null);

            var professionName = (await repo.GetProfessionsAsync(version, ct))
                .FirstOrDefault(p => p.ProfessionId == request.ProfessionId)
                ?.Name;

            var vendorItemIds = (await vendorPriceRepository.GetVendorPricesAsync(version, ct)).Keys.ToHashSet();
            var craftables = request.UseCraftIntermediates
                ? await BuildCraftableProducerIndexAllAsync(repo, version, ct)
                : BuildCraftableProducerIndex(recipes);
            var smelt = BuildSmeltProducerIndex(await producerRepository.GetProducersAsync(version, ct));
            var lua = GenerateRecipeTargetsLua(
                request.ProfessionId,
                professionName,
                recipes,
                craftables,
                smelt,
                vendorItemIds,
                request.UseCraftIntermediates,
                request.UseSmeltIntermediates,
                version,
                request.Region?.ToString(),
                request.RealmSlug);

            var targetPath = Path.Combine(addonFolder, "WowAhPlannerScan_Targets.lua");
            try
            {
                File.WriteAllText(targetPath, lua);
            }
            catch (Exception ex)
            {
                return Results.Problem($"Failed to write {targetPath}: {ex.Message}");
            }

            return Results.Ok(new { message = $"Updated {targetPath}", addonFolder });
        });

        return app;
    }

    private static string EscapeLuaString(string value)
        => value.Replace("\\", "\\\\", StringComparison.Ordinal).Replace("\"", "\\\"", StringComparison.Ordinal);

    private static string GenerateRecipeTargetsLua(
        int professionId,
        string? professionName,
        IReadOnlyList<Recipe> recipes,
        IReadOnlyDictionary<int, Recipe> craftables,
        IReadOnlyDictionary<int, IReadOnlyList<Producer>> smelt,
        IReadOnlySet<int> vendorItemIds,
        bool useCraftIntermediates,
        bool useSmeltIntermediates,
        GameVersion gameVersion,
        string? region,
        string? realmSlug)
    {
        var allReagentItemIds = recipes
            .SelectMany(r => r.Reagents)
            .Select(r => r.ItemId)
            .SelectMany(itemId => ExpandScanItemIds(itemId, professionId, craftables, smelt, vendorItemIds, useCraftIntermediates, useSmeltIntermediates))
            .Distinct()
            .OrderBy(x => x)
            .ToArray();

        var lines = new List<string>
        {
            "-- Generated by WowAhPlanner",
            $"WowAhPlannerScan_TargetGameVersion = \"{EscapeLuaString(gameVersion.ToString())}\"",
            $"WowAhPlannerScan_TargetProfessionId = {professionId}",
            $"WowAhPlannerScan_TargetProfessionName = \"{EscapeLuaString(NormalizeProfessionName(professionName) ?? "")}\"",
            $"WowAhPlannerScan_VendorItemIds = {{ {string.Join(", ", vendorItemIds.OrderBy(x => x))} }}",
            $"WowAhPlannerScan_TargetItemIds = {{ {string.Join(", ", allReagentItemIds)} }}",
            "WowAhPlannerScan_RecipeTargets = {",
        };
        lines.RemoveAll(string.IsNullOrWhiteSpace);

        foreach (var recipe in recipes.OrderBy(r => r.MinSkill).ThenBy(r => r.RecipeId))
        {
            var reagentIds = recipe.Reagents
                .Select(x => x.ItemId)
                .SelectMany(itemId => ExpandScanItemIds(itemId, professionId, craftables, smelt, vendorItemIds, useCraftIntermediates, useSmeltIntermediates))
                .Distinct()
                .OrderBy(x => x)
                .ToArray();
            lines.Add(
                $"  {{ recipeId = \"{EscapeLuaString(recipe.RecipeId)}\", minSkill = {recipe.MinSkill}, grayAt = {recipe.GrayAt}, reagents = {{ {string.Join(", ", reagentIds)} }} }},");
        }

        lines.Add("}");
        lines.Add("");
        return string.Join("\r\n", lines);
    }

    private static string? NormalizeProfessionName(string? name)
    {
        if (string.IsNullOrWhiteSpace(name)) return null;
        var trimmed = name.Trim();
        var idx = trimmed.IndexOf('(');
        if (idx > 0) trimmed = trimmed[..idx].Trim();
        return trimmed;
    }

    private static IReadOnlyDictionary<int, Recipe> BuildCraftableProducerIndex(IReadOnlyList<Recipe> recipes)
    {
        var byOutput = new Dictionary<int, Recipe>();

        foreach (var recipe in recipes.OrderBy(r => r.MinSkill).ThenBy(r => r.RecipeId, StringComparer.OrdinalIgnoreCase))
        {
            var output = recipe.Output;
            if (output is null) continue;
            if (output.ItemId <= 0) continue;
            if (output.Quantity <= 0) continue;

            if (!byOutput.ContainsKey(output.ItemId))
            {
                byOutput[output.ItemId] = recipe;
            }
        }

        return byOutput;
    }

    private static async Task<IReadOnlyDictionary<int, Recipe>> BuildCraftableProducerIndexAllAsync(
        IRecipeRepository repo,
        GameVersion version,
        CancellationToken ct)
    {
        var professions = await repo.GetProfessionsAsync(version, ct);
        var all = new List<Recipe>();
        foreach (var prof in professions)
        {
            all.AddRange(await repo.GetRecipesAsync(version, prof.ProfessionId, ct));
        }

        var filtered = FilterRecipes(all, minSkill: null, maxSkill: null);
        return BuildCraftableProducerIndex(filtered);
    }

    private static IReadOnlyDictionary<int, IReadOnlyList<Producer>> BuildSmeltProducerIndex(IReadOnlyList<Producer> producers)
    {
        var byOutput = new Dictionary<int, List<Producer>>();

        foreach (var p in producers)
        {
            if (p.Kind != ProducerKind.Smelt) continue;
            if (p.Output.ItemId <= 0) continue;
            if (p.Output.Quantity <= 0) continue;

            if (!byOutput.TryGetValue(p.Output.ItemId, out var list))
            {
                list = new List<Producer>();
                byOutput[p.Output.ItemId] = list;
            }

            list.Add(p);
        }

        return byOutput.ToDictionary(kvp => kvp.Key, kvp => (IReadOnlyList<Producer>)kvp.Value.ToArray());
    }

    private static IEnumerable<int> ExpandScanItemIds(
        int itemId,
        int targetProfessionId,
        IReadOnlyDictionary<int, Recipe> craftables,
        IReadOnlyDictionary<int, IReadOnlyList<Producer>> smelt,
        IReadOnlySet<int> vendorItemIds,
        bool useCraftIntermediates,
        bool useSmeltIntermediates)
    {
        var visited = new HashSet<int>();
        var results = new HashSet<int>();
        ExpandScanItemIdsInner(itemId, targetProfessionId, craftables, smelt, vendorItemIds, useCraftIntermediates, useSmeltIntermediates, visited, results);
        return results;
    }

    private static void ExpandScanItemIdsInner(
        int itemId,
        int targetProfessionId,
        IReadOnlyDictionary<int, Recipe> craftables,
        IReadOnlyDictionary<int, IReadOnlyList<Producer>> smelt,
        IReadOnlySet<int> vendorItemIds,
        bool useCraftIntermediates,
        bool useSmeltIntermediates,
        HashSet<int> visited,
        HashSet<int> results)
    {
        if (vendorItemIds.Contains(itemId))
        {
            return;
        }

        if (!visited.Add(itemId))
        {
            results.Add(itemId);
            return;
        }

        try
        {
            if (craftables.TryGetValue(itemId, out var producerRecipe) &&
                (producerRecipe.ProfessionId == targetProfessionId || useCraftIntermediates))
            {
                foreach (var reagent in producerRecipe.Reagents)
                {
                    ExpandScanItemIdsInner(reagent.ItemId, targetProfessionId, craftables, smelt, vendorItemIds, useCraftIntermediates, useSmeltIntermediates, visited, results);
                }
                return;
            }

            if (useSmeltIntermediates && smelt.TryGetValue(itemId, out var producers))
            {
                results.Add(itemId);
                foreach (var producer in producers)
                {
                    foreach (var reagent in producer.Reagents)
                    {
                        ExpandScanItemIdsInner(reagent.ItemId, targetProfessionId, craftables, smelt, vendorItemIds, useCraftIntermediates, useSmeltIntermediates, visited, results);
                    }
                }
                return;
            }

            results.Add(itemId);
        }
        finally
        {
            visited.Remove(itemId);
        }
    }

    private static IReadOnlyList<Recipe> FilterRecipes(IReadOnlyList<Recipe> recipes, int? minSkill, int? maxSkill)
    {
        return recipes
            .Where(r =>
            {
                if (r.OutputQuality is int q && q >= 3) return false;
                if (minSkill is int min && r.GrayAt <= min) return false;
                if (maxSkill is int max && r.MinSkill > max) return false;
                return true;
            })
            .ToArray();
    }

    public sealed record PlanApiRequest(
        Region Region,
        GameVersion GameVersion,
        string RealmSlug,
        int ProfessionId,
        int CurrentSkill,
        int TargetSkill,
        PriceMode PriceMode,
        bool? UseCraftIntermediates,
        bool? UseSmeltIntermediates);

    public sealed record InstallTargetsRequest(
        GameVersion GameVersion,
        int ProfessionId,
        bool UseCraftIntermediates = true,
        bool UseSmeltIntermediates = true,
        Region? Region = null,
        string? RealmSlug = null);
}
