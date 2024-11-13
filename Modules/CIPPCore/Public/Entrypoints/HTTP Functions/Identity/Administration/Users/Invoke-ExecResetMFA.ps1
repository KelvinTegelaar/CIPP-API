using namespace System.Net

Function Invoke-ExecResetMFA {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $UserID = $Request.Query.ID
    try {
        $Results = Remove-CIPPUserMFA -UserPrincipalName $UserID -TenantFilter $TenantFilter -ExecutingUser $request.headers.'x-ms-client-principal'
    } catch {
        $Results = [pscustomobject]@{'Results' = "Failed to reset MFA methods for $($Request.Query.ID): $(Get-NormalizedError -message $_.Exception.Message)" }
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to reset MFA for user $($Request.Query.ID): $($_.Exception.Message)" -Sev 'Error' -LogData (Get-CippException -Exception $_)
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
