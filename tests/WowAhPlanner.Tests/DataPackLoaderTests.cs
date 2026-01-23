namespace WowAhPlanner.Tests;

using WowAhPlanner.Infrastructure.DataPacks;

public sealed class DataPackLoaderTests
{
    [Fact]
    public void Rejects_missing_required_fields()
    {
        var root = Path.Combine(Path.GetTempPath(), "WowAhPlannerTests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);

        try
        {
            var era = Path.Combine(root, "Era");
            var professions = Path.Combine(era, "professions");
            Directory.CreateDirectory(professions);

            File.WriteAllText(
                Path.Combine(era, "items.json"),
                """[ { "itemId": 1, "name": "Test Item" } ]""");

            File.WriteAllText(
                Path.Combine(professions, "cooking.json"),
                """
                {
                  "professionId": 185,
                  "professionName": "Cooking",
                  "recipes": [
                    {
                      "professionId": 185,
                      "name": "Missing recipeId",
                      "minSkill": 1,
                      "orangeUntil": 1,
                      "yellowUntil": 2,
                      "greenUntil": 3,
                      "grayAt": 4,
                      "reagents": [ { "itemId": 1, "qty": 1 } ]
                    }
                  ]
                }
                """);

            Assert.Throws<DataPackValidationException>(() => _ = new JsonDataPackRepository(new DataPackOptions { RootPath = root }));
        }
        finally
        {
            try { Directory.Delete(root, recursive: true); } catch { }
        }
    }
}

