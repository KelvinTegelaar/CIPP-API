# Set CippRoot directory and process requirements.psd1
$CippRoot = (Get-Item $PSScriptRoot).Parent.FullName
$Requirements = & { Get-Content $CippRoot\requirements.psd1 -Raw | Invoke-Expression }
$Modules = $Requirements.Keys

# Exclude top level Modules and Tools directories
$Exclude = @(
    'Modules'
    'Tools'
)
$Files = Get-ChildItem $CippRoot -Exclude $Exclude | Get-ChildItem -Recurse -Include @('*.ps1', '*.psm1')

# Process each module in requirements
$ModuleTests = $Modules | ForEach-Object -Parallel {
    $ModuleRefs = 0
    $Success = $true
    $Module = $_

    try { 
        # Update module from gallery
        Save-Module -Name $Module -Path $using:CippRoot\Modules
        $ModuleInfo = Get-Module $using:CippRoot\Modules\$Module -ListAvailable

        # Remove old versions
        while (($ModuleInfo | Measure-Object).Count -gt 1) {
            Remove-Module $Module
            $RemoveVersion = $ModuleInfo | Sort-Object -Property Version | Select-Object -First 1
            Remove-Item -Path $RemoveVersion.ModuleBase -Recurse
        }

        # Check for module
        if (-not ($ModuleInfo)) {
            Import-Module $using:CippRoot\Modules\$Module -Force -ErrorAction Stop
        }

        # Get list of module commands
        $Commands = (Get-Command -Module $Module -ErrorAction Stop).Name
    
        # Review all powershell files and search for module commands
        $Files = foreach ($File in $using:Files) {
            $References = 0
            $Content = Get-Content -Raw $File
            $MatchedCommands = foreach ($Command in $Commands) {
                if ($Content | Select-String -Pattern $Command) {
                    $References++
                    $ModuleRefs++
                    $Command
                }
            }
            if ($References -gt 0) {
                [pscustomobject]@{
                    File       = $File | Resolve-Path -Relative
                    References = $References
                    Commands   = $MatchedCommands
                }
            }
        }
        if ($ModuleRefs -eq 0) {
            $ErrorMsg = 'No references found'
            $Success = $false
        }
    }
    catch {
        $ErrorMsg = $_.Exception.Message
        $Success = $false
    }

    # Return processed module object
    [pscustomobject]@{
        Module     = $Module
        Version    = $ModuleInfo.Version
        References = $ModuleRefs
        Files      = $Files
        ErrorMsg   = $ErrorMsg
        Success    = $Success
    }
}

$ModuleTests
