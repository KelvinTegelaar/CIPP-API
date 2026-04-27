function Get-CIPPHttpFunctions {
    param(
        [switch]$ByRole,
        [switch]$ByRoleGroup
    )

    try {
        if (-not $script:CIPPFunctionPermissions) {
            if ($global:CIPPFunctionPermissions) {
                $script:CIPPFunctionPermissions = $global:CIPPFunctionPermissions
            } else {
                $PermissionsFileJson = Join-Path $env:CIPPRootPath 'Config\function-permissions.json'

                if (Test-Path $PermissionsFileJson) {
                    try {
                        $script:CIPPFunctionPermissions = [System.IO.File]::ReadAllText($PermissionsFileJson) | ConvertFrom-Json -AsHashtable
                        Write-Debug "Loaded $($script:CIPPFunctionPermissions.Count) function permissions from JSON cache"
                    } catch {
                        Write-Warning "Failed to load function permissions from JSON: $($_.Exception.Message)"
                    }
                }
            }
        }

        $Functions = Get-Command -Module CIPPHTTP | Where-Object { $_.Visibility -eq 'Public' -and $_.Name -match 'Invoke-*' }
        $Results = foreach ($Function in $Functions) {
            $Role = $null
            $Functionality = $null
            $Description = $null

            if ($script:CIPPFunctionPermissions -and $script:CIPPFunctionPermissions.ContainsKey($Function.Name)) {
                $PermissionData = $script:CIPPFunctionPermissions[$Function.Name]
                $Role = $PermissionData['Role']
                $Functionality = $PermissionData['Functionality']
                if ($PermissionData.ContainsKey('Description')) {
                    $Description = $PermissionData['Description']
                }
            } else {
                $Help = Get-Help $Function -ErrorAction SilentlyContinue
                if (-not $Help) { continue }
                $Role = $Help.Role
                $Functionality = $Help.Functionality
                $Description = $Help.Description
            }

            if ($Functionality -notmatch 'Entrypoint') { continue }
            if ($Role -eq 'Public') { continue }
            [PSCustomObject]@{
                Function    = $Function.Name
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
