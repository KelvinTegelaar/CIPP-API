using namespace System.Net

Function Invoke-ExecPartnerMode {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $roles = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($request.headers.'x-ms-client-principal')) | ConvertFrom-Json).userRoles
    if ('superadmin' -notin $roles) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body       = @{ error = 'You do not have permission to perform this action.' }
            })
        return
    } else {
        $Table = Get-CippTable -tablename 'tenantMode'
        if ($request.body.TenantMode) {
            Add-CIPPAzDataTableEntity @Table -Entity @{
                PartitionKey = 'Setting'
                RowKey       = 'PartnerModeSetting'
                state        = $request.body.TenantMode
            } -Force

            if ($Request.Body.TenantMode -eq 'default') {
                $Table = Get-CippTable -tablename 'Tenants'
                $Tenant = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Tenants' and RowKey eq '$($env:TenantID)'" -Property RowKey, PartitionKey, customerId, displayName
                if ($Tenant) {
                    try {
                        Remove-AzDataTableEntity -Force @Table -Entity $Tenant
                    } catch {
                    }
                }
            }

            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = @{
                        results = @(
                            @{
                                result   = "Set Tenant mode to $($Request.body.TenantMode)"
                                copyInfo = $null
                                state    = 'info'
                            }
                        )
                    }
                })

        }

        if ($request.query.action -eq 'ListCurrent') {
            $CurrentState = Get-CIPPAzDataTableEntity @Table
            $CurrentState = if (!$CurrentState) {
                [PSCustomObject]@{
                    TenantMode = 'default'
                }
            } else {
                [PSCustomObject]@{
                    TenantMode = $CurrentState.state
                }
            }

            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = $CurrentState
                })
        }
    }
}
