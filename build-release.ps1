[CmdletBinding()]
param(
    [string]$Version,
    [switch]$BuildOnly,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$AllowPartialCheckout,
    [string]$OutputDirectory = "C:\Users\Luke\Desktop\ActuallyZips"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepositoryDirectory = $PSScriptRoot
$AddonName = "Actually"
$ExpectedRepository = "maplepancake50/actually"
$IsBuildOnly = $BuildOnly -or $DryRun

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text
    )

    $Encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $Encoding)
}

function Get-ActuallyTocPath {
    $Toc = Get-ChildItem -LiteralPath $RepositoryDirectory -File -Filter "*.toc" |
        Where-Object { $_.BaseName -ieq $AddonName } |
        Select-Object -First 1

    if (-not $Toc) {
        throw "Could not find Actually.toc in $RepositoryDirectory"
    }

    return $Toc.FullName
}

function Get-TocVersion {
    param([Parameter(Mandatory = $true)][string]$TocPath)

    $Match = Select-String -LiteralPath $TocPath -Pattern '^\s*##\s*Version:\s*(\S+)\s*$' |
        Select-Object -First 1
    if (-not $Match) {
        throw "The TOC has no ## Version entry: $TocPath"
    }

    return $Match.Matches[0].Groups[1].Value
}

function Assert-Version {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value -notmatch '^\d+\.\d+\.\d+$') {
        throw "Version '$Value' is invalid. Use semantic version format such as 0.3.5."
    }
}

function Get-DefaultNextVersion {
    param([Parameter(Mandatory = $true)][string]$CurrentVersion)

    if ($CurrentVersion -notmatch '^(\d+)\.(\d+)\.(\d+)$') {
        throw "Current TOC version '$CurrentVersion' is not a three-part semantic version."
    }

    return "{0}.{1}.{2}" -f [int]$Matches[1], [int]$Matches[2], ([int]$Matches[3] + 1)
}

function Test-BlockedRelativePath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $Segments = $RelativePath -split '[\\/]'
    foreach ($Segment in $Segments) {
        if (
            $Segment -like ".git*" -or
            $Segment -in @(".github", ".claude", ".codex-plugins", ".agents", "Tests", "tmp", "Archive")
        ) {
            return $true
        }
    }

    return $false
}

function Copy-RelativeFile {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$PackageRoot
    )

    if (Test-BlockedRelativePath -RelativePath $RelativePath) {
        throw "The TOC references a development-only or blocked path: $RelativePath"
    }

    $SourcePath = Join-Path $RepositoryDirectory $RelativePath
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        throw "The TOC references a missing file: $RelativePath"
    }

    $DestinationPath = Join-Path $PackageRoot $RelativePath
    $DestinationParent = Split-Path -Parent $DestinationPath
    if (-not (Test-Path -LiteralPath $DestinationParent)) {
        New-Item -ItemType Directory -Force -Path $DestinationParent | Out-Null
    }

    Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
}

