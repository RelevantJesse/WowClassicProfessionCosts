namespace WowAhPlanner.Core.Domain.Planning;

using WowAhPlanner.Core.Domain;

public sealed record PlanComputationResult(
    PlanResult? Plan,
    PriceSnapshot PriceSnapshot,
    IReadOnlyList<int> MissingItemIds,
    string? ErrorMessage);

