using namespace System.Net

Function Invoke-ListBreachesTenant {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $users = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$select=UserPrincipalName,mail" -tenantid $Request.query.TenantFilter
    $usersResults = foreach ($user in $users) {
        $Results = Get-HIBPRequest "breachedaccount/$($user.UserPrincipalName)?truncateResponse=true"
        if ($null -eq $Results) {
            $Results = 'No breaches found.'
        }
        [PSCustomObject]@{
            user     = $user.UserPrincipalName
            breaches = $Results
        }
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($usersResults)
        })

}
