namespace WowAhPlanner.Infrastructure.DataPacks;

public sealed class DataPackOptions
{
    public string RootPath { get; set; } = Path.Combine(AppContext.BaseDirectory, "data");
}

