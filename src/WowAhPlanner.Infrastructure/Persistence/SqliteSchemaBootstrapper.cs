namespace WowAhPlanner.Infrastructure.Persistence;

using Microsoft.EntityFrameworkCore;

public static class SqliteSchemaBootstrapper
{
    public static async Task EnsureAppSchemaAsync(AppDbContext db, CancellationToken cancellationToken = default)
    {
        await db.Database.ExecuteSqlRawAsync(
            """
            CREATE TABLE IF NOT EXISTS PriceSnapshotUploads (
                Id TEXT NOT NULL CONSTRAINT PK_PriceSnapshotUploads PRIMARY KEY,
                RealmKey TEXT NOT NULL,
                UploadedAtUtc TEXT NOT NULL,
                SnapshotTimestampUtc TEXT NOT NULL,
                UploaderUserId TEXT NULL,
                ItemCount INTEGER NOT NULL
            );
            """,
            cancellationToken);

        await db.Database.ExecuteSqlRawAsync(
            """
            CREATE TABLE IF NOT EXISTS PriceSnapshotItems (
                UploadId TEXT NOT NULL,
                ItemId INTEGER NOT NULL,
                MinUnitBuyoutCopper INTEGER NOT NULL,
                TotalQuantity INTEGER NULL,
                CONSTRAINT PK_PriceSnapshotItems PRIMARY KEY (UploadId, ItemId),
                CONSTRAINT FK_PriceSnapshotItems_PriceSnapshotUploads_UploadId
                    FOREIGN KEY (UploadId) REFERENCES PriceSnapshotUploads (Id) ON DELETE CASCADE
            );
            """,
            cancellationToken);

        await db.Database.ExecuteSqlRawAsync(
            """
            CREATE INDEX IF NOT EXISTS IX_PriceSnapshotUploads_RealmKey_UploadedAtUtc
                ON PriceSnapshotUploads (RealmKey, UploadedAtUtc);
            """,
            cancellationToken);

        await db.Database.ExecuteSqlRawAsync(
            """
            CREATE INDEX IF NOT EXISTS IX_PriceSnapshotItems_ItemId
                ON PriceSnapshotItems (ItemId);
            """,
            cancellationToken);

        await db.Database.ExecuteSqlRawAsync(
            """
            CREATE TABLE IF NOT EXISTS OwnedMaterials (
                RealmKey TEXT NOT NULL,
                UserId TEXT NOT NULL,
                ItemId INTEGER NOT NULL,
                Quantity INTEGER NOT NULL,
                UpdatedAtUtc TEXT NOT NULL,
                CONSTRAINT PK_OwnedMaterials PRIMARY KEY (RealmKey, UserId, ItemId)
            );
            """,
            cancellationToken);

        await db.Database.ExecuteSqlRawAsync(
            """
            CREATE INDEX IF NOT EXISTS IX_OwnedMaterials_RealmKey_UserId
                ON OwnedMaterials (RealmKey, UserId);
            """,
            cancellationToken);
    }
}
