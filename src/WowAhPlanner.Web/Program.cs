using Microsoft.EntityFrameworkCore;
using WowAhPlanner.Core.Ports;
using WowAhPlanner.Core.Services;
using WowAhPlanner.Infrastructure.DependencyInjection;
using WowAhPlanner.Infrastructure.Persistence;
using WowAhPlanner.Web.Api;
using WowAhPlanner.Web.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddRazorPages();
builder.Services.AddServerSideBlazor();

builder.Services.AddSingleton<RealmCatalog>();
builder.Services.AddScoped<LocalStorageService>();
builder.Services.AddScoped<SelectionState>();
builder.Services.AddScoped<PlannerService>();

var dbDir = Path.Combine(builder.Environment.ContentRootPath, "App_Data");
Directory.CreateDirectory(dbDir);

builder.Services.AddWowAhPlannerSqlite($"Data Source={Path.Combine(dbDir, "wowahplanner.db")}");
builder.Services.AddWowAhPlannerInfrastructure(
    configureDataPacks: o =>
    {
        o.RootPath = builder.Configuration["DataPacks:RootPath"] ?? Path.Combine(AppContext.BaseDirectory, "data");
    },
    configurePricing: o =>
    {
        o.PrimaryProviderName = builder.Configuration["Pricing:PrimaryProviderName"] ?? o.PrimaryProviderName;
        o.FallbackProviderName = builder.Configuration["Pricing:FallbackProviderName"] ?? o.FallbackProviderName;
    },
    configureWorker: o =>
    {
        builder.Configuration.GetSection("PriceRefreshWorker").Bind(o);
    });

var app = builder.Build();

using (var scope = app.Services.CreateScope())
{
    var dbFactory = scope.ServiceProvider.GetRequiredService<IDbContextFactory<AppDbContext>>();
    await using var db = await dbFactory.CreateDbContextAsync();
    await db.Database.EnsureCreatedAsync();

    _ = scope.ServiceProvider.GetRequiredService<IRecipeRepository>();
}

if (!app.Environment.IsDevelopment())
{
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseRouting();

app.MapWowAhPlannerApi();

app.MapBlazorHub();
app.MapFallbackToPage("/_Host");

app.Run();

