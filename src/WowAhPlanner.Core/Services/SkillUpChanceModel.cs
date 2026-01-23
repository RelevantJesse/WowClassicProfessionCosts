namespace WowAhPlanner.Core.Services;

using WowAhPlanner.Core.Domain;

public sealed class SkillUpChanceModel
{
    public decimal OrangeChance { get; init; } = 1.00m;
    public decimal YellowChance { get; init; } = 0.75m;
    public decimal GreenChance { get; init; } = 0.25m;
    public decimal GrayChance { get; init; } = 0.00m;

    public decimal GetChance(DifficultyColor color) =>
        color switch
        {
            DifficultyColor.Orange => OrangeChance,
            DifficultyColor.Yellow => YellowChance,
            DifficultyColor.Green => GreenChance,
            DifficultyColor.Gray => GrayChance,
            _ => 0.00m,
        };
}

