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
            Write-LogMessage -user $Request.Headers.'x-ms-client-principal' -API 'ExecCustomRole' -message "Saved custom role $($Request.Body.RoleName)" -Sev 'Info'
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
            Write-LogMessage -user $Request.Headers.'x-ms-client-principal' -API 'ExecCustomRole' -message "Deleted custom role $($Request.Body.RoleName)" -Sev 'Info'
            $Role = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($Request.Body.RoleName)'" -Property RowKey, PartitionKey
            Remove-AzDataTableEntity @Table -Entity $Role
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
                    $Role.Permissions = $Role.Permissions | ConvertFrom-Json
                    if ($Role.AllowedTenants) {
                        $Role.AllowedTenants = @($Role.AllowedTenants | ConvertFrom-Json)
                    } else {
                        $Role | Add-Member -NotePropertyName AllowedTenants -NotePropertyValue @() -Force
                    }
                    if ($Role.BlockedTenants) {
                        $Role.BlockedTenants = @($Role.BlockedTenants | ConvertFrom-Json)
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
