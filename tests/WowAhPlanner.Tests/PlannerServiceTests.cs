namespace WowAhPlanner.Tests;

using WowAhPlanner.Core.Domain;
using WowAhPlanner.Core.Domain.Planning;
using WowAhPlanner.Core.Ports;
using WowAhPlanner.Core.Services;

public sealed class PlannerServiceTests
{
    [Fact]
    public async Task Picks_cheapest_recipe_for_a_skill_point()
    {
        var recipes = new[]
        {
            new Recipe(
                RecipeId: "cheap",
                ProfessionId: 185,
                Name: "Cheap",
                MinSkill: 1,
                OrangeUntil: 100,
                YellowUntil: 101,
                GreenUntil: 102,
                GrayAt: 103,
                Reagents: [new Reagent(100, 1)]),
            new Recipe(
                RecipeId: "expensive",
                ProfessionId: 185,
                Name: "Expensive",
                MinSkill: 1,
                OrangeUntil: 100,
                YellowUntil: 101,
                GreenUntil: 102,
                GrayAt: 103,
                Reagents: [new Reagent(200, 1)]),
        };

        var recipeRepo = new InMemoryRecipeRepository(recipes);
        var priceService = new InMemoryPriceService(new Dictionary<int, long>
        {
            [100] = 10,
            [200] = 999,
        });
        var vendorRepo = new InMemoryVendorPriceRepository(new Dictionary<int, long>());

        var producerRepo = new InMemoryProducerRepository();

        var planner = new PlannerService(recipeRepo, priceService, vendorRepo, producerRepo);
        var result = await planner.BuildPlanAsync(
            new PlanRequest(
                RealmKey: new RealmKey(Region.US, GameVersion.Era, "whitemane"),
                ProfessionId: 185,
                CurrentSkill: 1,
                TargetSkill: 2,
                PriceMode: PriceMode.Min),
            CancellationToken.None);

        Assert.NotNull(result.Plan);
        Assert.Equal("cheap", result.Plan!.Steps.Single().RecipeId);
    }

    [Fact]
    public async Task Excludes_cooldown_recipes_from_planning()
    {
        var recipes = new[]
        {
            new Recipe(
                RecipeId: "cooldown-cheap",
                ProfessionId: 185,
                Name: "Cooldown Cheap",
                MinSkill: 1,
                OrangeUntil: 100,
                YellowUntil: 101,
                GreenUntil: 102,
                GrayAt: 103,
                Reagents: [new Reagent(100, 1)],
                CooldownSeconds: 345600),
            new Recipe(
                RecipeId: "normal",
                ProfessionId: 185,
                Name: "Normal",
                MinSkill: 1,
                OrangeUntil: 100,
                YellowUntil: 101,
                GreenUntil: 102,
                GrayAt: 103,
                Reagents: [new Reagent(200, 1)]),
        };

        var recipeRepo = new InMemoryRecipeRepository(recipes);
        var priceService = new InMemoryPriceService(new Dictionary<int, long>
        {
            [100] = 1,
            [200] = 10,
        });
        var vendorRepo = new InMemoryVendorPriceRepository(new Dictionary<int, long>());

        var producerRepo = new InMemoryProducerRepository();

        var planner = new PlannerService(recipeRepo, priceService, vendorRepo, producerRepo);
        var result = await planner.BuildPlanAsync(
            new PlanRequest(
                RealmKey: new RealmKey(Region.US, GameVersion.Era, "whitemane"),
                ProfessionId: 185,
                CurrentSkill: 1,
                TargetSkill: 2,
                PriceMode: PriceMode.Min),
            CancellationToken.None);

        Assert.NotNull(result.Plan);
        Assert.Equal("normal", result.Plan!.Steps.Single().RecipeId);
    }

    [Fact]
    public async Task Shopping_list_aggregates_quantities_across_steps()
    {
        var recipes = new[]
        {
            new Recipe(
                RecipeId: "r1",
                ProfessionId: 185,
                Name: "Recipe 1",
                MinSkill: 1,
                OrangeUntil: 100,
                YellowUntil: 101,
                GreenUntil: 102,
                GrayAt: 103,
                Reagents: [new Reagent(100, 2)]),
        };

        var recipeRepo = new InMemoryRecipeRepository(recipes);
        var priceService = new InMemoryPriceService(new Dictionary<int, long> { [100] = 10 });
        var vendorRepo = new InMemoryVendorPriceRepository(new Dictionary<int, long>());

        var producerRepo = new InMemoryProducerRepository();

        var planner = new PlannerService(recipeRepo, priceService, vendorRepo, producerRepo);
        var result = await planner.BuildPlanAsync(
            new PlanRequest(
                RealmKey: new RealmKey(Region.US, GameVersion.Era, "whitemane"),
                ProfessionId: 185,
                CurrentSkill: 1,
                TargetSkill: 3,
                PriceMode: PriceMode.Min),
            CancellationToken.None);

        Assert.NotNull(result.Plan);
        var line = Assert.Single(result.Plan!.ShoppingList);
        Assert.Equal(100, line.ItemId);
        Assert.Equal(4m, line.Quantity);
    }

