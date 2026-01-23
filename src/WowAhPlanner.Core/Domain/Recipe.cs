namespace WowAhPlanner.Core.Domain;

public sealed record Recipe(
    string RecipeId,
    int ProfessionId,
    string Name,
    int MinSkill,
    int OrangeUntil,
    int YellowUntil,
    int GreenUntil,
    int GrayAt,
    IReadOnlyList<Reagent> Reagents)
{
    public DifficultyColor GetDifficultyAtSkill(int skill)
    {
        if (skill < MinSkill) return DifficultyColor.Gray;
        if (skill <= OrangeUntil) return DifficultyColor.Orange;
        if (skill <= YellowUntil) return DifficultyColor.Yellow;
        if (skill <= GreenUntil) return DifficultyColor.Green;
        if (skill < GrayAt) return DifficultyColor.Green;
        return DifficultyColor.Gray;
    }
}

