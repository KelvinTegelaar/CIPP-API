function Invoke-ExecSAMRoles {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $SAMRolesTable = Get-CIPPTable -tablename 'SAMRoles'
    switch ($Request.Query.Action) {
        'Update' {
            $Entity = [pscustomobject]@{
                PartitionKey = 'SAMRoles'
                RowKey       = 'SAMRoles'
                Roles        = [string](ConvertTo-Json -Depth 5 -Compress -InputObject $Request.Body.Roles)
                Tenants      = [string](ConvertTo-Json -Depth 5 -Compress -InputObject $Request.Body.Tenants)
            }
            $null = Add-CIPPAzDataTableEntity @SAMRolesTable -Entity $Entity -Force
            $Body = [pscustomobject]@{'Results' = 'Successfully updated SAM roles' }
        }
        default {
            $SAMRoles = Get-CIPPAzDataTableEntity @SAMRolesTable
            $Body = @{
                'Roles'    = $SAMRoles.Roles | ConvertFrom-Json
                'Tenants'  = $SAMRoles.Tenants | ConvertFrom-Json
                'Metadata' = @{
                    'RoleCount'   = $SAMRoles.Roles.Count
                    'TenantCount' = $SAMRoles.Tenants.Count
                }
            } | ConvertTo-Json -Depth 5
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
