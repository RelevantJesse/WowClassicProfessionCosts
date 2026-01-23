namespace WowAhPlanner.Infrastructure.DependencyInjection;

using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using WowAhPlanner.Core.Ports;
using WowAhPlanner.Infrastructure.DataPacks;
using WowAhPlanner.Infrastructure.Persistence;
using WowAhPlanner.Infrastructure.Pricing;
using WowAhPlanner.Infrastructure.Workers;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddWowAhPlannerInfrastructure(
        this IServiceCollection services,
        Action<DataPackOptions>? configureDataPacks = null,
        Action<PricingOptions>? configurePricing = null,
        Action<PriceRefreshWorkerOptions>? configureWorker = null)
    {
        var dataOptions = new DataPackOptions();
        configureDataPacks?.Invoke(dataOptions);
        services.AddSingleton(dataOptions);

        var pricingOptions = new PricingOptions();
        configurePricing?.Invoke(pricingOptions);
        services.AddSingleton(pricingOptions);

        var workerOptions = new PriceRefreshWorkerOptions();
        configureWorker?.Invoke(workerOptions);
        services.AddSingleton(workerOptions);

        services.AddSingleton<IRecipeRepository, JsonDataPackRepository>();

        services.AddSingleton<IPriceProvider, StubJsonPriceProvider>();
        services.AddSingleton<IPriceProvider, BlizzardApiPriceProvider>();

        services.AddScoped<IPriceService, CachingPriceService>();

        services.AddHostedService<PriceRefreshWorker>();

        return services;
    }

    public static IServiceCollection AddWowAhPlannerSqlite(
        this IServiceCollection services,
        string connectionString)
    {
        services.AddDbContextFactory<AppDbContext>(o => o.UseSqlite(connectionString));
        return services;
    }
}

