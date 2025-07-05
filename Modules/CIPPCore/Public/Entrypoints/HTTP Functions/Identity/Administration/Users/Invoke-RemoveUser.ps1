using namespace System.Net

function Invoke-RemoveUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $UserID = $Request.Query.ID ?? $Request.Body.ID
    $Username = $Request.Query.userPrincipalName ?? $Request.Body.userPrincipalName

    if (!$UserID) {
        return @{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{ Results = 'No User ID provided' }
        }
    }

    try {
        $Result = Remove-CIPPUser -UserID $UserID -Username $Username -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $Result = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = $Result }
    }
}
