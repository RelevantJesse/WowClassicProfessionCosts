namespace WowAhPlanner.Infrastructure.Persistence;

using Microsoft.EntityFrameworkCore;

public sealed class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<ItemPriceSummaryEntity> ItemPriceSummaries => Set<ItemPriceSummaryEntity>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<ItemPriceSummaryEntity>(b =>
        {
            b.HasKey(x => new { x.RealmKey, x.ProviderName, x.ItemId });
            b.Property(x => x.RealmKey).HasMaxLength(128);
            b.Property(x => x.ProviderName).HasMaxLength(64);
        });
    }
}

