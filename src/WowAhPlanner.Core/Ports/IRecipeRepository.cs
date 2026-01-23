namespace WowAhPlanner.Core.Ports;

using WowAhPlanner.Core.Domain;

public interface IRecipeRepository
{
    Task<IReadOnlyList<Profession>> GetProfessionsAsync(GameVersion gameVersion, CancellationToken cancellationToken);
    Task<IReadOnlyList<Recipe>> GetRecipesAsync(GameVersion gameVersion, int professionId, CancellationToken cancellationToken);
}

