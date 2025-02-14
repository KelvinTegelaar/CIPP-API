using namespace System.Net

Function Invoke-ListTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint

    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $TenantAccess = Test-CIPPAccess -Request $Request -TenantList
    Write-Host "Tenant Access: $TenantAccess"

    if ($TenantAccess -notcontains 'AllTenants') {
        $AllTenantSelector = $false
    } else {
        $AllTenantSelector = $Request.Query.AllTenantSelector
    }

    # Clear Cache
    if ($Request.Query.ClearCache -eq $true) {
        Remove-CIPPCache -tenantsOnly $Request.Query.TenantsOnly

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

        $GraphRequest = [pscustomobject]@{'Results' = 'Cache has been cleared and a tenant refresh is queued.' }
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $GraphRequest
            })
        #Get-Tenants -IncludeAll -TriggerRefresh
        return
    }
    if ($Request.Query.TriggerRefresh) {
        if ($Request.Query.TenantFilter -and $Request.Query.TenantFilter -ne 'AllTenants') {
            Get-Tenants -TriggerRefresh -TenantFilter $Request.Query.TenantFilter
        } else {
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
    }
    try {
        $tenantfilter = $Request.Query.TenantFilter
        $Tenants = Get-Tenants -IncludeErrors -SkipDomains
        if ($TenantAccess -notcontains 'AllTenants') {
            $Tenants = $Tenants | Where-Object -Property customerId -In $TenantAccess
        }

        if ($null -eq $TenantFilter -or $TenantFilter -eq 'null') {
            $TenantList = [system.collections.generic.list[object]]::new()
            if ($AllTenantSelector -eq $true) {
                $TenantList.Add(@{
                        customerId        = 'AllTenants'
                        defaultDomainName = 'AllTenants'
                        displayName       = '*All Tenants'
                        domains           = 'AllTenants'
                        GraphErrorCount   = 0
                    }) | Out-Null

                if (($Tenants).length -gt 1) {
                    $TenantList.AddRange($Tenants) | Out-Null
                } elseif ($Tenants) {
                    $TenantList.Add($Tenants) | Out-Null
                }
                $body = $TenantList
            } else {
                $Body = $Tenants
            }
        } else {
            $body = $Tenants | Where-Object -Property defaultDomainName -EQ $Tenantfilter
        }

        Write-LogMessage -headers $Request.Headers -tenant $Tenantfilter -API $APINAME -message 'Listed Tenant Details' -Sev 'Debug'
    } catch {
        Write-LogMessage -headers $Request.Headers -tenant $Tenantfilter -API $APINAME -message "List Tenant failed. The error is: $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{
            'Results'         = "Failed to retrieve tenants: $($_.Exception.Message)"
            defaultDomainName = ''
            displayName       = 'Failed to retrieve tenants. Perform a permission check.'
            customerId        = ''

        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Body)
        })


}
