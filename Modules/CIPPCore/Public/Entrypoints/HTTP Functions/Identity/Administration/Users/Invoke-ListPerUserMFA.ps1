using namespace System.Net

function Invoke-ListPerUserMFA {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $User = $Request.Headers
    Write-LogMessage -Headers $User -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Parse query parameters
    $Tenant = $Request.query.tenantFilter
    try {
        $AllUsers = [System.Convert]::ToBoolean($Request.query.allUsers)
    } catch {
        $AllUsers = $false
    }
    $UserId = $Request.query.userId

    # Get the MFA state for the user/all users
    try {
        if ($AllUsers -eq $true) {
            $Results = Get-CIPPPerUserMFA -TenantFilter $Tenant -AllUsers $true
        } else {
            $Results = Get-CIPPPerUserMFA -TenantFilter $Tenant -UserId $UserId
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $Results = "Failed to get MFA State for $UserId : $ErrorMessage"
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })


}
