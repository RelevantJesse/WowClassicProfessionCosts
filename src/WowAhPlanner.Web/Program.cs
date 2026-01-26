using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using System.Diagnostics;
using WowAhPlanner.Core.Ports;
using WowAhPlanner.Core.Services;
using WowAhPlanner.Infrastructure.DependencyInjection;
using WowAhPlanner.Infrastructure.Persistence;
using WowAhPlanner.Web.Api;
using WowAhPlanner.Web.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddRazorPages();
builder.Services.AddServerSideBlazor();
builder.Services.AddHttpClient();

builder.Services.AddSingleton<RealmCatalog>();
builder.Services.AddScoped<LocalStorageService>();
builder.Services.AddScoped<SelectionState>();
builder.Services.AddSingleton<WowAddonInstaller>();
builder.Services.AddScoped<PlannerService>();

var dbDir = Path.Combine(builder.Environment.ContentRootPath, "App_Data");
Directory.CreateDirectory(dbDir);

var appDbPath = Path.Combine(dbDir, "wowahplanner.db");
var appDbConnectionString = $"Data Source={appDbPath}";

builder.Services.AddWowAhPlannerSqlite(appDbConnectionString);

builder.Services.AddWowAhPlannerInfrastructure(
    configureDataPacks: o =>
    {
        var configured = builder.Configuration["DataPacks:RootPath"];
        if (!string.IsNullOrWhiteSpace(configured))
        {
            o.RootPath = configured;
        }
        else
        {
            var contentDir = Path.Combine(builder.Environment.ContentRootPath, "data");
            var baseDir = Path.Combine(AppContext.BaseDirectory, "data");
            o.RootPath = Directory.Exists(contentDir) ? contentDir : baseDir;
        }
    },
    configurePricing: o =>
    {
        o.PrimaryProviderName = builder.Configuration["Pricing:PrimaryProviderName"] ?? o.PrimaryProviderName;
        o.FallbackProviderName = builder.Configuration["Pricing:FallbackProviderName"] ?? o.FallbackProviderName;
    },
    configureWorker: o =>
    {
        builder.Configuration.GetSection("PriceRefreshWorker").Bind(o);
    },
    configureCommunityUploads: o =>
    {
        builder.Configuration.GetSection("CommunityUploads").Bind(o);
    });

var app = builder.Build();

using (var scope = app.Services.CreateScope())
{
    var dbFactory = scope.ServiceProvider.GetRequiredService<IDbContextFactory<AppDbContext>>();
    await using var db = await dbFactory.CreateDbContextAsync();
    await db.Database.EnsureCreatedAsync();
    await SqliteSchemaBootstrapper.EnsureAppSchemaAsync(db);

    _ = scope.ServiceProvider.GetRequiredService<IRecipeRepository>();
}

var httpsEnabled = builder.Environment.IsDevelopment() || builder.Configuration.GetValue("Https:Enabled", false);

if (!app.Environment.IsDevelopment() && httpsEnabled)
{
    app.UseHsts();
}

if (httpsEnabled)
{
    app.UseHttpsRedirection();
}
app.UseStaticFiles();
app.UseRouting();

app.MapWowAhPlannerApi();

app.MapRazorPages();
app.MapBlazorHub();
app.MapFallbackToPage("/_Host");

if (builder.Configuration.GetValue("Browser:AutoOpen", false) && Environment.UserInteractive)
{
    var configuredUrl = builder.Configuration["Browser:Url"] ?? "http://localhost:5000";
    app.Lifetime.ApplicationStarted.Register(() =>
    {
        try
        {
            var server = app.Services.GetService<IServer>();
            var url =
                server?.Features.Get<IServerAddressesFeature>()?.Addresses.FirstOrDefault()
                ?? configuredUrl;

            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        }
        catch
        {
            // no-op
        }
    });
}

app.Run();
