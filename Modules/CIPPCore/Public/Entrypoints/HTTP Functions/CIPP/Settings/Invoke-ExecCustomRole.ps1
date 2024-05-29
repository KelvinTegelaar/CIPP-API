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
            $Role = @{
                'PartitionKey'   = 'CustomRoles'
                'RowKey'         = "$($Request.Body.RoleName)"
                'Permissions'    = "$($Request.Body.Permissions | ConvertTo-Json -Compress)"
                'AllowedTenants' = "$($Request.Body.AllowedTenants | ConvertTo-Json -Compress)"
            }
            Add-CIPPAzDataTableEntity @Table -Entity $Role -Force | Out-Null
            $Body = @{Results = 'Custom role saved' }
        }
        'Delete' {
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
                    $Role.AllowedTenants = @($Role.AllowedTenants | ConvertFrom-Json)
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
