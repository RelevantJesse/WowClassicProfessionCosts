namespace WowAhPlanner.Web.Services;

using System.Text.Json;
using Microsoft.JSInterop;

public sealed class LocalStorageService(IJSRuntime jsRuntime)
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async ValueTask<T?> GetAsync<T>(string key)
    {
        var json = await jsRuntime.InvokeAsync<string?>("wowAhPlanner.storage.get", key);
        if (string.IsNullOrWhiteSpace(json)) return default;
        return JsonSerializer.Deserialize<T>(json, JsonOptions);
    }

    public async ValueTask SetAsync<T>(string key, T value)
    {
        var json = JsonSerializer.Serialize(value, JsonOptions);
        await jsRuntime.InvokeVoidAsync("wowAhPlanner.storage.set", key, json);
    }
}

