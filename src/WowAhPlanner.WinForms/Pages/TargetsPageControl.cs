using System.Diagnostics;
using WowAhPlanner.Core.Domain;
using WowAhPlanner.Core.Ports;
using WowAhPlanner.WinForms.Services;
using Region = WowAhPlanner.Core.Domain.Region;

namespace WowAhPlanner.WinForms.Pages;

internal sealed class TargetsPageControl(
    SelectionState selection,
    IRecipeRepository recipeRepository,
    TargetsService targets,
    WowAddonInstaller addonInstaller) : PageControlBase
{
    private const int DefaultMaxSkillDelta = 100;

    private readonly Ui.CardPanel inputsCard = new();
    private readonly Label inputsTitleLabel = new();
    private readonly TableLayoutPanel inputsLayout = new();

    private readonly Label professionLabel = new();
    private readonly ComboBox professionComboBox = new();
    private readonly Label craftLabel = new();
    private readonly CheckBox craftIntermediatesCheckBox = new();
    private readonly Label smeltLabel = new();
    private readonly CheckBox smeltIntermediatesCheckBox = new();
    private readonly Label helpLabel = new();

    private readonly Ui.CardPanel actionsCard = new();
    private readonly Label actionsTitleLabel = new();
    private readonly FlowLayoutPanel actionsFlow = new();
    private readonly Button installButton = new();
    private readonly Button saveAsButton = new();
    private readonly Button openFolderButton = new();
    private readonly TextBox statusTextBox = new();

    private bool initialized;
    private bool busy;
    private IReadOnlyList<Profession> professions = [];

    public override string Title => "Targets";

    public override async Task OnNavigatedToAsync()
    {
        if (!initialized)
        {
            initialized = true;
            BuildUi();
        }

        await LoadAsync();
    }

    private void BuildUi()
    {
        Ui.Theme.ApplyCardStyle(inputsCard);
        inputsCard.Dock = DockStyle.Top;
        inputsCard.Padding = new Padding(16);
        inputsCard.Margin = new Padding(0, 0, 0, 12);
        inputsCard.AutoSize = true;
        inputsCard.AutoSizeMode = AutoSizeMode.GrowAndShrink;

        inputsTitleLabel.Text = "Profession";
        inputsTitleLabel.AutoSize = true;
        inputsTitleLabel.Dock = DockStyle.Top;
        inputsTitleLabel.Margin = new Padding(0, 0, 0, 12);
        Ui.Theme.ApplyCardTitleStyle(inputsTitleLabel);

        inputsLayout.ColumnCount = 2;
        inputsLayout.RowCount = 8;
        inputsLayout.Dock = DockStyle.Top;
        inputsLayout.AutoSize = true;
        inputsLayout.AutoSizeMode = AutoSizeMode.GrowAndShrink;
        inputsLayout.Margin = new Padding(0);
        inputsLayout.Padding = new Padding(0);
        inputsLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 220F));
        inputsLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
        for (int i = 0; i < inputsLayout.RowCount; i++)
        {
            inputsLayout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        }

        professionLabel.Text = "Profession";
        professionLabel.AutoSize = true;
        professionLabel.Margin = new Padding(0, 6, 8, 6);
        Ui.Theme.ApplyInputLabelStyle(professionLabel);

        professionComboBox.DropDownStyle = ComboBoxStyle.DropDownList;
        professionComboBox.Dock = DockStyle.Fill;
        professionComboBox.Margin = new Padding(0, 0, 0, 12);
        Ui.Theme.ApplyComboBoxStyle(professionComboBox);
        professionComboBox.SelectedIndexChanged += async (_, _) => await OnProfessionChangedAsync();

        craftLabel.Text = "Options";
        craftLabel.AutoSize = true;
        craftLabel.Margin = new Padding(0, 6, 8, 6);
        Ui.Theme.ApplyInputLabelStyle(craftLabel);

        craftIntermediatesCheckBox.Text = "Craft other-profession intermediates (optional)";
        craftIntermediatesCheckBox.AutoSize = true;
        craftIntermediatesCheckBox.Margin = new Padding(0, 0, 0, 8);
        craftIntermediatesCheckBox.ForeColor = Ui.Theme.TextSecondary;

        smeltLabel.Text = "";
        smeltLabel.AutoSize = true;
        smeltLabel.Margin = new Padding(0, 0, 0, 0);

        smeltIntermediatesCheckBox.Text = "Smelt intermediates (bars from ore)";
        smeltIntermediatesCheckBox.AutoSize = true;
        smeltIntermediatesCheckBox.Margin = new Padding(0, 0, 0, 12);
        smeltIntermediatesCheckBox.ForeColor = Ui.Theme.TextSecondary;
        smeltIntermediatesCheckBox.Checked = true;

        helpLabel.AutoSize = true;
        helpLabel.Margin = new Padding(0);
        helpLabel.ForeColor = Ui.Theme.TextSecondary;
        helpLabel.Text =
            "This writes ProfessionLevelerScan_Targets.lua into your WoW AddOns folder.\r\n" +
            $"The addon scans reagents for recipes from your current skill up to +{DefaultMaxSkillDelta} (configured in the addon).";

        inputsLayout.Controls.Add(professionLabel, 0, 0);
        inputsLayout.Controls.Add(professionComboBox, 1, 0);
        inputsLayout.Controls.Add(craftLabel, 0, 1);
        inputsLayout.Controls.Add(craftIntermediatesCheckBox, 1, 1);
        inputsLayout.Controls.Add(smeltLabel, 0, 2);
        inputsLayout.Controls.Add(smeltIntermediatesCheckBox, 1, 2);
        inputsLayout.Controls.Add(helpLabel, 0, 3);
        inputsLayout.SetColumnSpan(helpLabel, 2);

        inputsCard.Controls.Add(inputsLayout);
        inputsCard.Controls.Add(inputsTitleLabel);

        Ui.Theme.ApplyCardStyle(actionsCard);
        actionsCard.Dock = DockStyle.Fill;
        actionsCard.Padding = new Padding(16);
        actionsCard.Margin = new Padding(0);

        actionsTitleLabel.Text = "Actions";
        actionsTitleLabel.AutoSize = true;
        actionsTitleLabel.Dock = DockStyle.Top;
        actionsTitleLabel.Margin = new Padding(0, 0, 0, 12);
        Ui.Theme.ApplyCardTitleStyle(actionsTitleLabel);

        actionsFlow.Dock = DockStyle.Top;
        actionsFlow.AutoSize = true;
        actionsFlow.AutoSizeMode = AutoSizeMode.GrowAndShrink;
        actionsFlow.Margin = new Padding(0, 0, 0, 12);
        actionsFlow.Padding = new Padding(0);

        installButton.Text = "Install targets";
        installButton.Margin = new Padding(0, 0, 8, 0);
        Ui.Theme.ApplyPrimaryButtonStyle(installButton);
        installButton.Click += async (_, _) => await InstallAsync();

        saveAsButton.Text = "Save as...";
        saveAsButton.Margin = new Padding(0, 0, 8, 0);
        Ui.Theme.ApplyHeaderButtonStyle(saveAsButton);
        saveAsButton.Click += async (_, _) => await SaveAsAsync();

        openFolderButton.Text = "Open add-on folder";
        openFolderButton.Margin = new Padding(0);
        Ui.Theme.ApplyHeaderButtonStyle(openFolderButton);
        openFolderButton.Click += (_, _) => OpenAddonFolder();

        actionsFlow.Controls.Add(installButton);
        actionsFlow.Controls.Add(saveAsButton);
        actionsFlow.Controls.Add(openFolderButton);

        statusTextBox.Multiline = true;
        statusTextBox.ReadOnly = true;
        statusTextBox.Dock = DockStyle.Fill;
        statusTextBox.ScrollBars = ScrollBars.Vertical;
        statusTextBox.BackColor = Ui.Theme.AppBackground;
        statusTextBox.ForeColor = Ui.Theme.TextSecondary;
        statusTextBox.BorderStyle = BorderStyle.FixedSingle;

        actionsCard.Controls.Add(statusTextBox);
        actionsCard.Controls.Add(actionsFlow);
        actionsCard.Controls.Add(actionsTitleLabel);

        Controls.Add(actionsCard);
        Controls.Add(inputsCard);
    }

    private async Task LoadAsync()
    {
        if (busy)
        {
            return;
        }

        busy = true;
        try
        {
            await selection.EnsureLoadedAsync();
            professions = await recipeRepository.GetProfessionsAsync(selection.GameVersion, CancellationToken.None);

            var preferred = selection.ProfessionId;
            var selectedProfessionId = professions.Any(p => p.ProfessionId == preferred)
                ? preferred
                : professions.FirstOrDefault()?.ProfessionId ?? 0;

            professionComboBox.BeginUpdate();
            try
            {
                professionComboBox.DataSource = null;
                professionComboBox.DisplayMember = nameof(Profession.Name);
                professionComboBox.ValueMember = nameof(Profession.ProfessionId);
                professionComboBox.DataSource = professions.ToArray();
                professionComboBox.SelectedItem = professions.FirstOrDefault(p => p.ProfessionId == selectedProfessionId);
            }
            finally
            {
                professionComboBox.EndUpdate();
            }

            selection.ProfessionId = selectedProfessionId;
            await selection.PersistAsync();

            statusTextBox.Text = $"Ready. Selection: {selection.ToRealmKey()}";
        }
        catch (Exception ex)
        {
            statusTextBox.Text = ex.ToString();
        }
        finally
        {
            busy = false;
        }
    }

    private async Task OnProfessionChangedAsync()
    {
        if (busy)
        {
            return;
        }

        if (professionComboBox.SelectedItem is not Profession p)
        {
            return;
        }

        selection.ProfessionId = p.ProfessionId;
        await selection.PersistAsync();
    }

    private async Task InstallAsync()
    {
        if (busy)
        {
            return;
        }

        busy = true;
        installButton.Enabled = false;

        try
        {
            await selection.EnsureLoadedAsync();

            if (!addonInstaller.TryResolveAddonFolder(selection.GameVersion, out var addonFolder, out var err))
            {
                statusTextBox.Text = err;
                return;
            }

            var lua = await targets.GenerateRecipeTargetsLuaAsync(
                selection.GameVersion,
                selection.Region,
                selection.RealmSlug,
                selection.ProfessionId,
                useCraftIntermediates: craftIntermediatesCheckBox.Checked,
                useSmeltIntermediates: smeltIntermediatesCheckBox.Checked,
                CancellationToken.None);

            var targetPath = Path.Combine(addonFolder, "ProfessionLevelerScan_Targets.lua");
            File.WriteAllText(targetPath, lua);

            statusTextBox.Text =
                $"Updated:\r\n{targetPath}\r\n\r\n" +
                "Next steps:\r\n- /reload in WoW so SavedVariables and targets load\r\n- Run your scan command";
        }
        catch (Exception ex)
        {
            statusTextBox.Text = ex.ToString();
        }
        finally
        {
            busy = false;
            installButton.Enabled = true;
        }
    }

    private async Task SaveAsAsync()
    {
        if (busy)
        {
            return;
        }

        try
        {
            await selection.EnsureLoadedAsync();

            using var dialog = new SaveFileDialog
            {
                Title = "Save ProfessionLevelerScan_Targets.lua",
                FileName = "ProfessionLevelerScan_Targets.lua",
                Filter = "Lua files (*.lua)|*.lua|All files (*.*)|*.*",
                OverwritePrompt = true,
            };

            if (dialog.ShowDialog() != DialogResult.OK)
            {
                return;
            }

            var lua = await targets.GenerateRecipeTargetsLuaAsync(
                selection.GameVersion,
                selection.Region,
                selection.RealmSlug,
                selection.ProfessionId,
                useCraftIntermediates: craftIntermediatesCheckBox.Checked,
                useSmeltIntermediates: smeltIntermediatesCheckBox.Checked,
                CancellationToken.None);

            File.WriteAllText(dialog.FileName, lua);
            statusTextBox.Text = $"Saved:\r\n{dialog.FileName}";
        }
        catch (Exception ex)
        {
            statusTextBox.Text = ex.ToString();
        }
    }

    private void OpenAddonFolder()
    {
        try
        {
            if (!addonInstaller.TryResolveAddonFolder(selection.GameVersion, out var addonFolder, out var err))
            {
                statusTextBox.Text = err;
                return;
            }

            Process.Start(new ProcessStartInfo("explorer.exe", addonFolder) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            statusTextBox.Text = ex.Message;
        }
    }
}
