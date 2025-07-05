using namespace System.Net

function Invoke-ExecPartnerMode {
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

    $Table = Get-CippTable -tablename 'tenantMode'
    if ($Request.Body.TenantMode) {
        Add-CIPPAzDataTableEntity @Table -Entity @{
            PartitionKey = 'Setting'
            RowKey       = 'PartnerModeSetting'
            state        = $Request.Body.TenantMode
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

        return @{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{
                Results = @(
                    @{
                        resultText = "Set Tenant mode to $($Request.Body.TenantMode)"
                        state      = 'success'
                    }
                )
            }
        }
    }

    if ($Request.Query.action -eq 'ListCurrent') {
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

        return @{
            StatusCode = [HttpStatusCode]::OK
            Body       = $CurrentState
        }
    }
}
