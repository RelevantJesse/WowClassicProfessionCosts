namespace WowAhPlanner.Infrastructure.Pricing;

public sealed class PricingOptions
{
    public string PrimaryProviderName { get; set; } = "StubJson";
    public string? FallbackProviderName { get; set; } = "StubJson";
}

