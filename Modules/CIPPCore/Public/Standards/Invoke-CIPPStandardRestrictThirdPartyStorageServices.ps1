function Invoke-CIPPStandardRestrictThirdPartyStorageServices {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) RestrictThirdPartyStorageServices
    .SYNOPSIS
        (Label) Restrict third-party storage services in Microsoft 365 on the web
    .DESCRIPTION
        (Helptext) Restricts third-party storage services in Microsoft 365 on the web by managing the Microsoft 365 on the web service principal. This disables integrations with services like Dropbox, Google Drive, Box, and other third-party storage providers.
        (DocsDescription) Third-party storage can be enabled for users in Microsoft 365, allowing them to store and share documents using services such as Dropbox, alongside OneDrive and team sites. This standard ensures Microsoft 365 on the web third-party storage services are restricted by creating and disabling the Microsoft 365 on the web service principal (appId: c1f33bc0-bdb4-4248-ba9b-096807ddb43e). By using external storage services an organization may increase the risk of data breaches and unauthorized access to confidential information. Additionally, third-party services may not adhere to the same security standards as the organization, making it difficult to maintain data privacy and security. Impact is highly dependent upon current practices - if users do not use other storage providers, then minimal impact is likely. However, if users regularly utilize providers outside of the tenant this will affect their ability to continue to do so.
    .NOTES
        CAT
            Global Standards
        TAG
            "CIS"
        ADDEDCOMPONENT
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-06-06
        POWERSHELLEQUIVALENT
            New-MgServicePrincipal and Update-MgServicePrincipal
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param ($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'RestrictThirdPartyStorageServices'

    $AppId = 'c1f33bc0-bdb4-4248-ba9b-096807ddb43e'
    $Uri = "https://graph.microsoft.com/beta/servicePrincipals?`$filter=appId eq '$AppId'"

    try {
        $CurrentState = New-GraphGetRequest -Uri $Uri -tenantid $Tenant | Select-Object displayName, accountEnabled, appId
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not get current state for Microsoft 365 on the web service principal. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Return
    }

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate third-party storage services restriction'

        # Check if service principal is already disabled
        if ($CurrentState.accountEnabled -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Third-party storage services are already restricted (service principal is disabled).' -sev Info
        } else {
            # Disable the service principal to restrict third-party storage services
            try {
                $DisableBody = @{
                    accountEnabled = $false
                } | ConvertTo-Json -Depth 10 -Compress

                # Normal /servicePrincipal/AppId does not find the service principal, so gotta use the Upsert method. Also handles if the service principal does not exist nicely.
                # https://learn.microsoft.com/en-us/graph/api/serviceprincipal-upsert?view=graph-rest-beta&tabs=http
                $UpdateUri = "https://graph.microsoft.com/beta/servicePrincipals(appId='$AppId')"
                $null = New-GraphPostRequest -Uri $UpdateUri -Body $DisableBody -TenantID $Tenant -Type PATCH

                # Refresh the current state after disabling
                $CurrentState = New-GraphGetRequest -Uri $Uri -tenantid $Tenant | Select-Object displayName, accountEnabled, appId
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Successfully restricted third-party storage services in Microsoft 365 on the web.' -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to restrict third-party storage services. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($CurrentState.accountEnabled -eq $false) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Third-party storage services are restricted (service principal is disabled).' -sev Info
        } else {
            Write-StandardsAlert -message 'Third-party storage services are not restricted in Microsoft 365 on the web' -object $CurrentState -tenant $Tenant -standardName 'RestrictThirdPartyStorageServices' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Third-party storage services are not restricted.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        if ($null -eq $CurrentState.accountEnabled -or $CurrentState.accountEnabled -eq $true) {
            Set-CIPPStandardsCompareField -FieldName 'standards.RestrictThirdPartyStorageServices' -FieldValue $false -Tenant $Tenant
            Add-CIPPBPAField -FieldName 'ThirdPartyStorageServicesRestricted' -FieldValue $false -StoreAs bool -Tenant $Tenant
        } else {
            $CorrectState = $CurrentState.accountEnabled -eq $false ? $true : $false
            Set-CIPPStandardsCompareField -FieldName 'standards.RestrictThirdPartyStorageServices' -FieldValue $CorrectState -Tenant $Tenant
            Add-CIPPBPAField -FieldName 'ThirdPartyStorageServicesRestricted' -FieldValue $CorrectState -StoreAs bool -Tenant $Tenant
        }
    }
}
