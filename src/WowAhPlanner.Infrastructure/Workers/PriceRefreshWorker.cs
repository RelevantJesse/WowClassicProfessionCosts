namespace WowAhPlanner.Infrastructure.Workers;

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using WowAhPlanner.Core.Domain;
using WowAhPlanner.Core.Ports;

public sealed class PriceRefreshWorker(
    PriceRefreshWorkerOptions options,
    IRecipeRepository recipeRepository,
    IServiceScopeFactory scopeFactory,
    ILogger<PriceRefreshWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!options.Enabled)
        {
            return;
        }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await RefreshOnce(stoppingToken);
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Price refresh worker failed.");
            }

            await Task.Delay(TimeSpan.FromSeconds(Math.Max(5, options.IntervalSeconds)), stoppingToken);
        }
    }

    private async Task RefreshOnce(CancellationToken cancellationToken)
    {
        using var scope = scopeFactory.CreateScope();
        var priceService = scope.ServiceProvider.GetRequiredService<IPriceService>();

        foreach (var realm in options.Realms)
        {
            var professions = await recipeRepository.GetProfessionsAsync(realm.GameVersion, cancellationToken);
            var itemIds = new HashSet<int>();

            foreach (var profession in professions)
            {
                var recipes = await recipeRepository.GetRecipesAsync(realm.GameVersion, profession.ProfessionId, cancellationToken);
                foreach (var reagent in recipes.SelectMany(r => r.Reagents))
                {
                    itemIds.Add(reagent.ItemId);
                }
            }

            if (itemIds.Count == 0) continue;

            _ = await priceService.GetPricesAsync(realm, itemIds.OrderBy(x => x).ToArray(), PriceMode.Min, cancellationToken);
        }
    }
}
