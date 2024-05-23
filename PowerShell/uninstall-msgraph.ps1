Get-InstalledModule Microsoft.Graph.* | ? Name -ne "Microsoft.Graph.Authentication" | Uninstall-Module -AllVersions
Uninstall-Module Microsoft.Graph.Authentication -AllVersions