using System.ComponentModel;
using System.Text.Json;
using WowAhPlanner.Core.Domain;
using WowAhPlanner.Core.Ports;
using WowAhPlanner.Infrastructure.Owned;
using WowAhPlanner.WinForms.Services;
using WowAhPlanner.WinForms.Ui;
using Region = WowAhPlanner.Core.Domain.Region;

namespace WowAhPlanner.WinForms.Pages;

internal sealed class OwnedPageControl(
    SelectionState selection,
    IItemRepository itemRepository,
    OwnedMaterialsService ownedService,
    OwnedBreakdownService ownedBreakdown,
    JsonFileStateStore store) : PageControlBase
{
    private const string SavedVariablesPathKey = "WowAhPlanner.Owned.SavedVariablesPath.v1";
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
    private readonly Button loadAndSaveButton = new();

    private readonly Ui.CardPanel jsonCard = new();
    private readonly Label jsonTitleLabel = new();
    private readonly CheckBox allowMismatchCheckBox = new();
    private readonly TextBox jsonTextBox = new();
    private readonly FlowLayoutPanel jsonButtons = new();
    private readonly Button saveButton = new();
    private readonly Button loadFromDbButton = new();
    private readonly Label messageLabel = new();

    private readonly Ui.CardPanel previewCard = new();
    private readonly Label previewTitleLabel = new();
    private readonly DataGridView previewGrid = new();

    private bool initialized;
    private bool busy;
    private Dictionary<int, string> itemNames = new();

    public override string Title => "Owned";

    public override async Task OnNavigatedToAsync()
    {
        if (!initialized)
        {
            initialized = true;
            BuildUi();
        }

        await selection.EnsureLoadedAsync();

        itemNames = (await itemRepository.GetItemsAsync(selection.GameVersion, CancellationToken.None))
            .ToDictionary(kvp => kvp.Key, kvp => kvp.Value);

        var storedPath = await store.GetAsync<string>(SavedVariablesPathKey);
        if (!string.IsNullOrWhiteSpace(storedPath) && string.IsNullOrWhiteSpace(savedVariablesPathTextBox.Text))
        {
            savedVariablesPathTextBox.Text = storedPath;
        }

        realmBodyLabel.Text = $"Saved locally for: {selection.ToRealmKey()}";
        await RefreshPreviewAsync();
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
        loadButton.Click += async (_, _) => await LoadFromSavedVariablesAsync(saveAfterLoad: false);

        loadAndSaveButton.Text = "Load + Save";
        loadAndSaveButton.Margin = new Padding(0);
        Ui.Theme.ApplyPrimaryButtonStyle(loadAndSaveButton);
        loadAndSaveButton.Click += async (_, _) => await LoadFromSavedVariablesAsync(saveAfterLoad: true);

        importButtons.Dock = DockStyle.Top;
        importButtons.AutoSize = true;
        importButtons.AutoSizeMode = AutoSizeMode.GrowAndShrink;
        importButtons.Margin = new Padding(0);
        importButtons.Padding = new Padding(0);
        importButtons.Controls.Add(browseButton);
        importButtons.Controls.Add(loadButton);
        importButtons.Controls.Add(loadAndSaveButton);

        importCard.Controls.Add(importButtons);
        importCard.Controls.Add(savedVariablesPathTextBox);
        importCard.Controls.Add(importTitleLabel);

        Ui.Theme.ApplyCardStyle(jsonCard);
        jsonCard.Dock = DockStyle.Top;
        jsonCard.Padding = new Padding(16);
        jsonCard.Margin = new Padding(0, 0, 0, 12);
        jsonCard.AutoSize = true;
        jsonCard.AutoSizeMode = AutoSizeMode.GrowAndShrink;

        jsonTitleLabel.Text = "Paste owned mats JSON";
        jsonTitleLabel.AutoSize = true;
        jsonTitleLabel.Dock = DockStyle.Top;
        jsonTitleLabel.Margin = new Padding(0, 0, 0, 8);
        Ui.Theme.ApplyCardTitleStyle(jsonTitleLabel);

        allowMismatchCheckBox.Text = "Allow importing owned mats whose (region/version/realmSlug) do not match current selection";
        allowMismatchCheckBox.AutoSize = true;
        allowMismatchCheckBox.Margin = new Padding(0, 0, 0, 8);
        allowMismatchCheckBox.ForeColor = Ui.Theme.TextSecondary;

        jsonTextBox.Multiline = true;
        jsonTextBox.ScrollBars = ScrollBars.Vertical;
        jsonTextBox.Dock = DockStyle.Top;
        jsonTextBox.Height = 220;
        jsonTextBox.Margin = new Padding(0, 0, 0, 12);
        jsonTextBox.BackColor = Ui.Theme.AppBackground;
        jsonTextBox.ForeColor = Ui.Theme.TextPrimary;
        jsonTextBox.BorderStyle = BorderStyle.FixedSingle;
        jsonTextBox.Text = "{\"schema\":\"wowahplanner-owned-v1\",\"items\":[{\"itemId\":2589,\"qty\":200}]}";

        saveButton.Text = "Save";
        saveButton.Margin = new Padding(0, 0, 8, 0);
        Ui.Theme.ApplyPrimaryButtonStyle(saveButton);
        saveButton.Click += async (_, _) => await SaveAsync();

        loadFromDbButton.Text = "Load";
        loadFromDbButton.Margin = new Padding(0);
        Ui.Theme.ApplyHeaderButtonStyle(loadFromDbButton);
        loadFromDbButton.Click += async (_, _) => await LoadFromDbAsync();

        jsonButtons.Dock = DockStyle.Top;
        jsonButtons.AutoSize = true;
        jsonButtons.AutoSizeMode = AutoSizeMode.GrowAndShrink;
        jsonButtons.Margin = new Padding(0, 0, 0, 12);
        jsonButtons.Padding = new Padding(0);
        jsonButtons.Controls.Add(saveButton);
        jsonButtons.Controls.Add(loadFromDbButton);

        messageLabel.AutoSize = true;
        messageLabel.Dock = DockStyle.Top;
        messageLabel.Margin = new Padding(0);
        messageLabel.ForeColor = Ui.Theme.TextSecondary;

        jsonCard.Controls.Add(messageLabel);
        jsonCard.Controls.Add(jsonButtons);
        jsonCard.Controls.Add(jsonTextBox);
        jsonCard.Controls.Add(allowMismatchCheckBox);
        jsonCard.Controls.Add(jsonTitleLabel);

        Ui.Theme.ApplyCardStyle(previewCard);
        previewCard.Dock = DockStyle.Fill;
        previewCard.Padding = new Padding(16);
        previewCard.Margin = new Padding(0);

        previewTitleLabel.Text = "Owned totals";
        previewTitleLabel.AutoSize = true;
        previewTitleLabel.Dock = DockStyle.Top;
        previewTitleLabel.Margin = new Padding(0, 0, 0, 12);
        Ui.Theme.ApplyCardTitleStyle(previewTitleLabel);

        Ui.Theme.ApplyDataGridViewStyle(previewGrid);
        previewGrid.Dock = DockStyle.Fill;
        previewGrid.AutoGenerateColumns = false;
        previewGrid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Item", DataPropertyName = nameof(OwnedRow.Item), MinimumWidth = 240 });
        previewGrid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText = "Qty", DataPropertyName = nameof(OwnedRow.Qty), AutoSizeMode = DataGridViewAutoSizeColumnMode.AllCells });

        previewCard.Controls.Add(previewGrid);
        previewCard.Controls.Add(previewTitleLabel);

        Controls.Add(previewCard);
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

    private async Task LoadFromSavedVariablesAsync(bool saveAfterLoad)
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

            var json = await SavedVariablesReader.ReadLuaStringValueAsync(path, "lastOwnedJson");
            jsonTextBox.Text = json;
            messageLabel.Text = saveAfterLoad
                ? "Loaded owned JSON from SavedVariables. Saving..."
                : "Loaded owned JSON from SavedVariables. Click Save to store it.";

            if (saveAfterLoad)
            {
                await SaveJsonAsync(json);
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

    private async Task SaveAsync()
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
            await SaveJsonAsync(jsonTextBox.Text ?? "");
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

    private async Task SaveJsonAsync(string json)
    {
        if (string.IsNullOrWhiteSpace(json))
        {
            throw new InvalidOperationException("JSON is required.");
        }

        await selection.EnsureLoadedAsync();

        var dto = JsonSerializer.Deserialize<OwnedDto>(json, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        if (dto is null)
        {
            throw new InvalidOperationException("Could not parse JSON.");
        }

        if (!string.IsNullOrWhiteSpace(dto.Schema) &&
            !string.Equals(dto.Schema, "wowahplanner-owned-v1", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException($"Unexpected schema '{dto.Schema}'. Expected 'wowahplanner-owned-v1'.");
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
                $"Owned snapshot is for '{metaKey}', but current selection is '{selectionKey}'. " +
                "Switch your selection to match, or check the box to allow mismatch.");
        }

        var items = dto.Items ?? [];
        var rows = items
            .Where(x => x.ItemId > 0 && x.Qty >= 0)
            .Select(x => (x.ItemId, (long)x.Qty))
            .ToArray();

        // Store under the user's current selection key so planning uses the same realm.
        var updated = await ownedService.UpsertAsync(selectionKey.ToString(), LocalUserId, rows, CancellationToken.None);

        // Persist per-character breakdown (optional) for richer plan UI.
        if (dto.Characters is { Count: > 0 })
        {
            var byItemId = new Dictionary<int, List<(string CharacterName, long Qty)>>();
            foreach (var ch in dto.Characters.Where(c => !string.IsNullOrWhiteSpace(c.Name)))
            {
                if (ch.Items is null) continue;
                foreach (var it in ch.Items)
                {
                    if (it.ItemId <= 0 || it.Qty <= 0) continue;

                    if (!byItemId.TryGetValue(it.ItemId, out var list))
                    {
                        list = new List<(string, long)>();
                        byItemId[it.ItemId] = list;
                    }

                    list.Add((ch.Name.Trim(), it.Qty));
                }
            }

            var frozen = byItemId.ToDictionary(
                kvp => kvp.Key,
                kvp => (IReadOnlyList<(string, long)>)kvp.Value.ToArray());

            await ownedBreakdown.SaveAsync(selectionKey.ToString(), frozen);
        }

        var metaNote = hasAnyMeta && metaKey != selectionKey
            ? $" (owned meta is {metaKey})"
            : "";
        messageLabel.Text = $"Saved {updated} items for {selectionKey}.{metaNote}";

        await RefreshPreviewAsync();
    }

    private async Task LoadFromDbAsync()
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
            await selection.EnsureLoadedAsync();

            var realmKey = selection.ToRealmKey().ToString();
            var owned = await ownedService.GetOwnedAsync(realmKey, LocalUserId, CancellationToken.None);

            jsonTextBox.Text = JsonSerializer.Serialize(
                new OwnedDto
                {
                    Schema = "wowahplanner-owned-v1",
                    Items = owned.OrderBy(kvp => kvp.Key)
                        .Select(kvp => new OwnedItemDto { ItemId = kvp.Key, Qty = kvp.Value })
                        .ToList(),
                },
                new JsonSerializerOptions(JsonSerializerDefaults.Web) { WriteIndented = true });

            messageLabel.Text = $"Loaded {owned.Count} items.";
            await RefreshPreviewAsync();
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

    private async Task RefreshPreviewAsync()
    {
        try
        {
            await selection.EnsureLoadedAsync();
            var realmKey = selection.ToRealmKey().ToString();
            var owned = await ownedService.GetOwnedAsync(realmKey, LocalUserId, CancellationToken.None);

            var view = owned
                .OrderByDescending(kvp => kvp.Value)
                .ThenBy(kvp => kvp.Key)
                .Select(kvp =>
                {
                    var name = itemNames.GetValueOrDefault(kvp.Key) ?? $"Item {kvp.Key}";
                    return new OwnedRow($"{name} ({kvp.Key})", kvp.Value.ToString());
                })
                .ToList();

            previewGrid.DataSource = new BindingList<OwnedRow>(view);
        }
        catch
        {
            // ignore preview errors
        }
    }

    private void SetBusyUi(bool isBusy)
    {
        loadButton.Enabled = !isBusy;
        loadAndSaveButton.Enabled = !isBusy;
        saveButton.Enabled = !isBusy;
        loadFromDbButton.Enabled = !isBusy;
        browseButton.Enabled = !isBusy;
    }

    private sealed record OwnedRow(string Item, string Qty);

    private sealed class OwnedDto
    {
        public string? Schema { get; set; }
        public string? SnapshotTimestampUtc { get; set; }
        public string? Region { get; set; }
        public string? GameVersion { get; set; }
        public string? RealmSlug { get; set; }
        public List<OwnedCharacterDto>? Characters { get; set; }
        public List<OwnedItemDto>? Items { get; set; }
    }

    private sealed class OwnedCharacterDto
    {
        public string Name { get; set; } = "Unknown";
        public List<OwnedItemDto>? Items { get; set; }
    }

    private sealed class OwnedItemDto
    {
        public int ItemId { get; set; }
        public long Qty { get; set; }
    }
}
