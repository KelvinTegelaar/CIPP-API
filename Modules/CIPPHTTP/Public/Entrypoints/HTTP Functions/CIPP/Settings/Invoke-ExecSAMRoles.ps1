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

    $SAMRolesTable = Get-CIPPTable -tablename 'SAMRoles'
    switch ($Request.Query.Action) {
        'Update' {
            try {
                $Entity = [pscustomobject]@{
                    PartitionKey = 'SAMRoles'
                    RowKey       = 'SAMRoles'
                    Roles        = [string](ConvertTo-Json -Depth 5 -Compress -InputObject $Request.Body.Roles)
                    Tenants      = [string](ConvertTo-Json -Depth 5 -Compress -InputObject $Request.Body.Tenants)
                }
                $null = Add-CIPPAzDataTableEntity @SAMRolesTable -Entity $Entity -Force
                $Result = 'Successfully updated SAM roles'
                Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message $Result -Sev 'Info'
                $Body = [pscustomobject]@{'Results' = $Result }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $Result = "Failed to update SAM roles: $($ErrorMessage.NormalizedError)"
                Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message $Result -Sev 'Error' -LogData $ErrorMessage
                $Body = [pscustomobject]@{'Results' = $Result }
            }
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

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
