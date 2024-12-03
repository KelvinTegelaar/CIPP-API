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

    $APIName = $TriggerMetadata.FunctionName
    $User = $request.headers.'x-ms-client-principal'
    Write-LogMessage -user $User -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

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
            $Results = Get-CIPPPerUserMFA -TenantFilter $Tenant -userId $UserId
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $Results = "Failed to get MFA State for $UserId : $ErrorMessage"
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })


}
