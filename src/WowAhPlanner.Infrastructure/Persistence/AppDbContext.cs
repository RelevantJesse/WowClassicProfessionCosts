namespace WowAhPlanner.Infrastructure.Persistence;

using Microsoft.EntityFrameworkCore;

public sealed class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<ItemPriceSummaryEntity> ItemPriceSummaries => Set<ItemPriceSummaryEntity>();
    public DbSet<PriceSnapshotUploadEntity> PriceSnapshotUploads => Set<PriceSnapshotUploadEntity>();
    public DbSet<PriceSnapshotItemEntity> PriceSnapshotItems => Set<PriceSnapshotItemEntity>();
    public DbSet<OwnedMaterialEntity> OwnedMaterials => Set<OwnedMaterialEntity>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<ItemPriceSummaryEntity>(b =>
        {
            b.HasKey(x => new { x.RealmKey, x.ProviderName, x.ItemId });
            b.Property(x => x.RealmKey).HasMaxLength(128);
            b.Property(x => x.ProviderName).HasMaxLength(64);
        });

        modelBuilder.Entity<PriceSnapshotUploadEntity>(b =>
        {
            b.HasKey(x => x.Id);
            b.Property(x => x.RealmKey).HasMaxLength(128);
            b.Property(x => x.UploaderUserId).HasMaxLength(450);
            b.HasIndex(x => new { x.RealmKey, x.UploadedAtUtc });
        });

        modelBuilder.Entity<PriceSnapshotItemEntity>(b =>
        {
            b.HasKey(x => new { x.UploadId, x.ItemId });
            b.HasOne(x => x.Upload)
                .WithMany(x => x.Items)
                .HasForeignKey(x => x.UploadId)
                .OnDelete(DeleteBehavior.Cascade);
            b.HasIndex(x => x.ItemId);
        });

        modelBuilder.Entity<OwnedMaterialEntity>(b =>
        {
            b.HasKey(x => new { x.RealmKey, x.UserId, x.ItemId });
            b.Property(x => x.RealmKey).HasMaxLength(128);
            b.Property(x => x.UserId).HasMaxLength(450);
            b.HasIndex(x => new { x.RealmKey, x.UserId });
        });
    }
}
