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
    if ($Request.body.Cloned) {
        Write-AlertMessage -message $Request.body.AlertMessage -sev 'Alert' -tenant $Request.body.TenantId
    }

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = 'OK'
    }
}
