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
                new PlanRequest(realmKey, request.ProfessionId, request.CurrentSkill, request.TargetSkill, request.PriceMode),
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
            IRecipeRepository repo,
            IVendorPriceRepository vendorPriceRepository,
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

            var itemIds = new HashSet<int>();
            var vendorItemIds = (await vendorPriceRepository.GetVendorPricesAsync(v, ct)).Keys.ToHashSet();

            if (professionId is int pid)
            {
                var recipes = await repo.GetRecipesAsync(v, pid, ct);
                recipes = FilterRecipes(recipes, minSkill, maxSkill);
                foreach (var reagent in recipes.SelectMany(r => r.Reagents))
                {
                    if (vendorItemIds.Contains(reagent.ItemId)) continue;
                    itemIds.Add(reagent.ItemId);
                }
            }
            else
            {
                var professions = await repo.GetProfessionsAsync(v, ct);
                foreach (var prof in professions)
                {
                    var recipes = await repo.GetRecipesAsync(v, prof.ProfessionId, ct);
                    recipes = FilterRecipes(recipes, minSkill, maxSkill);
                    foreach (var reagent in recipes.SelectMany(r => r.Reagents))
                    {
                        if (vendorItemIds.Contains(reagent.ItemId)) continue;
                        itemIds.Add(reagent.ItemId);
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
            IRecipeRepository repo,
            IVendorPriceRepository vendorPriceRepository,
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

            var itemIds = new HashSet<int>();
            var vendorItemIds = (await vendorPriceRepository.GetVendorPricesAsync(v, ct)).Keys.ToHashSet();

            if (professionId is int pid)
            {
                var recipes = await repo.GetRecipesAsync(v, pid, ct);
                recipes = FilterRecipes(recipes, minSkill, maxSkill);
                foreach (var reagent in recipes.SelectMany(r => r.Reagents))
                {
                    if (vendorItemIds.Contains(reagent.ItemId)) continue;
                    itemIds.Add(reagent.ItemId);
                }
            }
            else
            {
                var professions = await repo.GetProfessionsAsync(v, ct);
                foreach (var prof in professions)
                {
                    var recipes = await repo.GetRecipesAsync(v, prof.ProfessionId, ct);
                    recipes = FilterRecipes(recipes, minSkill, maxSkill);
                    foreach (var reagent in recipes.SelectMany(r => r.Reagents))
                    {
                        if (vendorItemIds.Contains(reagent.ItemId)) continue;
                        itemIds.Add(reagent.ItemId);
                    }
                }
            }

            var content = $"-- Generated by WowAhPlanner\r\nWowAhPlannerScan_TargetItemIds = {{ {string.Join(", ", itemIds.OrderBy(x => x))} }}\r\n";
            return Results.Text(content, "text/plain");
        });

        api.MapGet("/scans/recipeTargets.lua", async (
            [FromQuery] string version,
            [FromQuery] int professionId,
            IRecipeRepository repo,
            IVendorPriceRepository vendorPriceRepository,
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

            var vendorItemIds = (await vendorPriceRepository.GetVendorPricesAsync(v, ct)).Keys.ToHashSet();
            return Results.Text(GenerateRecipeTargetsLua(professionId, professionName, recipes, vendorItemIds), "text/plain");
        });

        api.MapPost("/scans/installTargets", async (
            [FromBody] InstallTargetsRequest request,
            IRecipeRepository repo,
            IVendorPriceRepository vendorPriceRepository,
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

            var professionName = (await repo.GetProfessionsAsync(version, ct))
                .FirstOrDefault(p => p.ProfessionId == request.ProfessionId)
                ?.Name;

            var vendorItemIds = (await vendorPriceRepository.GetVendorPricesAsync(version, ct)).Keys.ToHashSet();
            var lua = GenerateRecipeTargetsLua(request.ProfessionId, professionName, recipes, vendorItemIds);

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

    private static string GenerateRecipeTargetsLua(int professionId, string? professionName, IReadOnlyList<Recipe> recipes, IReadOnlySet<int> vendorItemIds)
    {
        var allReagentItemIds = recipes
            .SelectMany(r => r.Reagents)
            .Select(r => r.ItemId)
            .Where(itemId => !vendorItemIds.Contains(itemId))
            .Distinct()
            .OrderBy(x => x)
            .ToArray();

        var lines = new List<string>
        {
            "-- Generated by WowAhPlanner",
            $"WowAhPlannerScan_TargetProfessionId = {professionId}",
            $"WowAhPlannerScan_TargetProfessionName = \"{EscapeLuaString(NormalizeProfessionName(professionName) ?? "")}\"",
            $"WowAhPlannerScan_TargetItemIds = {{ {string.Join(", ", allReagentItemIds)} }}",
            "WowAhPlannerScan_RecipeTargets = {",
        };

        foreach (var recipe in recipes.OrderBy(r => r.MinSkill).ThenBy(r => r.RecipeId))
        {
            var reagentIds = recipe.Reagents
                .Select(x => x.ItemId)
                .Where(itemId => !vendorItemIds.Contains(itemId))
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

    private static IReadOnlyList<Recipe> FilterRecipes(IReadOnlyList<Recipe> recipes, int? minSkill, int? maxSkill)
    {
        if (minSkill is null && maxSkill is null) return recipes;

        return recipes
            .Where(r =>
            {
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
        PriceMode PriceMode);

    public sealed record InstallTargetsRequest(GameVersion GameVersion, int ProfessionId);
}
