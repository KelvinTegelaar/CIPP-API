using namespace System.Net

function Invoke-PublicPhishingCheck {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Public
    #>
    [CmdletBinding()]

    #this has been switched to the external free service by cyberdrain at clone.cipp.app due to extreme numbers of executions if selfhosted.
    param($Request, $TriggerMetadata)

    $Tenant = Get-Tenants -TenantFilter $Request.body.TenantId

    if ($Request.body.Cloned -and $Tenant.customerId -eq $Request.body.TenantId) {
        Write-AlertMessage -message $Request.body.AlertMessage -sev 'Alert' -tenant $Request.body.TenantId
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = 'OK'
        })
}
