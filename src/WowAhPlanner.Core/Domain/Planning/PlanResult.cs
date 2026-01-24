namespace WowAhPlanner.Core.Domain.Planning;

using WowAhPlanner.Core.Domain;

public sealed record PlanResult(
    IReadOnlyList<PlanStep> Steps,
    IReadOnlyList<IntermediateLine> Intermediates,
    IReadOnlyList<ShoppingListLine> ShoppingList,
    IReadOnlyList<OwnedMaterialLine> OwnedMaterialsUsed,
    int SkillCreditApplied,
    decimal ExpectedSkillUpsFromIntermediates,
    Money TotalCost,
    DateTime GeneratedAtUtc);
