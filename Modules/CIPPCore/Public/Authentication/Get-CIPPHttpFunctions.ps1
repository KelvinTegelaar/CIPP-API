function Get-CIPPHttpFunctions {
    param(
        [switch]$ByRole,
        [switch]$ByRoleGroup
    )

    try {
        # Load function-metadata.json cache
        $ModuleRoot = (Get-Module -Name CIPPCore).ModuleBase
        $CIPPRoot = (Get-Item $ModuleRoot).Parent.Parent
        $MetadataPath = Join-Path $CIPPRoot 'Config\function-metadata.json'

        # Load metadata if not already cached
        if (-not $global:metadata -and (Test-Path $MetadataPath)) {
            $global:metadata = Get-Content -Path $MetadataPath -Raw | ConvertFrom-Json
        }

        # Process functions
        if ($global:metadata) {
            $Functions = $global:metadata.Functions.PSObject.Properties | Where-Object { $_.Name -match '^Invoke-' }
            $Results = foreach ($Function in $Functions) {
                $Help = $Function.Value
                if ($Help.Functionality -notmatch 'Entrypoint') { continue }
                if ($Help.Role -eq 'Public') { continue }
                [PSCustomObject]@{
                    Function    = $Function.Name
                    Role        = $Help.Role
                    Description = @( @{Text = $Help.Description} )
                }
            }
        } else {
            Write-Debug "Metadata file not found at $MetadataPath"
            $Functions = Get-Command -Module CIPPCore | Where-Object { $_.Visibility -eq 'Public' -and $_.Name -match 'Invoke-*' }
            $Results = foreach ($Function in $Functions) {
                $Help = Get-Help $Function
                if ($Help.Functionality -notmatch 'Entrypoint') { continue }
                if ($Help.Role -eq 'Public') { continue }
                [PSCustomObject]@{
                    Function    = $Function.Name
                    Role        = $Help.Role
                    Description = $Help.Description
                }
            }
        }

        if ($ByRole.IsPresent -or $ByRoleGroup.IsPresent) {
            $Results = $Results | Group-Object -Property Role | Select-Object -Property @{l = 'Permission'; e = { $_.Name -eq '' ? 'None' : $_.Name } }, Count, @{l = 'Functions'; e = { $_.Group | Select-Object @{l = 'Name'; e = { $_.Function -replace 'Invoke-' } }, Description } } | Sort-Object -Property Permission
            if ($ByRoleGroup.IsPresent) {
                $RoleGroup = @{}
                foreach ($Permission in $Results) {
                    $PermSplit = $Permission.Permission -split '\.'
                    if ($PermSplit.Count -ne 3) { continue }
                    if ($null -eq $RoleGroup[$PermSplit[0]]) { $RoleGroup[$PermSplit[0]] = @{} }
                    if ($null -eq $RoleGroup[$PermSplit[0]][$PermSplit[1]]) { $RoleGroup[$PermSplit[0]][$PermSplit[1]] = @{} }
                    $RoleGroup[$PermSplit[0]][$PermSplit[1]][$PermSplit[2]] = @($Permission.Functions)
                }
                $Results = $RoleGroup
            }
        }
        $Results
    } catch {
        "Function Error $($_.Exception.Message): $($_.InvocationInfo.PositionMessage)"
    }
}
