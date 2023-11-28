using namespace System.Net

Function Invoke-ListUserSigninLogs {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $UserID = $Request.Query.UserID
    try {
        $URI = "https://graph.microsoft.com/beta/auditLogs/signIns?`$filter=(userId eq '$UserID')&`$top=50&`$orderby=createdDateTime desc" 
        Write-Host $URI
        $GraphRequest = New-GraphGetRequest -uri $URI -tenantid $TenantFilter -noPagination $true -verbose | Select-Object @{ Name = 'Date'; Expression = { $(($_.createdDateTime | Out-String) -replace '\r\n') } },
        id,
        @{ Name = 'Application'; Expression = { $_.resourceDisplayName } },
        @{ Name = 'LoginStatus'; Expression = { $_.status.errorCode } },
        @{ Name = 'ConditionalAccessStatus'; Expression = { $_.conditionalAccessStatus } },
        @{ Name = 'OverallLoginStatus'; Expression = { if (($_.conditionalAccessStatus -eq 'Success' -or 'Not Applied') -and $_.status.errorCode -eq 0) { 'Success' } else { 'Failed' } } },
        @{ Name = 'IPAddress'; Expression = { $_.ipAddress } },
        @{ Name = 'Town'; Expression = { $_.location.city } },
        @{ Name = 'State'; Expression = { $_.location.state } },
        @{ Name = 'Country'; Expression = { $_.location.countryOrRegion } },
        @{ Name = 'Device'; Expression = { $_.deviceDetail.displayName } },
        @{ Name = 'DeviceCompliant'; Expression = { $_.deviceDetail.isCompliant } },
        @{ Name = 'OS'; Expression = { $_.deviceDetail.operatingSystem } },
        @{ Name = 'Browser'; Expression = { $_.deviceDetail.browser } },
        @{ Name = 'AppliedCAPs'; Expression = { ($_.appliedConditionalAccessPolicies | ForEach-Object { @{Result = $_.result; Name = $_.displayName } }) } },
        @{ Name = 'AdditionalDetails'; Expression = { $_.status.additionalDetails } },
        @{ Name = 'FailureReason'; Expression = { $_.status.failureReason } },
        @{ Name = 'FullDetails'; Expression = { $_ } }
        # Associate values to output bindings by calling 'Push-OutputBinding'.
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @($GraphRequest)
            })
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to retrieve Sign In report: $($_.Exception.message) " -Sev 'Error' -tenant $TenantFilter
        # Associate values to output bindings by calling 'Push-OutputBinding'.
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = '500'
                Body       = $(Get-NormalizedError -message $_.Exception.message)
            })
    }


}
