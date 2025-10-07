function Invoke-ExecPartnerMode {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)


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
        } elseif ($Request.Body.TenantMode -eq 'PartnerTenantAvailable') {
            $InputObject = [PSCustomObject]@{
                Batch            = @(
                    @{
                        FunctionName = 'UpdateTenants'
                    }
                )
                OrchestratorName = 'UpdateTenants'
                SkipLog          = $true
            }
            Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Compress -Depth 5)
        }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{
                    results = @(
                        @{
                            resultText = "Set Tenant mode to $($Request.body.TenantMode)"
                            state      = 'success'
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

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $CurrentState
            })
    }

}
