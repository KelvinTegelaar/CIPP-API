function Get-CIPPHttpFunctions {
    param(
        [switch]$ByRole,
        [switch]$ByRoleGroup
    )

    try {
        # Load permissions from cache
        if (-not $global:CIPPFunctionPermissions) {
            $CIPPCoreModule = Get-Module -Name CIPPCore
            if ($CIPPCoreModule) {
                $PermissionsFileJson = Join-Path $CIPPCoreModule.ModuleBase 'lib' 'data' 'function-permissions.json'
                
                if (Test-Path $PermissionsFileJson) {
                    try {
                        $jsonData = Get-Content -Path $PermissionsFileJson -Raw | ConvertFrom-Json -AsHashtable
                        $global:CIPPFunctionPermissions = [System.Collections.Hashtable]::new([StringComparer]::OrdinalIgnoreCase)
                        foreach ($key in $jsonData.Keys) {
                            $global:CIPPFunctionPermissions[$key] = $jsonData[$key]
                        }
                        Write-Information "Loaded $($global:CIPPFunctionPermissions.Count) function permissions from JSON cache"
                    } catch {
                        Write-Warning "Failed to load function permissions from JSON: $($_.Exception.Message)"
                    }
                }
            }
        }

        $Functions = Get-Command -Module CIPPCore | Where-Object { $_.Visibility -eq 'Public' -and $_.Name -match 'Invoke-*' }
        $Results = foreach ($Function in $Functions) {
            $FunctionName = $Function.Name
            if ($global:CIPPFunctionPermissions -and $global:CIPPFunctionPermissions.ContainsKey($FunctionName)) {
                $PermissionData = $global:CIPPFunctionPermissions[$FunctionName]
                $Functionality = $PermissionData['Functionality']
                $Role = $PermissionData['Role']
                $Description = $PermissionData['Description']
            } else {
                $Help = Get-Help $Function
                $Functionality = $Help.Functionality
                $Role = $Help.Role
                $Description = $Help.Description
            }
            
            if ($Functionality -notmatch 'Entrypoint') { continue }
            if ($Role -eq 'Public') { continue }
            [PSCustomObject]@{
                Function    = $FunctionName
                Role        = $Role
                Description = $Description
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
