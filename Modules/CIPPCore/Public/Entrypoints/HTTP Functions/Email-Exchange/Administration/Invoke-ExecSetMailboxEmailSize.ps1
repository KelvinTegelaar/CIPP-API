using namespace System.Net

Function Invoke-ExecSetMailboxEmailSize {
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
    Write-LogMessage -Headers $User -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $Tenant = $Request.Body.tenantFilter
    $UserPrincipalName = $Request.Body.UPN
    $UserID = $Request.Body.id
    $MaxSendSize = $Request.Body.maxSendSize
    $MaxReceiveSize = $Request.Body.maxReceiveSize

    try {
        $Params = @{
            TenantFilter      = $Tenant
            APIName           = $APIName
            Headers           = $Headers
            UserPrincipalName = $UserPrincipalName
            UserID            = $UserID
            MaxSendSize       = $MaxSendSize
            MaxReceiveSize    = $MaxReceiveSize
        }
        if ([string]::IsNullOrWhiteSpace($MaxSendSize)) { $Params.Remove('MaxSendSize') }
        if ([string]::IsNullOrWhiteSpace($MaxReceiveSize)) { $Params.Remove('MaxReceiveSize') }
        $Result = Set-CippMaxEmailSize @Params
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = "$($_.Exception.Message)"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })

}
