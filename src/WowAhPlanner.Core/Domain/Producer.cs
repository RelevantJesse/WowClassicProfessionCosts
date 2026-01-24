namespace WowAhPlanner.Core.Domain;

public sealed record Producer(
    string ProducerId,
    string Name,
    ProducerKind Kind,
    RecipeOutput Output,
    IReadOnlyList<Reagent> Reagents,
    int? MinSkill = null);