function Get-TocRuntimeFiles {
    param([Parameter(Mandatory = $true)][string]$TocPath)

    $Files = New-Object System.Collections.Generic.List[string]
    foreach ($Line in Get-Content -LiteralPath $TocPath) {
        $Entry = $Line.Trim()
        if (-not $Entry -or $Entry.StartsWith("#")) {
            continue
        }

        $Files.Add(($Entry -replace '/', '\'))
    }

    return $Files
}

function Set-StagedTocVersion {
    param(
        [Parameter(Mandatory = $true)][string]$TocPath,
        [Parameter(Mandatory = $true)][string]$NewVersion
    )

    $Text = [System.IO.File]::ReadAllText($TocPath)
    $Updated = [regex]::Replace(
        $Text,
        '(?m)^(\s*##\s*Version:\s*)\S+(\s*)$',
        ('${1}' + $NewVersion + '${2}'),
        1
    )
    if ($Updated -eq $Text -and (Get-TocVersion -TocPath $TocPath) -ne $NewVersion) {
        throw "Unable to update the staged TOC version."
    }

    Write-Utf8NoBom -Path $TocPath -Text $Updated
}

function New-ActuallyPackage {
    param(
        [Parameter(Mandatory = $true)][string]$TocPath,
        [Parameter(Mandatory = $true)][string]$PackageVersion
    )

    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    }

    $ZipPath = Join-Path $OutputDirectory "$AddonName-v$PackageVersion.zip"
    if (Test-Path -LiteralPath $ZipPath) {
        if (-not $Force) {
            throw "Release ZIP already exists: $ZipPath. Use -Force to replace it."
        }
        Remove-Item -LiteralPath $ZipPath -Force
    }

    $StageDirectory = Join-Path $OutputDirectory (".actually-stage-{0}-{1}" -f $PID, [guid]::NewGuid().ToString("N"))
    $PackageRoot = Join-Path $StageDirectory $AddonName

    try {
        New-Item -ItemType Directory -Force -Path $PackageRoot | Out-Null

        $StagedToc = Join-Path $PackageRoot "$AddonName.toc"
        Copy-Item -LiteralPath $TocPath -Destination $StagedToc -Force
        Set-StagedTocVersion -TocPath $StagedToc -NewVersion $PackageVersion

        foreach ($RelativePath in Get-TocRuntimeFiles -TocPath $TocPath) {
            Copy-RelativeFile -RelativePath $RelativePath -PackageRoot $PackageRoot
        }

        foreach ($OptionalFile in @("README.md", "LICENSE", "THIRD_PARTY_NOTICES.md")) {
            $OptionalPath = Join-Path $RepositoryDirectory $OptionalFile
            if (Test-Path -LiteralPath $OptionalPath -PathType Leaf) {
                Copy-Item -LiteralPath $OptionalPath -Destination (Join-Path $PackageRoot $OptionalFile) -Force
            }
        }

        $RuntimeAssetExtensions = @(".blp", ".tga", ".ogg", ".wav", ".mp3", ".ttf")
        Get-ChildItem -LiteralPath $RepositoryDirectory -Recurse -File |
            Where-Object {
                $_.Extension.ToLowerInvariant() -in $RuntimeAssetExtensions -and
                -not (Test-BlockedRelativePath -RelativePath $_.FullName.Substring($RepositoryDirectory.Length).TrimStart('\'))
            } |
            ForEach-Object {
                $RelativeAssetPath = $_.FullName.Substring($RepositoryDirectory.Length).TrimStart('\')
                Copy-RelativeFile -RelativePath $RelativeAssetPath -PackageRoot $PackageRoot
            }

        Compress-Archive -LiteralPath $PackageRoot -DestinationPath $ZipPath -CompressionLevel Optimal

        if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) {
            throw "ZIP creation failed: $ZipPath"
        }

        return $ZipPath
    }
    finally {
        if (Test-Path -LiteralPath $StageDirectory) {
            Remove-Item -LiteralPath $StageDirectory -Recurse -Force
        }
    }
}

function Assert-FullReleaseCheckout {
    if (-not (Test-Path -LiteralPath (Join-Path $RepositoryDirectory ".git"))) {
        throw "Publishing requires a real Git checkout. This folder has no .git directory. Use -BuildOnly here, or run this script from a complete clone of $ExpectedRepository."
    }

    if (-not $AllowPartialCheckout) {
        $RequiredFullAddonPaths = @("Official.lua", "TierBoard.lua", "Sync.lua", "Pet.lua", "Textures")
        $Missing = @(
            $RequiredFullAddonPaths |
                Where-Object { -not (Test-Path -LiteralPath (Join-Path $RepositoryDirectory $_)) }
        )
        if ($Missing.Count -gt 0) {
            throw "This looks like a partial Actually checkout. Missing: $($Missing -join ', '). Use a complete clone before publishing. -AllowPartialCheckout overrides this guard."
        }
    }

    foreach ($Command in @("git", "gh")) {
        if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
            throw "Required command is not installed or not on PATH: $Command"
        }
    }

    $Dirty = @(& git -C $RepositoryDirectory status --porcelain)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read Git status."
    }
    $UnexpectedChanges = @(
        $Dirty | Where-Object {
            $_ -notmatch '^\?\?\s+build-release\.ps1$'
        }
    )
    if ($UnexpectedChanges.Count -gt 0) {
        throw "The Git working tree is not clean. Commit or stash changes before publishing."
    }

    $Origin = (& git -C $RepositoryDirectory remote get-url origin).Trim()
    if ($LASTEXITCODE -ne 0 -or $Origin -notmatch 'maplepancake50[/:]actually(?:\.git)?$') {
        throw "The origin remote is not $ExpectedRepository. Found: $Origin"
    }

    & gh auth status | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub CLI is not authenticated. Run: gh auth login"
    }
}

