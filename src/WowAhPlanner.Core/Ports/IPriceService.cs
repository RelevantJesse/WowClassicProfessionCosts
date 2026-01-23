namespace WowAhPlanner.Core.Ports;

using WowAhPlanner.Core.Domain;

public interface IPriceService
{
    Task<PriceSnapshot> GetPricesAsync(
        RealmKey realmKey,
        IReadOnlyCollection<int> itemIds,
        PriceMode priceMode,
        CancellationToken cancellationToken);
}

