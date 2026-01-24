namespace WowAhPlanner.Core.Services;

using System.Collections.Frozen;
using WowAhPlanner.Core.Domain;
using WowAhPlanner.Core.Domain.Planning;
using WowAhPlanner.Core.Ports;

public sealed class PlannerService(
    IRecipeRepository recipeRepository,
    IPriceService priceService,
    IVendorPriceRepository vendorPriceRepository)
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

        var vendorPrices = await vendorPriceRepository.GetVendorPricesAsync(gameVersion, cancellationToken);

        var allItemIds =
            recipes.SelectMany(r => r.Reagents)
                .Select(r => r.ItemId)
                .Where(itemId => !vendorPrices.ContainsKey(itemId))
                .Distinct()
                .OrderBy(x => x)
                .ToArray();

        var snapshot = await priceService.GetPricesAsync(request.RealmKey, allItemIds, request.PriceMode, cancellationToken);
        var priceByItemId = snapshot.Prices.ToFrozenDictionary(kvp => kvp.Key, kvp => kvp.Value);

        var craftables = CraftableIndex.Build(recipes);
        var resolver = new ReagentResolver(request.PriceMode, vendorPrices, priceByItemId, craftables);

        var steps = new List<PlanStep>();
        var shopping = new Dictionary<int, decimal>();

        var missingAcrossPlan = new HashSet<int>();

        for (var skill = request.CurrentSkill; skill < request.TargetSkill; skill++)
        {
            var best = FindBestRecipeAtSkill(recipes, skill, resolver, out var missingAtSkill);
            if (best is null)
            {
                foreach (var itemId in missingAtSkill) missingAcrossPlan.Add(itemId);

                return new PlanComputationResult(
                    Plan: null,
                    PriceSnapshot: snapshot,
                    MissingItemIds: missingAcrossPlan.OrderBy(x => x).ToArray(),
                    ErrorMessage: $"No usable recipe with prices at skill {skill}.");
            }

            var (recipe, chance, craftCost, expectedCost, expectedCrafts) = best.Value;

            resolver.AddShoppingExpanded(shopping, recipe, expectedCrafts, skill);

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
                    LearnedByTrainer: recipe.LearnedByTrainer,
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

                Money unit;
                if (vendorPrices.TryGetValue(itemId, out var vendorCopper))
                {
                    unit = new Money(vendorCopper);
                }
                else if (priceByItemId.TryGetValue(itemId, out var summary))
                {
                    unit = GetUnitPrice(request.PriceMode, summary);
                }
                else
                {
                    unit = Money.Zero;
                }

                return new ShoppingListLine(itemId, qty, unit, unit * qty);
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
        ReagentResolver resolver,
        out int[] missingItemIds)
    {
        var missing = new HashSet<int>();
        (Recipe recipe, decimal chance, Money craftCost, Money expectedCost, decimal expectedCrafts)? best = null;

        foreach (var recipe in recipes)
        {
            if (skill < recipe.MinSkill) continue;

            var color = recipe.GetDifficultyAtSkill(skill);
            var p = _defaultChanceModel.GetChance(color);
            if (p <= 0) continue;

            if (!resolver.TryGetCraftCost(recipe, skill, out var craftCost, out var missingForRecipe))
            {
                foreach (var itemId in missingForRecipe) missing.Add(itemId);
                continue;
            }

            var expectedCost = Money.FromCopperDecimal(craftCost.Copper / p);
            var expectedCrafts = 1m / p;

            if (best is null || expectedCost.Copper < best.Value.expectedCost.Copper)
            {
                best = (recipe, p, craftCost, expectedCost, expectedCrafts);
            }
        }

        missingItemIds = missing.OrderBy(x => x).ToArray();
        return best;
    }

    private static Money GetUnitPrice(PriceMode priceMode, PriceSummary summary) =>
        priceMode switch
        {
            PriceMode.Min => new Money(summary.MinBuyoutCopper),
            PriceMode.Median when summary.MedianCopper is long med => new Money(med),
            _ => new Money(summary.MinBuyoutCopper),
        };

    private sealed class ReagentResolver(
        PriceMode priceMode,
        IReadOnlyDictionary<int, long> vendorPrices,
        FrozenDictionary<int, PriceSummary> prices,
        CraftableIndex craftables)
    {
        private readonly Dictionary<(int itemId, int skill), Money> _unitCostCache = new();
        private readonly Dictionary<(int itemId, int skill), (Recipe recipe, int outputQty)> _producerCache = new();

        public bool TryGetCraftCost(Recipe recipe, int skill, out Money craftCost, out int[] missingItemIds)
        {
            var missing = new HashSet<int>();
            var visiting = new HashSet<int>();

            craftCost = Money.Zero;

            foreach (var reagent in recipe.Reagents)
            {
                if (!TryGetUnitCost(reagent.ItemId, skill, missing, visiting, out var unit))
                {
                    missingItemIds = missing.OrderBy(x => x).ToArray();
                    return false;
                }

                craftCost += unit * reagent.Quantity;
            }

            missingItemIds = [];
            return true;
        }

        public void AddShoppingExpanded(Dictionary<int, decimal> shopping, Recipe recipe, decimal expectedCrafts, int skill)
        {
            var missing = new HashSet<int>();
            var visiting = new HashSet<int>();

            foreach (var reagent in recipe.Reagents)
            {
                AddShoppingForItem(shopping, reagent.ItemId, reagent.Quantity * expectedCrafts, skill, missing, visiting);
            }
        }

        private bool TryGetUnitCost(
            int itemId,
            int skill,
            HashSet<int> missing,
            HashSet<int> visiting,
            out Money unitCost)
        {
            if (_unitCostCache.TryGetValue((itemId, skill), out unitCost))
            {
                return true;
            }

            if (!visiting.Add(itemId))
            {
                missing.Add(itemId);
                unitCost = Money.Zero;
                return false;
            }

            try
            {
                if (vendorPrices.TryGetValue(itemId, out var vendorCopper))
                {
                    unitCost = new Money(vendorCopper);
                    _unitCostCache[(itemId, skill)] = unitCost;
                    return true;
                }

                if (TryGetBestProducer(itemId, skill, missing, visiting, out var producer, out var outputQty, out var perUnitCost))
                {
                    _producerCache[(itemId, skill)] = (producer, outputQty);
                    unitCost = perUnitCost;
                    _unitCostCache[(itemId, skill)] = unitCost;
                    return true;
                }

                if (!prices.TryGetValue(itemId, out var summary))
                {
                    missing.Add(itemId);
                    unitCost = Money.Zero;
                    return false;
                }

                unitCost = GetUnitPrice(priceMode, summary);
                _unitCostCache[(itemId, skill)] = unitCost;
                return true;
            }
            finally
            {
                visiting.Remove(itemId);
            }
        }

        private bool TryGetBestProducer(
            int itemId,
            int skill,
            HashSet<int> missing,
            HashSet<int> visiting,
            out Recipe producer,
            out int outputQty,
            out Money perUnitCost)
        {
            producer = null!;
            outputQty = 0;
            perUnitCost = Money.Zero;

            if (!craftables.TryGetProducers(itemId, out var candidates))
            {
                return false;
            }

            Money? bestCost = null;

            foreach (var recipe in candidates)
            {
                if (recipe.MinSkill > skill) continue;
                if (recipe.Output is null) continue;
                if (recipe.Output.ItemId != itemId) continue;

                var qty = recipe.Output.Quantity <= 0 ? 1 : recipe.Output.Quantity;

                var cost = Money.Zero;
                var failed = false;

                foreach (var reagent in recipe.Reagents)
                {
                    if (!TryGetUnitCost(reagent.ItemId, skill, missing, visiting, out var unit))
                    {
                        failed = true;
                        break;
                    }

                    cost += unit * reagent.Quantity;
                }

                if (failed) continue;

                var candidatePerUnit = Money.FromCopperDecimal(cost.Copper / (decimal)qty);
                if (bestCost is null || candidatePerUnit.Copper < bestCost.Value.Copper)
                {
                    bestCost = candidatePerUnit;
                    producer = recipe;
                    outputQty = qty;
                    perUnitCost = candidatePerUnit;
                }
            }

            return bestCost is not null;
        }

        private void AddShoppingForItem(
            Dictionary<int, decimal> shopping,
            int itemId,
            decimal quantity,
            int skill,
            HashSet<int> missing,
            HashSet<int> visiting)
        {
            if (vendorPrices.ContainsKey(itemId))
            {
                AddLeaf(shopping, itemId, quantity);
                return;
            }

            if (!visiting.Add(itemId))
            {
                missing.Add(itemId);
                return;
            }

            try
            {
                if (!_producerCache.TryGetValue((itemId, skill), out var cached))
                {
                    if (TryGetBestProducer(itemId, skill, missing, visiting, out var producer, out var outputQty, out _))
                    {
                        cached = (producer, outputQty);
                        _producerCache[(itemId, skill)] = cached;
                    }
                }

                if (cached.recipe is not null)
                {
                    var crafts = quantity / cached.outputQty;
                    foreach (var reagent in cached.recipe.Reagents)
                    {
                        AddShoppingForItem(shopping, reagent.ItemId, reagent.Quantity * crafts, skill, missing, visiting);
                    }
                    return;
                }

                if (!prices.ContainsKey(itemId))
                {
                    missing.Add(itemId);
                    return;
                }

                AddLeaf(shopping, itemId, quantity);
            }
            finally
            {
                visiting.Remove(itemId);
            }
        }

        private static void AddLeaf(Dictionary<int, decimal> shopping, int itemId, decimal quantity)
        {
            if (shopping.TryGetValue(itemId, out var existing))
            {
                shopping[itemId] = existing + quantity;
            }
            else
            {
                shopping[itemId] = quantity;
            }
        }
    }

    private sealed class CraftableIndex(IReadOnlyDictionary<int, IReadOnlyList<Recipe>> byOutputItemId)
    {
        public static CraftableIndex Build(IReadOnlyList<Recipe> recipes)
        {
            var dict = new Dictionary<int, List<Recipe>>();

            foreach (var recipe in recipes)
            {
                var output = recipe.Output;
                if (output is null) continue;
                if (output.ItemId <= 0) continue;
                if (output.Quantity <= 0) continue;

                if (!dict.TryGetValue(output.ItemId, out var list))
                {
                    list = new List<Recipe>();
                    dict[output.ItemId] = list;
                }

                list.Add(recipe);
            }

            return new CraftableIndex(dict.ToDictionary(kvp => kvp.Key, kvp => (IReadOnlyList<Recipe>)kvp.Value.ToArray()));
        }

        public bool TryGetProducers(int itemId, out IReadOnlyList<Recipe> recipes) =>
            byOutputItemId.TryGetValue(itemId, out recipes!);
    }
}
