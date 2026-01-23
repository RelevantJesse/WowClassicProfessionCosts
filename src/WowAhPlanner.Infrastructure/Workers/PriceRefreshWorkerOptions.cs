namespace WowAhPlanner.Infrastructure.Workers;

using WowAhPlanner.Core.Domain;

public sealed class PriceRefreshWorkerOptions
{
    public bool Enabled { get; set; } = false;
    public int IntervalSeconds { get; set; } = 900;
    public List<RealmKey> Realms { get; set; } = [];
}

