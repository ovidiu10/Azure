$repo = "Microsoft/DiagManager"
$releases = "https://api.github.com/repos/$repo/releases"
Write-Host Determining latest release
$tag = (Invoke-WebRequest $releases | ConvertFrom-Json)[0].tag_name
$ver = $tag.Substring(3, $tag.Length - 3).Replace(".","_")
$file = "PSSDIAG_v_$ver.zip"
$download = "https://github.com/$repo/releases/download/$tag/$file"
Write-Host Dowloading latest release
Invoke-WebRequest $download -Out $file
Write-Host Done