namespace WowAhPlanner.Core.Domain.Planning;

using WowAhPlanner.Core.Domain;

public sealed record PlanResult(
    IReadOnlyList<PlanStep> Steps,
    IReadOnlyList<ShoppingListLine> ShoppingList,
    Money TotalCost,
    DateTime GeneratedAtUtc);

