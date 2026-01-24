namespace WowAhPlanner.Core.Services;

using System.Collections.Frozen;
using WowAhPlanner.Core.Domain;
using WowAhPlanner.Core.Domain.Planning;
using WowAhPlanner.Core.Ports;

public sealed class PlannerService(
    IRecipeRepository recipeRepository,
    IPriceService priceService,
    IVendorPriceRepository vendorPriceRepository,
    IProducerRepository producerRepository)
{
    private readonly SkillUpChanceModel _defaultChanceModel = new();

    public async Task<PlanComputationResult> BuildPlanAsync(PlanRequest request, CancellationToken cancellationToken)
    {
        if (request.TargetSkill <= request.CurrentSkill)
        {
            return new PlanComputationResult(
                Plan: new PlanResult([], [], [], Money.Zero, DateTime.UtcNow),
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
        var producers = await producerRepository.GetProducersAsync(gameVersion, cancellationToken);

        var directReagentItemIds =
            recipes.SelectMany(r => r.Reagents)
                .Select(r => r.ItemId)
                .Where(itemId => !vendorPrices.ContainsKey(itemId))
                .Distinct()
                .OrderBy(x => x)
                .ToArray();

        var smelt = ProducerIndex.Build(producers.Where(p => p.Kind == ProducerKind.Smelt));

        var allItemIds = directReagentItemIds.ToHashSet();
        if (request.UseSmeltIntermediates)
        {
            foreach (var itemId in directReagentItemIds)
            {
                AddSmeltClosureItemIds(itemId, smelt, allItemIds);
            }
        }

        var snapshot = await priceService.GetPricesAsync(
            request.RealmKey,
            allItemIds.OrderBy(x => x).ToArray(),
            request.PriceMode,
            cancellationToken);
        var priceByItemId = snapshot.Prices.ToFrozenDictionary(kvp => kvp.Key, kvp => kvp.Value);

        var craftables = CraftableIndex.Build(recipes);
        var resolver = new ReagentResolver(
            request.PriceMode,
            vendorPrices,
            priceByItemId,
            craftables,
            smelt,
            request.TargetSkill,
            request.UseCraftIntermediates,
            request.UseSmeltIntermediates);

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
        var intermediates = resolver.GetIntermediates();

        return new PlanComputationResult(
            Plan: new PlanResult(steps, intermediates, shoppingLines, total, DateTime.UtcNow),
            PriceSnapshot: snapshot,
            MissingItemIds: [],
            ErrorMessage: null);
    }

    private static void AddSmeltClosureItemIds(int itemId, ProducerIndex smelt, HashSet<int> into)
    {
        var visited = new HashSet<int>();
        AddSmeltClosureItemIdsInner(itemId, smelt, into, visited);
    }

    private static void AddSmeltClosureItemIdsInner(int itemId, ProducerIndex smelt, HashSet<int> into, HashSet<int> visited)
    {
        if (!visited.Add(itemId))
        {
            return;
        }

        into.Add(itemId);

        if (!smelt.TryGetProducers(itemId, out var producers))
        {
            return;
        }

        foreach (var producer in producers)
        {
            foreach (var reagent in producer.Reagents)
            {
                AddSmeltClosureItemIdsInner(reagent.ItemId, smelt, into, visited);
            }
        }
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
            if (recipe.CooldownSeconds is int cd && cd > 0) continue;
            if (recipe.OutputQuality is int q && q >= 3) continue;

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
        CraftableIndex craftables,
        ProducerIndex smelt,
        int craftabilitySkillCap,
        bool useCraftIntermediates,
        bool useSmeltIntermediates)
    {
        private readonly int _craftabilitySkillCap = craftabilitySkillCap;
        private readonly bool _useCraftIntermediates = useCraftIntermediates;
        private readonly bool _useSmeltIntermediates = useSmeltIntermediates;
        private readonly Dictionary<(int itemId, int skill), Money> _unitCostCache = new();
        private readonly Dictionary<(int itemId, int skill), (Recipe recipe, int outputQty)> _craftProducerCache = new();
        private readonly Dictionary<(int itemId, int skill), (Producer producer, int outputQty)> _smeltProducerCache = new();
        private readonly Dictionary<(int itemId, ProducerKind kind, string producerName), decimal> _intermediates = new();

        public IReadOnlyList<IntermediateLine> GetIntermediates() =>
            _intermediates
                .OrderBy(kvp => kvp.Key.kind)
                .ThenBy(kvp => kvp.Key.itemId)
                .ThenBy(kvp => kvp.Key.producerName, StringComparer.OrdinalIgnoreCase)
                .Select(kvp => new IntermediateLine(kvp.Key.itemId, kvp.Value, kvp.Key.kind, kvp.Key.producerName))
                .ToArray();

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

                var hasEligibleProducer = false;
                if (_useCraftIntermediates &&
                    TryGetBestCraftProducer(itemId, skill, missing, visiting, out hasEligibleProducer, out var producer, out var outputQty, out var perUnitCost))
                {
                    _craftProducerCache[(itemId, skill)] = (producer, outputQty);
                    unitCost = perUnitCost;
                    _unitCostCache[(itemId, skill)] = unitCost;
                    return true;
                }

                if (_useCraftIntermediates && hasEligibleProducer)
                {
                    unitCost = Money.Zero;
                    return false;
                }

                var hasBuy = prices.TryGetValue(itemId, out var summary);
                var buyCost = hasBuy ? GetUnitPrice(priceMode, summary!) : (Money?)null;

                if (_useSmeltIntermediates &&
                    TryGetBestSmeltProducer(itemId, skill, missing, visiting, out var smeltProducer, out var smeltOutputQty, out var smeltPerUnit))
                {
                    if (!hasBuy || smeltPerUnit.Copper < buyCost!.Value.Copper)
                    {
                        _smeltProducerCache[(itemId, skill)] = (smeltProducer, smeltOutputQty);
                        unitCost = smeltPerUnit;
                        _unitCostCache[(itemId, skill)] = unitCost;
                        return true;
                    }
                }

                if (!hasBuy)
                {
                    missing.Add(itemId);
                    unitCost = Money.Zero;
                    return false;
                }

                unitCost = buyCost!.Value;
                _unitCostCache[(itemId, skill)] = unitCost;
                return true;
            }
            finally
            {
                visiting.Remove(itemId);
            }
        }

        private bool TryGetBestCraftProducer(
            int itemId,
            int skill,
            HashSet<int> missing,
            HashSet<int> visiting,
            out bool hasEligibleProducer,
            out Recipe producer,
            out int outputQty,
            out Money perUnitCost)
        {
            producer = null!;
            outputQty = 0;
            perUnitCost = Money.Zero;
            hasEligibleProducer = false;

            if (!craftables.TryGetProducers(itemId, out var candidates))
            {
                return false;
            }

            Money? bestCost = null;

            foreach (var recipe in candidates)
            {
                if (recipe.MinSkill > _craftabilitySkillCap) continue;
                if (recipe.Output is null) continue;
                if (recipe.Output.ItemId != itemId) continue;

                hasEligibleProducer = true;

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

        private bool TryGetBestSmeltProducer(
            int itemId,
            int skill,
            HashSet<int> missing,
            HashSet<int> visiting,
            out Producer producer,
            out int outputQty,
            out Money perUnitCost)
        {
            producer = null!;
            outputQty = 0;
            perUnitCost = Money.Zero;

            if (!smelt.TryGetProducers(itemId, out var candidates))
            {
                return false;
            }

            Money? bestCost = null;

            foreach (var p in candidates)
            {
                if (p.Output.ItemId != itemId) continue;

                var qty = p.Output.Quantity <= 0 ? 1 : p.Output.Quantity;

                var cost = Money.Zero;
                var failed = false;

                foreach (var reagent in p.Reagents)
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
                    producer = p;
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
                if (_useCraftIntermediates)
                {
                    if (!_craftProducerCache.TryGetValue((itemId, skill), out var craftCached))
                    {
                        if (TryGetBestCraftProducer(itemId, skill, missing, visiting, out var hasEligibleProducer, out var producer, out var outputQty, out _))
                        {
                            craftCached = (producer, outputQty);
                            _craftProducerCache[(itemId, skill)] = craftCached;
                        }
                        else if (hasEligibleProducer)
                        {
                            return;
                        }
                    }

                    if (craftCached.recipe is not null)
                    {
                        AddIntermediate(itemId, quantity, ProducerKind.Craft, craftCached.recipe.Name);
                        var crafts = quantity / craftCached.outputQty;
                        foreach (var reagent in craftCached.recipe.Reagents)
                        {
                            AddShoppingForItem(shopping, reagent.ItemId, reagent.Quantity * crafts, skill, missing, visiting);
                        }
                        return;
                    }
                }

                if (_useSmeltIntermediates)
                {
                    _ = TryGetUnitCost(itemId, skill, missing, visiting, out _);
                    if (_smeltProducerCache.TryGetValue((itemId, skill), out var smeltCached))
                    {
                        AddIntermediate(itemId, quantity, ProducerKind.Smelt, smeltCached.producer.Name);
                        var crafts = quantity / smeltCached.outputQty;
                        foreach (var reagent in smeltCached.producer.Reagents)
                        {
                            AddShoppingForItem(shopping, reagent.ItemId, reagent.Quantity * crafts, skill, missing, visiting);
                        }
                        return;
                    }
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

        private void AddIntermediate(int itemId, decimal quantity, ProducerKind kind, string producerName)
        {
            var key = (itemId, kind, producerName);
            if (_intermediates.TryGetValue(key, out var existing))
            {
                _intermediates[key] = existing + quantity;
            }
            else
            {
                _intermediates[key] = quantity;
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

    private sealed class ProducerIndex(IReadOnlyDictionary<int, IReadOnlyList<Producer>> byOutputItemId)
    {
        public static ProducerIndex Build(IEnumerable<Producer> producers)
        {
            var dict = new Dictionary<int, List<Producer>>();

            foreach (var p in producers)
            {
                if (p.Output.ItemId <= 0) continue;
                if (p.Output.Quantity <= 0) continue;

                if (!dict.TryGetValue(p.Output.ItemId, out var list))
                {
                    list = new List<Producer>();
                    dict[p.Output.ItemId] = list;
                }

                list.Add(p);
            }

            return new ProducerIndex(dict.ToDictionary(kvp => kvp.Key, kvp => (IReadOnlyList<Producer>)kvp.Value.ToArray()));
        }

        public bool TryGetProducers(int itemId, out IReadOnlyList<Producer> producers) =>
            byOutputItemId.TryGetValue(itemId, out producers!);
    }
}
