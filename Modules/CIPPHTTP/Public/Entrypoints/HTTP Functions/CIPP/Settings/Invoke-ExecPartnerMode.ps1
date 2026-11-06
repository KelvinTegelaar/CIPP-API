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

    $Table = Get-CippTable -tablename 'tenantMode'
    if ($request.body.TenantMode) {
        Add-CIPPAzDataTableEntity @Table -Entity @{
            PartitionKey = 'Setting'
            RowKey       = 'PartnerModeSetting'
            state        = $request.body.TenantMode
        } -Force

        if ($Request.Body.TenantMode -eq 'default') {
            # Remove every partner tenant's row, not just the primary's
            $Table = Get-CippTable -tablename 'Tenants'
            $PartnerIds = @((Get-CIPPPartnerTenantList).partnerTenantId)
            $PartnerRows = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Tenants'" | Where-Object { $_.customerId -in $PartnerIds -or $_.isPartnerTenantRow -eq $true }
            foreach ($Tenant in $PartnerRows) {
                try {
                    Remove-CIPPAzDataTableEntity -Force @Table -Entity $Tenant
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
            Start-CIPPOrchestrator -InputObject $InputObject
        }

        $Result = "Set Tenant mode to $($Request.body.TenantMode)"
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message $Result -Sev 'Info'

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{
                    results = @(
                        @{
                            resultText = $Result
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

