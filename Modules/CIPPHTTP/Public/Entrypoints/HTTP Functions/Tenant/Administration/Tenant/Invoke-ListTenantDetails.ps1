Function Invoke-ListTenantDetails {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter

    try {
        $org = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/organization' -tenantid $TenantFilter | Select-Object displayName, id, city, country, countryLetterCode, street, state, postalCode,
        @{ Name = 'businessPhones'; Expression = { $_.businessPhones -join ', ' } },
        @{ Name = 'technicalNotificationMails'; Expression = { $_.technicalNotificationMails -join ', ' } },
        tenantType, createdDateTime, onPremisesLastPasswordSyncDateTime, onPremisesLastSyncDateTime, onPremisesSyncEnabled, assignedPlans

        $customProperties = Get-TenantProperties -customerId $TenantFilter
        $org | Add-Member -MemberType NoteProperty -Name 'customProperties' -Value $customProperties

        $Groups = (Get-TenantGroups -TenantFilter $TenantFilter) ?? @()
        $org | Add-Member -MemberType NoteProperty -Name 'Groups' -Value @($Groups)
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $org = "Failed to retrieve tenant details: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $org -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $org
        })
}
