[CmdletBinding()]
param(
    [Parameter()]
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$')]
    [string]$Version = '1.3.0',

    [Parameter()]
    [string]$OutputDirectory,

    [Parameter()]
    [string]$ArtifactDirectory,

    [Parameter()]
    [string]$ReadmeDirectory
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $PSScriptRoot 'artifacts'
}

function Find-DirectoryContainingFile {
    param(
        [Parameter(Mandatory)]
        [string[]]$Candidates,

        [Parameter(Mandatory)]
        [string]$FileName
    )

    foreach ($candidate in $Candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate $FileName) -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "${FileName} was not found. Searched: $($Candidates -join ', ')"
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($ArtifactDirectory)) {
    $ArtifactDirectory = Find-DirectoryContainingFile -Candidates @(
        $repositoryRoot,
        (Join-Path $repositoryRoot 'iscp')
    ) -FileName 'iSCP.dll'
} else {
    $ArtifactDirectory = (Resolve-Path -LiteralPath $ArtifactDirectory).Path
}

if ([string]::IsNullOrWhiteSpace($ReadmeDirectory)) {
    $ReadmeDirectory = Find-DirectoryContainingFile -Candidates @(
        (Join-Path $repositoryRoot 'iscp/iSCP'),
        $repositoryRoot
    ) -FileName 'README.md'
} else {
    $ReadmeDirectory = (Resolve-Path -LiteralPath $ReadmeDirectory).Path
}

foreach ($requiredFile in @('iSCP.dll', 'iSCP.xml')) {
    $requiredPath = Join-Path $ArtifactDirectory $requiredFile
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "A required package file was not found: $requiredPath"
    }
}

$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$projectPath = Join-Path $PSScriptRoot 'iSCP.NuGet.csproj'

& dotnet pack $projectPath `
    --configuration Release `
    --output $OutputDirectory `
    "-p:PackageVersion=$Version" `
    "-p:ArtifactPath=$ArtifactDirectory" `
    "-p:ReadmePath=$ReadmeDirectory"

if ($LASTEXITCODE -ne 0) {
    throw "NuGet package creation failed with exit code $LASTEXITCODE."
}

$packagePath = Join-Path $OutputDirectory "iSCP.$Version.nupkg"
if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
    throw "The generated NuGet package was not found: $packagePath"
}

Write-Output "Created NuGet package: $packagePath"
