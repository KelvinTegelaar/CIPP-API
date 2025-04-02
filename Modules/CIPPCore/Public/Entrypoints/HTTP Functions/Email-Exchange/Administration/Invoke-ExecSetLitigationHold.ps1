function Invoke-ExecSetLitigationHold {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message 'Accessed this API' -Sev 'Debug'

    # Interact with the query or body of the request
    $TenantFilter = $Request.Body.tenantFilter
    $DisableLitHold = $Request.Body.disable -as [bool]
    Write-Host "TenantFilter: $TenantFilter"
    Write-Host "DisableLitHold: $DisableLitHold"



}
