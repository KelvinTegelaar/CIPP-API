function Get-CIPPHttpFunctions {
    Param(
        [switch]$ByRole,
        [switch]$ByRoleGroup
    )

    try {
        $Functions = Get-Command -Module CIPPCore | Where-Object { $_.Visibility -eq 'Public' -and $_.Name -match 'Invoke-*' }
        $Results = foreach ($Function in $Functions) {
            $Help = Get-Help $Function
            if ($Help.Functionality -ne 'Entrypoint') { continue }
            if ($Help.Role -eq 'Public') { continue }
            [PSCustomObject]@{
                Function = $Function.Name
                Role     = $Help.Role
            }
        }

        if ($ByRole.IsPresent -or $ByRoleGroup.IsPresent) {
            $Results = $Results | Group-Object -Property Role | Select-Object -Property @{l = 'Permission'; e = { $_.Name -eq '' ? 'None' : $_.Name } }, Count, @{l = 'Functions'; e = { $_.Group.Function -replace 'Invoke-' } } | Sort-Object -Property Permission

            if ($ByRoleGroup.IsPresent) {
                $RoleGroup = @{}
                foreach ($Permission in $Results) {
                    $PermSplit = $Permission.Permission -split '\.'
                    if ($PermSplit.Count -ne 3) { continue }
                    if ($RoleGroup[$PermSplit[0]] -eq $null) { $RoleGroup[$PermSplit[0]] = @{} }
                    if ($RoleGroup[$PermSplit[0]][$PermSplit[1]] -eq $null) { $RoleGroup[$PermSplit[0]][$PermSplit[1]] = @{} }
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
