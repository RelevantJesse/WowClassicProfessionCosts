namespace WowAhPlanner.Infrastructure.Pricing;

using WowAhPlanner.Core.Domain;
using WowAhPlanner.Core.Ports;

public sealed class BlizzardApiPriceProvider : IPriceProvider
{
    public string Name => "BlizzardApi";

    public Task<PriceProviderResult> GetPricesAsync(
        RealmKey realmKey,
        IReadOnlyCollection<int> itemIds,
        PriceMode priceMode,
        CancellationToken cancellationToken)
    {
        return Task.FromResult(new PriceProviderResult(
            Success: false,
            ProviderName: Name,
            SnapshotTimestampUtc: DateTime.UtcNow,
            Prices: new Dictionary<int, PriceSummary>(),
            ErrorCode: "not_configured",
            ErrorMessage: "Blizzard API provider not configured (MVP ships with StubJson pricing)."));
    }
}

