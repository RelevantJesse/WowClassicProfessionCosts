namespace WowAhPlanner.Core.Domain.Planning;

using WowAhPlanner.Core.Domain;

public sealed record PlanResult(
    IReadOnlyList<PlanStep> Steps,
    IReadOnlyList<IntermediateLine> Intermediates,
    IReadOnlyList<ShoppingListLine> ShoppingList,
    Money TotalCost,
    DateTime GeneratedAtUtc);
