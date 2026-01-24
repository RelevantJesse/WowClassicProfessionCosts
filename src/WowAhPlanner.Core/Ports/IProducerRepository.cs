namespace WowAhPlanner.Core.Ports;

using WowAhPlanner.Core.Domain;

public interface IProducerRepository
{
    Task<IReadOnlyList<Producer>> GetProducersAsync(GameVersion gameVersion, CancellationToken cancellationToken);
}