    [Fact]
    public async Task Shopping_list_expands_craftable_reagents_into_base_materials()
    {
        var recipes = new[]
        {
            new Recipe(
                RecipeId: "make-bolt",
                ProfessionId: 197,
                Name: "Bolt of Linen Cloth",
                MinSkill: 1,
                OrangeUntil: 0,
                YellowUntil: 0,
                GreenUntil: 0,
                GrayAt: 1,
                Reagents: [new Reagent(2589, 2)],
                Output: new RecipeOutput(2996, 1)),
            new Recipe(
                RecipeId: "shirt",
                ProfessionId: 197,
                Name: "Brown Linen Shirt",
                MinSkill: 1,
                OrangeUntil: 100,
                YellowUntil: 101,
                GreenUntil: 102,
                GrayAt: 103,
                Reagents: [new Reagent(2996, 3), new Reagent(2320, 1)]),
        };

        var recipeRepo = new InMemoryRecipeRepository(recipes);
        var priceService = new InMemoryPriceService(new Dictionary<int, long>
        {
            [2589] = 10,
            [2320] = 5,
        });
        var vendorRepo = new InMemoryVendorPriceRepository(new Dictionary<int, long>());

        var producerRepo = new InMemoryProducerRepository();

        var planner = new PlannerService(recipeRepo, priceService, vendorRepo, producerRepo);
        var result = await planner.BuildPlanAsync(
            new PlanRequest(
                RealmKey: new RealmKey(Region.US, GameVersion.Era, "whitemane"),
                ProfessionId: 197,
                CurrentSkill: 1,
                TargetSkill: 2,
                PriceMode: PriceMode.Min),
            CancellationToken.None);

        Assert.NotNull(result.Plan);
        Assert.DoesNotContain(result.Plan!.ShoppingList, x => x.ItemId == 2996);
        Assert.Contains(result.Plan!.ShoppingList, x => x.ItemId == 2589 && x.Quantity == 6m);
    }

    [Fact]
    public async Task Vendor_items_do_not_require_auction_price()
    {
        var recipes = new[]
        {
            new Recipe(
                RecipeId: "r1",
                ProfessionId: 197,
                Name: "Uses vendor reagent",
                MinSkill: 1,
                OrangeUntil: 100,
                YellowUntil: 101,
                GreenUntil: 102,
                GrayAt: 103,
                Reagents: [new Reagent(2320, 1)]),
        };

        var recipeRepo = new InMemoryRecipeRepository(recipes);
        var priceService = new InMemoryPriceService(new Dictionary<int, long>());
        var vendorRepo = new InMemoryVendorPriceRepository(new Dictionary<int, long> { [2320] = 40 });

        var producerRepo = new InMemoryProducerRepository();

        var planner = new PlannerService(recipeRepo, priceService, vendorRepo, producerRepo);
        var result = await planner.BuildPlanAsync(
            new PlanRequest(
                RealmKey: new RealmKey(Region.US, GameVersion.Era, "whitemane"),
                ProfessionId: 197,
                CurrentSkill: 1,
                TargetSkill: 2,
                PriceMode: PriceMode.Min),
            CancellationToken.None);

        Assert.NotNull(result.Plan);
        var line = Assert.Single(result.Plan!.ShoppingList);
        Assert.Equal(2320, line.ItemId);
        Assert.Equal(new Money(40), line.UnitPrice);
    }

    private sealed class InMemoryRecipeRepository(params Recipe[] recipes) : IRecipeRepository
    {
        public Task<IReadOnlyList<Profession>> GetProfessionsAsync(GameVersion gameVersion, CancellationToken cancellationToken)
            => Task.FromResult<IReadOnlyList<Profession>>([new Profession(185, "Cooking")]);

        public Task<IReadOnlyList<Recipe>> GetRecipesAsync(GameVersion gameVersion, int professionId, CancellationToken cancellationToken)
            => Task.FromResult<IReadOnlyList<Recipe>>(recipes.Where(r => r.ProfessionId == professionId).ToArray());
    }

    private sealed class InMemoryPriceService(IReadOnlyDictionary<int, long> prices) : IPriceService
    {
        public Task<PriceSnapshot> GetPricesAsync(
            RealmKey realmKey,
            IReadOnlyCollection<int> itemIds,
            PriceMode priceMode,
            CancellationToken cancellationToken)
        {
            var dict = new Dictionary<int, PriceSummary>();

            foreach (var itemId in itemIds)
            {
                if (!prices.TryGetValue(itemId, out var minCopper)) continue;
                dict[itemId] = new PriceSummary(itemId, minCopper, null, DateTime.UtcNow, "Test");
            }

            return Task.FromResult(new PriceSnapshot(realmKey, "Test", DateTime.UtcNow, IsStale: false, ErrorMessage: null, Prices: dict));
        }
    }

    private sealed class InMemoryVendorPriceRepository(IReadOnlyDictionary<int, long> vendorPrices) : IVendorPriceRepository
    {
        public Task<IReadOnlyDictionary<int, long>> GetVendorPricesAsync(GameVersion gameVersion, CancellationToken cancellationToken)
            => Task.FromResult(vendorPrices);

        public Task<long?> GetVendorPriceCopperAsync(GameVersion gameVersion, int itemId, CancellationToken cancellationToken)
            => Task.FromResult(vendorPrices.TryGetValue(itemId, out var v) ? (long?)v : null);
    }

    private sealed class InMemoryProducerRepository(params Producer[] producers) : IProducerRepository
    {
        public Task<IReadOnlyList<Producer>> GetProducersAsync(GameVersion gameVersion, CancellationToken cancellationToken)
            => Task.FromResult<IReadOnlyList<Producer>>(producers);
    }
}

