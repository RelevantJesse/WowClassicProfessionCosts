namespace WowAhPlanner.Web.Services;

using WowAhPlanner.Core.Domain;

public sealed class WowAddonInstaller(IConfiguration configuration)
{
    public bool TryResolveAddonFolder(GameVersion version, out string folderPath, out string error)
    {
        folderPath = "";
        error = "";

        var configured = configuration.GetSection("WowAddon:InstallPaths")[version.ToString()];
        if (!string.IsNullOrWhiteSpace(configured))
        {
            folderPath = configured!;
            if (Directory.Exists(folderPath)) return true;
            error = $"Configured add-on folder not found: {folderPath}";
            return false;
        }

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
            var addonFolder = Path.Combine(root, wowMode, "Interface", "AddOns", "WowAhPlannerScan");
            if (Directory.Exists(addonFolder))
            {
                folderPath = addonFolder;
                return true;
            }
        }

        error = $"Could not find add-on folder. Expected something like 'C:\\Program Files (x86)\\World of Warcraft\\{wowMode}\\Interface\\AddOns\\WowAhPlannerScan'. " +
                $"Either create/copy the add-on folder first, or set WowAddon:InstallPaths:{version} in appsettings.json.";
        return false;
    }
}

