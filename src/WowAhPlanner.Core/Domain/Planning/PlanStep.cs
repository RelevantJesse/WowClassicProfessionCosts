namespace WowAhPlanner.Core.Domain.Planning;

using WowAhPlanner.Core.Domain;

public sealed record PlanStep(
    int SkillFrom,
    int SkillTo,
    string RecipeId,
    string RecipeName,
    bool? LearnedByTrainer,
    decimal SkillUpChance,
    decimal ExpectedCrafts,
    Money ExpectedCost);

