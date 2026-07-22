[CmdletBinding()]
param(
    [Parameter()]
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$')]
    [string]$Version = '1.3.0',

    [Parameter()]
    [string]$PackagePath
)

$ErrorActionPreference = 'Stop'
$packageDirectory = Join-Path $PSScriptRoot 'artifacts'

if ([string]::IsNullOrWhiteSpace($PackagePath)) {
    & (Join-Path $PSScriptRoot 'pack-nuget.ps1') -Version $Version -OutputDirectory $packageDirectory
    if ($LASTEXITCODE -ne 0) {
        throw "NuGet package creation failed with exit code $LASTEXITCODE."
    }
    $PackagePath = Join-Path $packageDirectory "iSCP.$Version.nupkg"
}

$PackagePath = (Resolve-Path -LiteralPath $PackagePath).Path
$packageDirectory = Split-Path -Parent $PackagePath
$temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "iscp-nuget-test-$([Guid]::NewGuid().ToString('N'))"
$expectedLibraryVersion = $Version.Split('-', 2)[0]

try {
    $null = New-Item -ItemType Directory -Path $temporaryDirectory

    $projectContent = @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="iSCP" Version="$Version" />
  </ItemGroup>
</Project>
"@

    $programContent = @"
using iSCP;

const string expectedVersion = "$expectedLibraryVersion";
if (IscpConsts.LIBRARY_VERSION != expectedVersion)
{
    throw new InvalidOperationException(`$"Expected iSCP {expectedVersion}, but loaded {IscpConsts.LIBRARY_VERSION}.");
}

Console.WriteLine(`$"iSCP {IscpConsts.LIBRARY_VERSION} loaded successfully.");
"@

    $escapedPackageDirectory = [System.Security.SecurityElement]::Escape($packageDirectory)
    $nugetConfigContent = @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="local" value="$escapedPackageDirectory" />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" protocolVersion="3" />
  </packageSources>
</configuration>
"@

    Set-Content -LiteralPath (Join-Path $temporaryDirectory 'NuGetTest.csproj') -Value $projectContent -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $temporaryDirectory 'Program.cs') -Value $programContent -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $temporaryDirectory 'NuGet.Config') -Value $nugetConfigContent -Encoding UTF8

    & dotnet restore (Join-Path $temporaryDirectory 'NuGetTest.csproj') `
        --configfile (Join-Path $temporaryDirectory 'NuGet.Config')
    if ($LASTEXITCODE -ne 0) {
        throw "Local NuGet package restore failed with exit code $LASTEXITCODE."
    }

    & dotnet run `
        --project (Join-Path $temporaryDirectory 'NuGetTest.csproj') `
        --configuration Release `
        --no-restore
    if ($LASTEXITCODE -ne 0) {
        throw "Local NuGet package execution test failed with exit code $LASTEXITCODE."
    }

    Write-Output "Local NuGet package installation test passed: $PackagePath"
}
finally {
    if (Test-Path -LiteralPath $temporaryDirectory) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force
    }
}
