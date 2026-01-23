namespace WowAhPlanner.Core.Services;

using System.Collections.Frozen;
using WowAhPlanner.Core.Domain;
using WowAhPlanner.Core.Domain.Planning;
using WowAhPlanner.Core.Ports;

public sealed class PlannerService(IRecipeRepository recipeRepository, IPriceService priceService)
{
    private readonly SkillUpChanceModel _defaultChanceModel = new();

    public async Task<PlanComputationResult> BuildPlanAsync(PlanRequest request, CancellationToken cancellationToken)
    {
        if (request.TargetSkill <= request.CurrentSkill)
        {
            return new PlanComputationResult(
                Plan: new PlanResult([], [], Money.Zero, DateTime.UtcNow),
                PriceSnapshot: new PriceSnapshot(
                    request.RealmKey,
                    ProviderName: "n/a",
                    SnapshotTimestampUtc: DateTime.UtcNow,
                    IsStale: true,
                    ErrorMessage: "No planning needed (target <= current).",
                    Prices: new Dictionary<int, PriceSummary>()),
                MissingItemIds: [],
                ErrorMessage: null);
        }

        var gameVersion = request.RealmKey.GameVersion;
        var recipes = await recipeRepository.GetRecipesAsync(gameVersion, request.ProfessionId, cancellationToken);
        if (recipes.Count == 0)
        {
            return new PlanComputationResult(
                Plan: null,
                PriceSnapshot: new PriceSnapshot(
                    request.RealmKey,
                    ProviderName: "n/a",
                    SnapshotTimestampUtc: DateTime.UtcNow,
                    IsStale: true,
                    ErrorMessage: null,
                    Prices: new Dictionary<int, PriceSummary>()),
                MissingItemIds: [],
                ErrorMessage: $"No recipes found for professionId={request.ProfessionId} ({gameVersion}).");
        }

        var allItemIds =
            recipes.SelectMany(r => r.Reagents)
                .Select(r => r.ItemId)
                .Distinct()
                .OrderBy(x => x)
                .ToArray();

        var snapshot = await priceService.GetPricesAsync(request.RealmKey, allItemIds, request.PriceMode, cancellationToken);
        var priceByItemId = snapshot.Prices.ToFrozenDictionary(kvp => kvp.Key, kvp => kvp.Value);

        var steps = new List<PlanStep>();
        var shopping = new Dictionary<int, decimal>();
        var missing = new HashSet<int>();

        for (var skill = request.CurrentSkill; skill < request.TargetSkill; skill++)
        {
            var best = FindBestRecipeAtSkill(recipes, skill, request.PriceMode, priceByItemId, missing);
            if (best is null)
            {
                return new PlanComputationResult(
                    Plan: null,
                    PriceSnapshot: snapshot,
                    MissingItemIds: missing.OrderBy(x => x).ToArray(),
                    ErrorMessage: $"No usable recipe with prices at skill {skill}.");
            }

            var (recipe, chance, craftCost, expectedCost, expectedCrafts) = best.Value;

            AddShopping(shopping, recipe, expectedCrafts);

            if (steps.Count > 0 &&
                steps[^1].RecipeId == recipe.RecipeId &&
                steps[^1].SkillUpChance == chance)
            {
                var prev = steps[^1];
                steps[^1] = prev with
                {
                    SkillTo = prev.SkillTo + 1,
                    ExpectedCrafts = prev.ExpectedCrafts + expectedCrafts,
                    ExpectedCost = prev.ExpectedCost + expectedCost,
                };
            }
            else
            {
                steps.Add(new PlanStep(
                    SkillFrom: skill,
                    SkillTo: skill + 1,
                    RecipeId: recipe.RecipeId,
                    RecipeName: recipe.Name,
                    SkillUpChance: chance,
                    ExpectedCrafts: expectedCrafts,
                    ExpectedCost: expectedCost));
            }
        }

        var shoppingLines = shopping
            .OrderBy(kvp => kvp.Key)
            .Select(kvp =>
            {
                var itemId = kvp.Key;
                var qty = kvp.Value;
                var unit = GetUnitPrice(request.PriceMode, priceByItemId[itemId]);
                var lineCost = unit * qty;
                return new ShoppingListLine(itemId, qty, unit, lineCost);
            })
            .ToArray();

        var total = shoppingLines.Aggregate(Money.Zero, (acc, line) => acc + line.LineCost);

        return new PlanComputationResult(
            Plan: new PlanResult(steps, shoppingLines, total, DateTime.UtcNow),
            PriceSnapshot: snapshot,
            MissingItemIds: [],
            ErrorMessage: null);
    }

    private (Recipe recipe, decimal chance, Money craftCost, Money expectedCost, decimal expectedCrafts)? FindBestRecipeAtSkill(
        IReadOnlyList<Recipe> recipes,
        int skill,
        PriceMode priceMode,
        FrozenDictionary<int, PriceSummary> prices,
        HashSet<int> missingItemIds)
    {
        (Recipe recipe, decimal chance, Money craftCost, Money expectedCost, decimal expectedCrafts)? best = null;

        foreach (var recipe in recipes)
        {
            if (skill < recipe.MinSkill) continue;

            var color = recipe.GetDifficultyAtSkill(skill);
            var p = _defaultChanceModel.GetChance(color);
            if (p <= 0) continue;

            if (!TryGetCraftCost(recipe, priceMode, prices, missingItemIds, out var craftCost))
            {
                continue;
            }

            var expectedCost = Money.FromCopperDecimal(craftCost.Copper / p);
            var expectedCrafts = 1m / p;

            if (best is null || expectedCost.Copper < best.Value.expectedCost.Copper)
            {
                best = (recipe, p, craftCost, expectedCost, expectedCrafts);
            }
        }

        return best;
    }

    private static bool TryGetCraftCost(
        Recipe recipe,
        PriceMode priceMode,
        FrozenDictionary<int, PriceSummary> prices,
        HashSet<int> missingItemIds,
        out Money craftCost)
    {
        craftCost = Money.Zero;

        foreach (var reagent in recipe.Reagents)
        {
            if (!prices.TryGetValue(reagent.ItemId, out var summary))
            {
                missingItemIds.Add(reagent.ItemId);
                return false;
            }

            var unit = GetUnitPrice(priceMode, summary);
            craftCost += unit * reagent.Quantity;
        }

        return true;
    }

    private static Money GetUnitPrice(PriceMode priceMode, PriceSummary summary) =>
        priceMode switch
        {
            PriceMode.Min => new Money(summary.MinBuyoutCopper),
            PriceMode.Median when summary.MedianCopper is long med => new Money(med),
            _ => new Money(summary.MinBuyoutCopper),
        };

    private static void AddShopping(Dictionary<int, decimal> shopping, Recipe recipe, decimal expectedCrafts)
    {
        foreach (var reagent in recipe.Reagents)
        {
            var qty = reagent.Quantity * expectedCrafts;
            if (shopping.TryGetValue(reagent.ItemId, out var existing))
            {
                shopping[reagent.ItemId] = existing + qty;
            }
            else
            {
                shopping[reagent.ItemId] = qty;
            }
        }
    }
}
