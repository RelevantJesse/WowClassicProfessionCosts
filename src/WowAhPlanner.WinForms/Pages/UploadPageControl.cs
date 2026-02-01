using System.Text.Json;
using WowAhPlanner.Core.Domain;
using WowAhPlanner.Infrastructure.Pricing;
using WowAhPlanner.WinForms.Services;
using Region = WowAhPlanner.Core.Domain.Region;

namespace WowAhPlanner.WinForms.Pages;

internal sealed class UploadPageControl(
    SelectionState selection,
    UploadedSnapshotIngestService ingest,
    JsonFileStateStore store) : PageControlBase
{
    private const string SavedVariablesPathKey = "WowAhPlanner.Upload.SavedVariablesPath.v1";
    private const string LocalUserId = "local";

    private readonly Ui.CardPanel realmCard = new();
    private readonly Label realmTitleLabel = new();
    private readonly Label realmBodyLabel = new();

    private readonly Ui.CardPanel importCard = new();
    private readonly Label importTitleLabel = new();
    private readonly TextBox savedVariablesPathTextBox = new();
    private readonly Button browseButton = new();
    private readonly FlowLayoutPanel importButtons = new();
    private readonly Button loadButton = new();
    private readonly Button loadAndUploadButton = new();

    private readonly Ui.CardPanel jsonCard = new();
    private readonly Label jsonTitleLabel = new();
    private readonly CheckBox allowMismatchCheckBox = new();
    private readonly TextBox jsonTextBox = new();
    private readonly FlowLayoutPanel jsonButtons = new();
    private readonly Button uploadButton = new();
    private readonly Label messageLabel = new();

    private bool initialized;
    private bool busy;

    public override string Title => "Upload";

    public override async Task OnNavigatedToAsync()
    {
        if (!initialized)
        {
            initialized = true;
            BuildUi();
        }

        await selection.EnsureLoadedAsync();

        var storedPath = await store.GetAsync<string>(SavedVariablesPathKey);
        if (!string.IsNullOrWhiteSpace(storedPath) && string.IsNullOrWhiteSpace(savedVariablesPathTextBox.Text))
        {
            savedVariablesPathTextBox.Text = storedPath;
        }

        realmBodyLabel.Text =
            $"Upload will be stored for: {selection.ToRealmKey()}\r\n" +
            $"Provider name used: {UploadedSnapshotIngestService.ProviderName}\r\n" +
            "Uploads are aggregated across the last few uploads to reduce outliers.";
    }

    private void BuildUi()
    {
        Ui.Theme.ApplyCardStyle(realmCard);
        realmCard.Dock = DockStyle.Top;
        realmCard.Padding = new Padding(16);
        realmCard.Margin = new Padding(0, 0, 0, 12);
        realmCard.AutoSize = true;
        realmCard.AutoSizeMode = AutoSizeMode.GrowAndShrink;

        realmTitleLabel.Text = "Realm";
        realmTitleLabel.AutoSize = true;
        realmTitleLabel.Dock = DockStyle.Top;
        realmTitleLabel.Margin = new Padding(0, 0, 0, 8);
        Ui.Theme.ApplyCardTitleStyle(realmTitleLabel);

        realmBodyLabel.AutoSize = true;
        realmBodyLabel.Dock = DockStyle.Top;
        realmBodyLabel.Margin = new Padding(0);
        Ui.Theme.ApplyCardBodyStyle(realmBodyLabel);

        realmCard.Controls.Add(realmBodyLabel);
        realmCard.Controls.Add(realmTitleLabel);

        Ui.Theme.ApplyCardStyle(importCard);
        importCard.Dock = DockStyle.Top;
        importCard.Padding = new Padding(16);
        importCard.Margin = new Padding(0, 0, 0, 12);
        importCard.AutoSize = true;
        importCard.AutoSizeMode = AutoSizeMode.GrowAndShrink;

        importTitleLabel.Text = "Import from SavedVariables";
        importTitleLabel.AutoSize = true;
        importTitleLabel.Dock = DockStyle.Top;
        importTitleLabel.Margin = new Padding(0, 0, 0, 12);
        Ui.Theme.ApplyCardTitleStyle(importTitleLabel);

        savedVariablesPathTextBox.Dock = DockStyle.Top;
        savedVariablesPathTextBox.Margin = new Padding(0, 0, 0, 12);
        savedVariablesPathTextBox.PlaceholderText = @"C:\Program Files (x86)\World of Warcraft\_anniversary_\WTF\Account\...\SavedVariables\ProfessionLevelerScan.lua";
        savedVariablesPathTextBox.BackColor = Ui.Theme.AppBackground;
        savedVariablesPathTextBox.ForeColor = Ui.Theme.TextPrimary;
        savedVariablesPathTextBox.BorderStyle = BorderStyle.FixedSingle;

        browseButton.Text = "Browse...";
        browseButton.Margin = new Padding(0, 0, 8, 0);
        Ui.Theme.ApplyHeaderButtonStyle(browseButton);
        browseButton.Click += (_, _) => BrowseSavedVariables();

        loadButton.Text = "Load into textarea";
        loadButton.Margin = new Padding(0, 0, 8, 0);
        Ui.Theme.ApplyHeaderButtonStyle(loadButton);
        loadButton.Click += async (_, _) => await LoadFromSavedVariablesAsync(uploadAfterLoad: false);

        loadAndUploadButton.Text = "Load + Upload";
        loadAndUploadButton.Margin = new Padding(0);
        Ui.Theme.ApplyPrimaryButtonStyle(loadAndUploadButton);
        loadAndUploadButton.Click += async (_, _) => await LoadFromSavedVariablesAsync(uploadAfterLoad: true);

        importButtons.Dock = DockStyle.Top;
        importButtons.AutoSize = true;
        importButtons.AutoSizeMode = AutoSizeMode.GrowAndShrink;
        importButtons.Margin = new Padding(0);
        importButtons.Padding = new Padding(0);
        importButtons.Controls.Add(browseButton);
        importButtons.Controls.Add(loadButton);
        importButtons.Controls.Add(loadAndUploadButton);

        importCard.Controls.Add(importButtons);
        importCard.Controls.Add(savedVariablesPathTextBox);
        importCard.Controls.Add(importTitleLabel);

        Ui.Theme.ApplyCardStyle(jsonCard);
        jsonCard.Dock = DockStyle.Fill;
        jsonCard.Padding = new Padding(16);
        jsonCard.Margin = new Padding(0);

        jsonTitleLabel.Text = "Paste JSON";
        jsonTitleLabel.AutoSize = true;
        jsonTitleLabel.Dock = DockStyle.Top;
        jsonTitleLabel.Margin = new Padding(0, 0, 0, 8);
        Ui.Theme.ApplyCardTitleStyle(jsonTitleLabel);

        allowMismatchCheckBox.Text = "Allow uploading snapshots whose (region/version/realmSlug) do not match current selection";
        allowMismatchCheckBox.AutoSize = true;
        allowMismatchCheckBox.Margin = new Padding(0, 0, 0, 8);
        allowMismatchCheckBox.ForeColor = Ui.Theme.TextSecondary;

        jsonTextBox.Multiline = true;
        jsonTextBox.ScrollBars = ScrollBars.Vertical;
        jsonTextBox.Dock = DockStyle.Fill;
        jsonTextBox.Margin = new Padding(0, 0, 0, 12);
        jsonTextBox.BackColor = Ui.Theme.AppBackground;
        jsonTextBox.ForeColor = Ui.Theme.TextPrimary;
        jsonTextBox.BorderStyle = BorderStyle.FixedSingle;

        uploadButton.Text = "Upload";
        uploadButton.Margin = new Padding(0);
        Ui.Theme.ApplyPrimaryButtonStyle(uploadButton);
        uploadButton.Click += async (_, _) => await UploadAsync();

        jsonButtons.Dock = DockStyle.Top;
        jsonButtons.AutoSize = true;
        jsonButtons.AutoSizeMode = AutoSizeMode.GrowAndShrink;
        jsonButtons.Margin = new Padding(0, 0, 0, 12);
        jsonButtons.Padding = new Padding(0);
        jsonButtons.Controls.Add(uploadButton);

        messageLabel.AutoSize = true;
        messageLabel.Dock = DockStyle.Top;
        messageLabel.Margin = new Padding(0);
        messageLabel.ForeColor = Ui.Theme.TextSecondary;

        jsonCard.Controls.Add(messageLabel);
        jsonCard.Controls.Add(jsonButtons);
        jsonCard.Controls.Add(jsonTextBox);
        jsonCard.Controls.Add(allowMismatchCheckBox);
        jsonCard.Controls.Add(jsonTitleLabel);

        Controls.Add(jsonCard);
        Controls.Add(importCard);
        Controls.Add(realmCard);
    }

    private void BrowseSavedVariables()
    {
        using var dialog = new OpenFileDialog
        {
            Title = "Select ProfessionLevelerScan.lua (SavedVariables)",
            Filter = "Lua files (*.lua)|*.lua|All files (*.*)|*.*",
            CheckFileExists = true,
        };

        if (dialog.ShowDialog() != DialogResult.OK)
        {
            return;
        }

        savedVariablesPathTextBox.Text = dialog.FileName;
    }

    private async Task LoadFromSavedVariablesAsync(bool uploadAfterLoad)
    {
        if (busy)
        {
            return;
        }

        busy = true;
        SetBusyUi(true);
        messageLabel.Text = "";

        try
        {
            var path = savedVariablesPathTextBox.Text ?? "";
            await store.SetAsync(SavedVariablesPathKey, path);

            var json = await SavedVariablesReader.ReadLuaStringValueAsync(path, "lastSnapshotJson");
            jsonTextBox.Text = json;
            messageLabel.Text = uploadAfterLoad
                ? "Loaded snapshot JSON from SavedVariables. Uploading..."
                : "Loaded snapshot JSON from SavedVariables. Click Upload to store it.";

            if (uploadAfterLoad)
            {
                await UploadJsonAsync(json);
            }
        }
        catch (Exception ex)
        {
            messageLabel.Text = ex.Message;
        }
        finally
        {
            busy = false;
            SetBusyUi(false);
        }
    }

    private async Task UploadAsync()
    {
        if (busy)
        {
            return;
        }

        busy = true;
        SetBusyUi(true);
        messageLabel.Text = "";

        try
        {
            await UploadJsonAsync(jsonTextBox.Text ?? "");
        }
        catch (Exception ex)
        {
            messageLabel.Text = ex.Message;
        }
        finally
        {
            busy = false;
            SetBusyUi(false);
        }
    }

    private async Task UploadJsonAsync(string json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            throw new InvalidOperationException("JSON is required.");
        }

        await selection.EnsureLoadedAsync();

        var dto = JsonSerializer.Deserialize<UploadSnapshotDto>(json, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        if (dto is null)
        {
            throw new InvalidOperationException("Could not parse JSON.");
        }

        if (!string.Equals(dto.Schema, "wowahplanner-scan-v1", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException($"Unexpected schema '{dto.Schema}'. Expected 'wowahplanner-scan-v1'.");
        }

        var selectionKey = selection.ToRealmKey();

        var region = selection.Region;
        var version = selection.GameVersion;
        var realmSlug = selection.RealmSlug;

        var hasAnyMeta = false;
        if (!string.IsNullOrWhiteSpace(dto.Region) && Enum.TryParse<Region>(dto.Region, true, out var r))
        {
            hasAnyMeta = true;
            region = r;
        }
        if (!string.IsNullOrWhiteSpace(dto.GameVersion) && Enum.TryParse<GameVersion>(dto.GameVersion, true, out var v))
        {
            hasAnyMeta = true;
            version = v;
        }
        if (!string.IsNullOrWhiteSpace(dto.RealmSlug))
        {
            hasAnyMeta = true;
            realmSlug = dto.RealmSlug.Trim();
        }

        var metaKey = new RealmKey(region, version, realmSlug);
        if (hasAnyMeta && metaKey != selectionKey && !allowMismatchCheckBox.Checked)
        {
            throw new InvalidOperationException(
                $"Snapshot is for '{metaKey}', but current selection is '{selectionKey}'. " +
                "Switch your selection to match, or check the box to allow mismatch.");
        }

        var prices = dto.Prices ?? [];
        var rows = prices
            .Where(p => p.ItemId > 0)
            .Select(p => new UploadedSnapshotIngestService.UploadPriceRow(
                p.ItemId,
                p.MinUnitBuyoutCopper,
                p.TotalQuantity))
            .ToArray();

        var snapshotTimestampUtc = dto.SnapshotTimestampUtc ?? DateTime.UtcNow;
        // Store under the user's current selection key so planning uses the same realm.
        var result = await ingest.IngestAsync(selectionKey.ToString(), snapshotTimestampUtc, uploaderUserId: LocalUserId, rows, CancellationToken.None);

        var metaNote = hasAnyMeta && metaKey != selectionKey
            ? $" (snapshot meta is {metaKey})"
            : "";

        messageLabel.Text = result.UploadId is null
            ? "No prices were stored."
            : $"Stored upload {result.UploadId} with {result.StoredItemCount} prices (aggregated {result.AggregatedItemCount}) for {selectionKey}.{metaNote}";
    }

    private void SetBusyUi(bool isBusy)
    {
        loadButton.Enabled = !isBusy;
        loadAndUploadButton.Enabled = !isBusy;
        uploadButton.Enabled = !isBusy;
        browseButton.Enabled = !isBusy;
    }

    private sealed class UploadSnapshotDto
    {
        public string? Schema { get; set; }
        public DateTime? SnapshotTimestampUtc { get; set; }
        public string? Region { get; set; }
        public string? GameVersion { get; set; }
        public string? RealmSlug { get; set; }
        public List<PriceDto>? Prices { get; set; }
    }

    private sealed class PriceDto
    {
        public int ItemId { get; set; }
        public long? MinUnitBuyoutCopper { get; set; }
        public long? TotalQuantity { get; set; }
    }
}
