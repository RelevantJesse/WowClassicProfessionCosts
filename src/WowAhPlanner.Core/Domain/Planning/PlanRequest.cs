namespace WowAhPlanner.Core.Domain.Planning;

using WowAhPlanner.Core.Domain;

public sealed record PlanRequest(
    RealmKey RealmKey,
    int ProfessionId,
    int CurrentSkill,
    int TargetSkill,
    PriceMode PriceMode,
    bool UseCraftIntermediates = true,
    bool UseSmeltIntermediates = true,
    IReadOnlyDictionary<int, long>? OwnedMaterials = null);
