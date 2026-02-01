using WowAhPlanner.Core.Domain;

namespace WowAhPlanner.WinForms.Services;

internal sealed class WowAddonInstaller
{
    public bool TryResolveAddonFolder(GameVersion version, out string folderPath, out string error)
    {
        folderPath = "";
        error = "";

        var wowMode = version switch
        {
            GameVersion.Anniversary => "_anniversary_",
            _ => "_classic_",
        };

        var candidates = new List<string?>
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "World of Warcraft"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "World of Warcraft"),
        };

        foreach (var root in candidates.Where(p => !string.IsNullOrWhiteSpace(p)).Cast<string>())
        {
            var addonFolder = Path.Combine(root, wowMode, "Interface", "AddOns", "ProfessionLevelerScan");
            if (Directory.Exists(addonFolder))
            {
                folderPath = addonFolder;
                return true;
            }
        }

        error = $"Could not find add-on folder. Expected something like 'C:\\Program Files (x86)\\World of Warcraft\\{wowMode}\\Interface\\AddOns\\ProfessionLevelerScan'.";
        return false;
    }
}
