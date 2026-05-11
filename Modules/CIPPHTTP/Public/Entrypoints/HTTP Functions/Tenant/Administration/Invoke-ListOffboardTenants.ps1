function Invoke-ListOffboardTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Administration.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint

    try {
        $TenantAccess = Test-CIPPAccess -Request $Request -TenantList
        $Tenants = @(Get-Tenants -IncludeAll)

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
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })
}
