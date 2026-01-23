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

        return app;
    }

    public sealed record PlanApiRequest(
        Region Region,
        GameVersion GameVersion,
        string RealmSlug,
        int ProfessionId,
        int CurrentSkill,
        int TargetSkill,
        PriceMode PriceMode);
}

