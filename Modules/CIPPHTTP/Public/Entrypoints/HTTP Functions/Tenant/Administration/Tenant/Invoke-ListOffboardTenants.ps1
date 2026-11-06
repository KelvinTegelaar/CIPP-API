function Invoke-ListOffboardTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Administration.ReadWrite
    .DESCRIPTION
        Lists tenants available for offboarding, including tenants in error state.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint

    try {
        $TenantAccess = Test-CIPPAccess -Request $Request -TenantList
    } catch {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body       = @([PSCustomObject]@{ Results = "Failed to list offboarding tenants. $($_.Exception.Message)" })
            })
    }

    try {
        # Partner tenants cannot be offboarded, so they don't belong in this list
        $PartnerIds = @((Get-CIPPPartnerTenantList).partnerTenantId)
        $Tenants = @(Get-Tenants -IncludeAll | Where-Object { $_.isPartnerTenantRow -ne $true -and $_.customerId -notin $PartnerIds -and $_.customerId -ne $env:TenantID })

        if ($TenantAccess -notcontains 'AllTenants') {
            $Tenants = @($Tenants | Where-Object -Property customerId -In $TenantAccess)
        }

        $Results = @($Tenants | Sort-Object -Property displayName)
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -message "Failed to list offboarding tenants. $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Results = @([PSCustomObject]@{
                Results = "Failed to list offboarding tenants. $($ErrorMessage.NormalizedError)"
            })
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })
}
