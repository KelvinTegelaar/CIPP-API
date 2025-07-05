function Invoke-ExecSAMRoles {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

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
            $Roles = @($SAMRoles.Roles | ConvertFrom-Json)
            $Tenants = @($SAMRoles.Tenants | ConvertFrom-Json)
            $Body = @{
                'Roles'    = $Roles
                'Tenants'  = $Tenants
                'Metadata' = @{
                    'RoleCount'   = ($Roles | Measure-Object).Count
                    'TenantCount' = ($Tenants | Measure-Object).Count
                }
            } | ConvertTo-Json -Depth 5
        }
    }

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    }
}
