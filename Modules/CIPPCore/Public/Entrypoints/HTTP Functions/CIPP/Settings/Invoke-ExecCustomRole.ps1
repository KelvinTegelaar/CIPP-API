function Invoke-ExecCustomRole {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Table = Get-CippTable -tablename 'CustomRoles'
    switch ($Request.Query.Action) {
        'AddUpdate' {
            Write-LogMessage -headers $Request.Headers -API 'ExecCustomRole' -message "Saved custom role $($Request.Body.RoleName)" -Sev 'Info'
            $Role = @{
                'PartitionKey'   = 'CustomRoles'
                'RowKey'         = "$($Request.Body.RoleName.ToLower())"
                'Permissions'    = "$($Request.Body.Permissions | ConvertTo-Json -Compress)"
                'AllowedTenants' = "$($Request.Body.AllowedTenants | ConvertTo-Json -Compress)"
                'BlockedTenants' = "$($Request.Body.BlockedTenants | ConvertTo-Json -Compress)"
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Role -Force | Out-Null
            $Body = @{Results = 'Custom role saved' }
        }
        'Delete' {
            Write-LogMessage -headers $Request.Headers -API 'ExecCustomRole' -message "Deleted custom role $($Request.Body.RoleName)" -Sev 'Info'
            $Role = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($Request.Body.RoleName)'" -Property RowKey, PartitionKey
            Remove-AzDataTableEntity -Force @Table -Entity $Role
            $Body = @{Results = 'Custom role deleted' }
        }
        default {
            $Body = Get-CIPPAzDataTableEntity @Table

            if (!$Body) {
                $Body = @(
                    @{
                        RowKey = 'No custom roles found'
                    }
                )
            } else {
                $Body = foreach ($Role in $Body) {
                    try {
                        $Role.Permissions = $Role.Permissions | ConvertFrom-Json
                    } catch {
                        $Role.Permissions = ''
                    }
                    if ($Role.AllowedTenants) {
                        try {
                            $Role.AllowedTenants = @($Role.AllowedTenants | ConvertFrom-Json)
                        } catch {
                            $Role.AllowedTenants = ''
                        }
                    } else {
                        $Role | Add-Member -NotePropertyName AllowedTenants -NotePropertyValue @() -Force
                    }
                    if ($Role.BlockedTenants) {
                        try {
                            $Role.BlockedTenants = @($Role.BlockedTenants | ConvertFrom-Json)
                        } catch {
                            $Role.BlockedTenants = ''
                        }
                    } else {
                        $Role | Add-Member -NotePropertyName BlockedTenants -NotePropertyValue @() -Force
                    }
                    $Role
                }
                $Body = @($Body)
            }
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
