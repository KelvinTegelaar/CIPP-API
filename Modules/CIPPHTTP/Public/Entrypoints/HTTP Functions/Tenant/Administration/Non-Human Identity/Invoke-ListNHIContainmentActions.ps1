function Invoke-ListNHIContainmentActions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.Read
    .SYNOPSIS
        Lists the containment actions for a non-human identity (NHI) compromise.
    .DESCRIPTION
        Returns the catalog of NHI containment actions: id, label, description, impact, whether it is reversible, whether it runs by default, its run order, the case section and parameter its targets come from, and what releasing the case does with it.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Body = @(Get-CIPPNhiContainmentActions)
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Body = @{ Results = "Failed to list NHI containment actions: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
