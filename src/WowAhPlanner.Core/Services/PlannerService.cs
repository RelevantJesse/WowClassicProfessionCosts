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
                Plan: new PlanResult([], [], [], [], 0, 0m, Money.Zero, DateTime.UtcNow),
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

        var smelt = ProducerIndex.Build(producers.Where(p => p.Kind == ProducerKind.Smelt));

        IReadOnlyList<Recipe> craftableRecipes = recipes;
        if (request.UseCraftIntermediates)
        {
            var professions = await recipeRepository.GetProfessionsAsync(gameVersion, cancellationToken);
            var all = new List<Recipe>(recipes);
            foreach (var p in professions)
            {
                if (p.ProfessionId == request.ProfessionId) continue;
                var pr = await recipeRepository.GetRecipesAsync(gameVersion, p.ProfessionId, cancellationToken);
                all.AddRange(pr);
            }

            craftableRecipes = all;
        }

        var craftables = CraftableIndex.Build(craftableRecipes);

        var allItemIds = new HashSet<int>();
        foreach (var reagent in recipes.SelectMany(r => r.Reagents))
        {
            AddPricingClosureItemIds(
                itemId: reagent.ItemId,
                craftables: craftables,
                smelt: smelt,
                vendorPrices: vendorPrices,
                professionId: request.ProfessionId,
                useCrossProfessionCraftIntermediates: request.UseCraftIntermediates,
                useSmeltIntermediates: request.UseSmeltIntermediates,
                craftabilitySkillCap: request.TargetSkill,
                into: allItemIds,
                visiting: new HashSet<int>());
        }

        var snapshot = await priceService.GetPricesAsync(
            request.RealmKey,
            allItemIds.OrderBy(x => x).ToArray(),
            request.PriceMode,
            cancellationToken);
        var priceByItemId = snapshot.Prices.ToFrozenDictionary(kvp => kvp.Key, kvp => kvp.Value);

        var desiredSkillUps = request.TargetSkill - request.CurrentSkill;
        var startingSkill = request.CurrentSkill;
        var intermediateSteps = new List<PlanStep>();
        var skillCreditApplied = 0;
        var expectedSkillUpsFromIntermediates = 0m;
        var ownedUsedIntermediate = new List<OwnedMaterialLine>();
        Dictionary<int, decimal>? finalOwnedRemaining = null;

        (IReadOnlyList<PlanStep> MainSteps, Dictionary<int, decimal> Shopping, ReagentResolver Resolver)? final = null;

        for (var iter = 0; iter < 6; iter++)
        {
            var iterResolver = new ReagentResolver(
                request.PriceMode,
                vendorPrices,
                priceByItemId,
                craftables,
                smelt,
                request.TargetSkill,
                professionId: request.ProfessionId,
                useCrossProfessionCraftIntermediates: request.UseCraftIntermediates,
                request.UseSmeltIntermediates);

            if (!TryBuildStepsAndShopping(
                startSkill: startingSkill,
                targetSkill: request.TargetSkill,
                recipes: recipes,
                resolver: iterResolver,
                out var mainSteps,
                out var shopping,
                out var missingAcrossPlan,
                out var failedSkill))
            {
                return new PlanComputationResult(
                    Plan: null,
                    PriceSnapshot: snapshot,
                    MissingItemIds: missingAcrossPlan.OrderBy(x => x).ToArray(),
                    ErrorMessage: $"No usable recipe with prices at skill {failedSkill}.");
            }

            var inProfessionIntermediates = iterResolver.GetIntermediateCrafts()
                .Where(x => x.Recipe.ProfessionId == request.ProfessionId)
                .ToArray();

            var ownedRemaining = request.OwnedMaterials is { Count: > 0 }
                ? request.OwnedMaterials.ToDictionary(kvp => kvp.Key, kvp => (decimal)kvp.Value)
                : null;

            if (ownedRemaining is not null)
            {
                ownedUsedIntermediate.Clear();
                ApplyOwnedToIntermediateCrafts(
                    intermediateCrafts: inProfessionIntermediates,
                    resolver: iterResolver,
                    skillForExpansion: request.TargetSkill,
                    ownedRemaining: ownedRemaining,
                    ownedUsed: ownedUsedIntermediate,
                    shopping: shopping,
                    out inProfessionIntermediates);
            }

            (intermediateSteps, skillCreditApplied, expectedSkillUpsFromIntermediates) =
                BuildIntermediateSkillUpSteps(
                    currentSkill: request.CurrentSkill,
                    targetSkill: request.TargetSkill,
                    intermediateCrafts: inProfessionIntermediates,
                    resolver: iterResolver);

            var baseStartingSkill = request.CurrentSkill + skillCreditApplied;
            var newStartingSkill = Math.Max(startingSkill, baseStartingSkill);
            if (newStartingSkill == startingSkill)
            {
                final = (mainSteps, shopping, iterResolver);
                finalOwnedRemaining = ownedRemaining;
                break;
            }

            if (newStartingSkill < request.CurrentSkill || newStartingSkill > request.TargetSkill)
            {
                final = (mainSteps, shopping, iterResolver);
                finalOwnedRemaining = ownedRemaining;
                break;
            }

            startingSkill = newStartingSkill;
            final = (mainSteps, shopping, iterResolver);
            finalOwnedRemaining = ownedRemaining;
        }

        var finalMainSteps = final!.Value.MainSteps;
        var finalShopping = final!.Value.Shopping;
        var finalResolver = final!.Value.Resolver;

        var finalSteps = intermediateSteps.Concat(finalMainSteps).ToArray();

        var shoppingLines = finalShopping
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

        var ownedUsed = new List<OwnedMaterialLine>();
        ownedUsed.AddRange(ownedUsedIntermediate);

        if (finalOwnedRemaining is not null)
        {
            var adjusted = new List<ShoppingListLine>(shoppingLines.Length);

            foreach (var line in shoppingLines)
            {
                if (!finalOwnedRemaining.TryGetValue(line.ItemId, out var ownedQty) || ownedQty <= 0)
                {
                    adjusted.Add(line);
                    continue;
                }

                var used = Math.Min(line.Quantity, ownedQty);
                if (used > 0)
                {
                    ownedUsed.Add(new OwnedMaterialLine(line.ItemId, used));
                }

                var buyQty = line.Quantity - used;
                if (buyQty > 0)
                {
                    adjusted.Add(line with { Quantity = buyQty, LineCost = line.UnitPrice * buyQty });
                }
            }

            shoppingLines = adjusted.ToArray();
        }

        var total = shoppingLines.Aggregate(Money.Zero, (acc, line) => acc + line.LineCost);
        var intermediates = finalResolver.GetIntermediates();

        return new PlanComputationResult(
            Plan: new PlanResult(
                finalSteps,
                intermediates,
                shoppingLines,
                ownedUsed.OrderBy(x => x.ItemId).ToArray(),
                skillCreditApplied,
                expectedSkillUpsFromIntermediates,
                total,
                DateTime.UtcNow),
            PriceSnapshot: snapshot,
            MissingItemIds: [],
            ErrorMessage: null);
    }

    private void ApplyOwnedToIntermediateCrafts(
        IReadOnlyList<(Recipe Recipe, decimal Crafts)> intermediateCrafts,
        ReagentResolver resolver,
        int skillForExpansion,
        Dictionary<int, decimal> ownedRemaining,
        List<OwnedMaterialLine> ownedUsed,
        Dictionary<int, decimal> shopping,
        out (Recipe Recipe, decimal Crafts)[] adjustedCrafts)
    {
        var updated = new List<(Recipe Recipe, decimal Crafts)>(intermediateCrafts.Count);

        foreach (var (recipe, crafts) in intermediateCrafts)
        {
            if (crafts <= 0)
            {
                continue;
            }

            var output = recipe.Output;
            if (output is null || output.ItemId <= 0)
            {
                updated.Add((recipe, crafts));
                continue;
            }

            var outputQty = output.Quantity <= 0 ? 1 : output.Quantity;
            if (!ownedRemaining.TryGetValue(output.ItemId, out var ownedQty) || ownedQty <= 0)
            {
                updated.Add((recipe, crafts));
                continue;
            }

            var craftsCovered = Math.Min(crafts, ownedQty / outputQty);
            if (craftsCovered <= 0)
            {
                updated.Add((recipe, crafts));
                continue;
            }

            var usedOutputQty = craftsCovered * outputQty;
            ownedRemaining[output.ItemId] = ownedQty - usedOutputQty;
            ownedUsed.Add(new OwnedMaterialLine(output.ItemId, usedOutputQty));

            foreach (var reagent in recipe.Reagents)
            {
                var reductions = resolver.ExpandToLeafQuantities(reagent.ItemId, reagent.Quantity * craftsCovered, skillForExpansion);
                foreach (var kvp in reductions)
                {
                    if (!shopping.TryGetValue(kvp.Key, out var existing)) continue;
                    var next = existing - kvp.Value;
                    if (next <= 0)
                    {
                        shopping.Remove(kvp.Key);
                    }
                    else
                    {
                        shopping[kvp.Key] = next;
                    }
                }
            }

            var remainingCrafts = crafts - craftsCovered;
            if (remainingCrafts > 0)
            {
                updated.Add((recipe, remainingCrafts));
            }
        }

        adjustedCrafts = updated.ToArray();
    }

    private bool TryBuildStepsAndShopping(
        int startSkill,
        int targetSkill,
        IReadOnlyList<Recipe> recipes,
        ReagentResolver resolver,
        out IReadOnlyList<PlanStep> steps,
        out Dictionary<int, decimal> shopping,
        out HashSet<int> missingItemIds,
        out int failedAtSkill)
    {
        steps = [];
        shopping = new Dictionary<int, decimal>();
        missingItemIds = new HashSet<int>();
        failedAtSkill = startSkill;

        if (startSkill >= targetSkill)
        {
            steps = [];
            return true;
        }

        var list = new List<PlanStep>();

        for (var skill = startSkill; skill < targetSkill; skill++)
        {
            failedAtSkill = skill;
            var best = FindBestRecipeAtSkill(recipes, skill, resolver, out var missingAtSkill);
            if (best is null)
            {
                foreach (var itemId in missingAtSkill) missingItemIds.Add(itemId);
                return false;
            }

            var (recipe, chance, _, expectedCost, expectedCrafts) = best.Value;
            resolver.AddShoppingExpanded(shopping, recipe, expectedCrafts, skill);

            if (list.Count > 0 &&
                list[^1].RecipeId == recipe.RecipeId &&
                list[^1].SkillUpChance == chance)
            {
                var prev = list[^1];
                list[^1] = prev with
                {
                    SkillTo = prev.SkillTo + 1,
                    ExpectedCrafts = prev.ExpectedCrafts + expectedCrafts,
                    ExpectedCost = prev.ExpectedCost + expectedCost,
                };
            }
            else
            {
                list.Add(new PlanStep(
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

        steps = list;
        return true;
    }

    private (List<PlanStep> Steps, int SkillCreditApplied, decimal ExpectedSkillUps) BuildIntermediateSkillUpSteps(
        int currentSkill,
        int targetSkill,
        IReadOnlyList<(Recipe Recipe, decimal Crafts)> intermediateCrafts,
        ReagentResolver resolver)
    {
        var remaining = Math.Max(0, targetSkill - currentSkill);
        if (remaining == 0 || intermediateCrafts.Count == 0)
        {
            return ([], 0, 0m);
        }

        var skill = currentSkill;
        var credited = 0;
        var expectedSkillUps = 0m;
        var steps = new List<PlanStep>();

        var remainingByRecipeId = intermediateCrafts
            .Where(x => x.Crafts > 0)
            .GroupBy(x => x.Recipe.RecipeId, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(
                g => g.Key,
                g => (Recipe: g.First().Recipe, Crafts: g.Sum(x => x.Crafts)),
                StringComparer.OrdinalIgnoreCase);

        while (remaining > 0)
        {
            (Recipe Recipe, decimal CraftsLeft, decimal Chance, Money CraftCost, Money CostPerExpectedSkill)? best = null;

            foreach (var kvp in remainingByRecipeId)
            {
                var recipe = kvp.Value.Recipe;
                var craftsLeft = kvp.Value.Crafts;
                if (craftsLeft <= 0) continue;
                if (recipe.CooldownSeconds is int cd && cd > 0) continue;
                if (recipe.OutputQuality is int q && q >= 3) continue;
                if (skill < recipe.MinSkill) continue;

                var p = _defaultChanceModel.GetChance(recipe.GetDifficultyAtSkill(skill));
                if (p <= 0) continue;

                if (!resolver.TryGetCraftCost(recipe, skill, out var craftCost, out _))
                {
                    continue;
                }

                var costPerExpectedSkill = Money.FromCopperDecimal(craftCost.Copper / p);
                if (best is null || costPerExpectedSkill.Copper < best.Value.CostPerExpectedSkill.Copper)
                {
                    best = (recipe, craftsLeft, p, craftCost, costPerExpectedSkill);
                }
            }

            if (best is null)
            {
                break;
            }

            var craftsToMake = best.Value.CraftsLeft;
            var expectedHere = craftsToMake * best.Value.Chance;
            expectedSkillUps += expectedHere;

            var appliedHere = Math.Min(remaining, (int)decimal.Floor(expectedHere));

            steps.Add(new PlanStep(
                SkillFrom: skill,
                SkillTo: skill + appliedHere,
                RecipeId: best.Value.Recipe.RecipeId,
                RecipeName: $"{best.Value.Recipe.Name} (Intermediate)",
                LearnedByTrainer: best.Value.Recipe.LearnedByTrainer,
                SkillUpChance: best.Value.Chance,
                ExpectedCrafts: craftsToMake,
                ExpectedCost: best.Value.CraftCost * craftsToMake));

            credited += appliedHere;
            remaining -= appliedHere;
            skill += appliedHere;

            var key = best.Value.Recipe.RecipeId;
            remainingByRecipeId[key] = (best.Value.Recipe, 0m);
        }

        return (steps, credited, expectedSkillUps);
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

    private static void AddPricingClosureItemIds(
        int itemId,
        CraftableIndex craftables,
        ProducerIndex smelt,
        IReadOnlyDictionary<int, long> vendorPrices,
        int professionId,
        bool useCrossProfessionCraftIntermediates,
        bool useSmeltIntermediates,
        int craftabilitySkillCap,
        HashSet<int> into,
        HashSet<int> visiting)
    {
        if (itemId <= 0) return;

        if (vendorPrices.ContainsKey(itemId))
        {
            return;
        }

        if (!visiting.Add(itemId))
        {
            return;
        }

        try
        {
            into.Add(itemId);

            if (craftables.TryGetProducers(itemId, out var candidates))
            {
                foreach (var recipe in candidates)
                {
                    if (recipe.MinSkill > craftabilitySkillCap) continue;
                    if (!useCrossProfessionCraftIntermediates && recipe.ProfessionId != professionId) continue;

                    foreach (var reagent in recipe.Reagents)
                    {
                        AddPricingClosureItemIds(
                            reagent.ItemId,
                            craftables,
                            smelt,
                            vendorPrices,
                            professionId,
                            useCrossProfessionCraftIntermediates,
                            useSmeltIntermediates,
                            craftabilitySkillCap,
                            into,
                            visiting);
                    }
                }
            }

            if (useSmeltIntermediates && smelt.TryGetProducers(itemId, out var producers))
            {
                foreach (var producer in producers)
                {
                    foreach (var reagent in producer.Reagents)
                    {
                        AddPricingClosureItemIds(
                            reagent.ItemId,
                            craftables,
                            smelt,
                            vendorPrices,
                            professionId,
                            useCrossProfessionCraftIntermediates,
                            useSmeltIntermediates,
                            craftabilitySkillCap,
                            into,
                            visiting);
                    }
                }
            }
        }
        finally
        {
            visiting.Remove(itemId);
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
        int professionId,
        bool useCrossProfessionCraftIntermediates,
        bool useSmeltIntermediates)
    {
        private readonly PriceMode _priceMode = priceMode;
        private readonly IReadOnlyDictionary<int, long> _vendorPrices = vendorPrices;
        private readonly FrozenDictionary<int, PriceSummary> _prices = prices;
        private readonly CraftableIndex _craftables = craftables;
        private readonly ProducerIndex _smelt = smelt;
        private readonly int _craftabilitySkillCap = craftabilitySkillCap;
        private readonly int _professionId = professionId;
        private readonly bool _useCrossProfessionCraftIntermediates = useCrossProfessionCraftIntermediates;
        private readonly bool _useSmeltIntermediates = useSmeltIntermediates;
        private readonly Dictionary<(int itemId, int skill), Money> _unitCostCache = new();
        private readonly Dictionary<(int itemId, int skill), (Recipe recipe, int outputQty)> _craftProducerCache = new();
        private readonly Dictionary<(int itemId, int skill), (Producer producer, int outputQty)> _smeltProducerCache = new();
        private readonly Dictionary<(int itemId, ProducerKind kind, string producerName), decimal> _intermediates = new();
        private readonly Dictionary<string, (Recipe recipe, decimal crafts)> _intermediateCraftsByRecipeId =
            new(StringComparer.OrdinalIgnoreCase);

        private bool IsCraftProducerAllowed(Recipe recipe) =>
            recipe.ProfessionId == _professionId || _useCrossProfessionCraftIntermediates;

        public IReadOnlyList<IntermediateLine> GetIntermediates() =>
            _intermediates
                .OrderBy(kvp => kvp.Key.kind)
                .ThenBy(kvp => kvp.Key.itemId)
                .ThenBy(kvp => kvp.Key.producerName, StringComparer.OrdinalIgnoreCase)
                .Select(kvp => new IntermediateLine(kvp.Key.itemId, kvp.Value, kvp.Key.kind, kvp.Key.producerName))
                .ToArray();

        public IReadOnlyList<(Recipe Recipe, decimal Crafts)> GetIntermediateCrafts() =>
            _intermediateCraftsByRecipeId.Values
                .OrderBy(x => x.recipe.ProfessionId)
                .ThenBy(x => x.recipe.MinSkill)
                .ThenBy(x => x.recipe.RecipeId, StringComparer.OrdinalIgnoreCase)
                .Select(x => (x.recipe, x.crafts))
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

        public Dictionary<int, decimal> ExpandToLeafQuantities(int itemId, decimal quantity, int skill)
        {
            var tmp = new ReagentResolver(
                _priceMode,
                _vendorPrices,
                _prices,
                _craftables,
                _smelt,
                _craftabilitySkillCap,
                _professionId,
                _useCrossProfessionCraftIntermediates,
                _useSmeltIntermediates);

            var dict = new Dictionary<int, decimal>();
            var missing = new HashSet<int>();
            var visiting = new HashSet<int>();
            tmp.AddShoppingForItem(dict, itemId, quantity, skill, missing, visiting);
            return dict;
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
                if (_vendorPrices.TryGetValue(itemId, out var vendorCopper))
                {
                    unitCost = new Money(vendorCopper);
                    _unitCostCache[(itemId, skill)] = unitCost;
                    return true;
                }

                var hasEligibleProducer = false;
                if (TryGetBestCraftProducer(itemId, skill, missing, visiting, out hasEligibleProducer, out var producer, out var outputQty, out var perUnitCost))
                {
                    _craftProducerCache[(itemId, skill)] = (producer, outputQty);
                    unitCost = perUnitCost;
                    _unitCostCache[(itemId, skill)] = unitCost;
                    return true;
                }

                if (hasEligibleProducer)
                {
                    unitCost = Money.Zero;
                    return false;
                }

                var hasBuy = _prices.TryGetValue(itemId, out var summary);
                var buyCost = hasBuy ? GetUnitPrice(_priceMode, summary!) : (Money?)null;

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

            if (!_craftables.TryGetProducers(itemId, out var candidates))
            {
                return false;
            }

            Money? bestCost = null;

            foreach (var recipe in candidates)
            {
                if (recipe.MinSkill > _craftabilitySkillCap) continue;
                if (recipe.Output is null) continue;
                if (recipe.Output.ItemId != itemId) continue;
                if (!IsCraftProducerAllowed(recipe)) continue;

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

            if (!_smelt.TryGetProducers(itemId, out var candidates))
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
            if (_vendorPrices.ContainsKey(itemId))
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
                    AddIntermediateCrafts(craftCached.recipe, crafts);
                    foreach (var reagent in craftCached.recipe.Reagents)
                    {
                        AddShoppingForItem(shopping, reagent.ItemId, reagent.Quantity * crafts, skill, missing, visiting);
                    }
                    return;
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

                if (!_prices.ContainsKey(itemId))
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

        private void AddIntermediateCrafts(Recipe recipe, decimal crafts)
        {
            if (crafts <= 0) return;

            if (_intermediateCraftsByRecipeId.TryGetValue(recipe.RecipeId, out var existing))
            {
                _intermediateCraftsByRecipeId[recipe.RecipeId] = (existing.recipe, existing.crafts + crafts);
            }
            else
            {
                _intermediateCraftsByRecipeId[recipe.RecipeId] = (recipe, crafts);
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
