using namespace System.Net

Function Invoke-ListTenantDetails {
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

    $tenantfilter = $Request.Query.TenantFilter

    try {
        $org = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/organization' -tenantid $tenantfilter | Select-Object displayName, id, city, country, countryLetterCode, street, state, postalCode,
        @{ Name = 'businessPhones'; Expression = { $_.businessPhones -join ', ' } },
        @{ Name = 'technicalNotificationMails'; Expression = { $_.technicalNotificationMails -join ', ' } },
        tenantType, createdDateTime, onPremisesLastPasswordSyncDateTime, onPremisesLastSyncDateTime, onPremisesSyncEnabled, assignedPlans

        # Respond with the successful output
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $org
            })
    } catch {
        # Log the exception message
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Error: $($_.Exception.Message)" -Sev 'Error'

        # Respond with a 500 error and include the exception message in the response body
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = Get-NormalizedError -message $_.Exception.Message
            })
    }
}
