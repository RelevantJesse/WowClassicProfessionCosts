namespace WowAhPlanner.Infrastructure.Pricing;

using System.Collections.Concurrent;
using System.Text.Json;
using WowAhPlanner.Core.Domain;
using WowAhPlanner.Core.Ports;
using WowAhPlanner.Infrastructure.DataPacks;

public sealed class StubJsonPriceProvider(DataPackOptions dataPackOptions) : IPriceProvider
{
    public string Name => "StubJson";

    private readonly ConcurrentDictionary<GameVersion, Lazy<StubPriceFile>> _byVersion = new();

    public Task<PriceProviderResult> GetPricesAsync(
        RealmKey realmKey,
        IReadOnlyCollection<int> itemIds,
        PriceMode priceMode,
        CancellationToken cancellationToken)
    {
        var file = GetFile(realmKey.GameVersion);
        var dict = new Dictionary<int, PriceSummary>();

        foreach (var itemId in itemIds.Distinct())
        {
            if (!file.MinPrices.TryGetValue(itemId, out var minCopper))
            {
                continue;
            }

            dict[itemId] = new PriceSummary(
                ItemId: itemId,
                MinBuyoutCopper: minCopper,
                MedianCopper: null,
                SnapshotTimestampUtc: file.SnapshotTimestampUtc,
                SourceProvider: Name);
        }

        return Task.FromResult(new PriceProviderResult(
            Success: true,
            ProviderName: Name,
            SnapshotTimestampUtc: file.SnapshotTimestampUtc,
            Prices: dict,
            ErrorCode: null,
            ErrorMessage: null));
    }

    private StubPriceFile GetFile(GameVersion version)
    {
        var lazy = _byVersion.GetOrAdd(version, v => new Lazy<StubPriceFile>(() => Load(v)));
        return lazy.Value;
    }

    private StubPriceFile Load(GameVersion version)
    {
        var path = Path.Combine(dataPackOptions.RootPath, version.ToString(), "stub-prices.json");
        if (!File.Exists(path))
        {
            throw new DataPackValidationException($"Stub prices not found: {path}");
        }

        var json = File.ReadAllText(path);
        var doc = JsonSerializer.Deserialize<StubPriceFileDto>(json, JsonDefaults.Options);
        if (doc is null)
        {
            throw new DataPackValidationException($"Invalid stub prices JSON in {path} (null).");
        }

        if (doc.Prices is null || doc.Prices.Count == 0)
        {
            throw new DataPackValidationException($"Missing prices[] in {path}.");
        }

        var ts = doc.SnapshotTimestampUtc ?? File.GetLastWriteTimeUtc(path);
        var min = doc.Prices.ToDictionary(p => p.ItemId, p => p.MinBuyoutCopper);

        return new StubPriceFile(ts, min);
    }

    private sealed record StubPriceFile(DateTime SnapshotTimestampUtc, IReadOnlyDictionary<int, long> MinPrices);

    private sealed class StubPriceFileDto
    {
        public DateTime? SnapshotTimestampUtc { get; set; }
        public List<StubPriceDto>? Prices { get; set; }
    }

    private sealed class StubPriceDto
    {
        public int ItemId { get; set; }
        public long MinBuyoutCopper { get; set; }
    }

    private static class JsonDefaults
    {
        public static readonly JsonSerializerOptions Options = new()
        {
            PropertyNameCaseInsensitive = true,
            ReadCommentHandling = JsonCommentHandling.Skip,
            AllowTrailingCommas = true,
        };
    }
}

