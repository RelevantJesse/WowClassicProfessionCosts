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

        var planner = new PlannerService(recipeRepo, priceService);
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

        var planner = new PlannerService(recipeRepo, priceService);
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
}

