namespace WowAhPlanner.Core.Domain.Planning;

using WowAhPlanner.Core.Domain;

public sealed record IntermediateLine(
    int ItemId,
    decimal Quantity,
    ProducerKind Kind,
    string ProducerName);