$TocPath = Get-ActuallyTocPath
$CurrentVersion = Get-TocVersion -TocPath $TocPath

if (-not $Version) {
    if ($IsBuildOnly) {
        $Version = $CurrentVersion
    }
    else {
        $DefaultVersion = Get-DefaultNextVersion -CurrentVersion $CurrentVersion
        $EnteredVersion = Read-Host "Release version [$DefaultVersion]"
        $Version = if ([string]::IsNullOrWhiteSpace($EnteredVersion)) { $DefaultVersion } else { $EnteredVersion.Trim() }
    }
}

Assert-Version -Value $Version

if ($IsBuildOnly) {
    $BuiltZip = New-ActuallyPackage -TocPath $TocPath -PackageVersion $Version
    Write-Host "Clean Actually package created:" -ForegroundColor Green
    Write-Host $BuiltZip
    exit 0
}

Assert-FullReleaseCheckout

$Tag = "v$Version"
& git -C $RepositoryDirectory rev-parse --verify --quiet "refs/tags/$Tag" | Out-Null
if ($LASTEXITCODE -eq 0) {
    throw "Git tag already exists: $Tag"
}

& gh release view $Tag --repo $ExpectedRepository | Out-Null 2>&1
if ($LASTEXITCODE -eq 0) {
    throw "GitHub Release already exists: $Tag"
}

$ReleaseZip = New-ActuallyPackage -TocPath $TocPath -PackageVersion $Version

$SourceTocText = [System.IO.File]::ReadAllText($TocPath)
$UpdatedSourceTocText = [regex]::Replace(
    $SourceTocText,
    '(?m)^(\s*##\s*Version:\s*)\S+(\s*)$',
    ('${1}' + $Version + '${2}'),
    1
)
Write-Utf8NoBom -Path $TocPath -Text $UpdatedSourceTocText

& git -C $RepositoryDirectory add -- $TocPath $PSCommandPath
if ($LASTEXITCODE -ne 0) { throw "Unable to stage the TOC version change." }

& git -C $RepositoryDirectory commit -m "Release $Tag"
if ($LASTEXITCODE -ne 0) { throw "Unable to create the release commit." }

$Branch = (& git -C $RepositoryDirectory branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or -not $Branch) {
    throw "Publishing from a detached HEAD is not supported."
}

& git -C $RepositoryDirectory tag -a $Tag -m "Actually $Tag"
if ($LASTEXITCODE -ne 0) { throw "Unable to create Git tag $Tag." }

& git -C $RepositoryDirectory push origin $Branch
if ($LASTEXITCODE -ne 0) { throw "Unable to push branch $Branch." }

& git -C $RepositoryDirectory push origin $Tag
if ($LASTEXITCODE -ne 0) { throw "Unable to push tag $Tag." }

& gh release create $Tag $ReleaseZip --repo $ExpectedRepository --title "Actually $Tag" --generate-notes
if ($LASTEXITCODE -ne 0) { throw "Unable to create the GitHub Release." }

Write-Host "Actually $Tag was released successfully." -ForegroundColor Green
Write-Host "Package: $ReleaseZip"
Write-Host "Release: https://github.com/$ExpectedRepository/releases/tag/$Tag"
