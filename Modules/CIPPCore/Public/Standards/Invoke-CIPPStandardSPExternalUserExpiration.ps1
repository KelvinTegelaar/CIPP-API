function Invoke-CIPPStandardSPExternalUserExpiration {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SPExternalUserExpiration
    .SYNOPSIS
        (Label) Set guest access to expire automatically
    .DESCRIPTION
        (Helptext) Ensure guest access to a site or OneDrive will expire automatically
        (DocsDescription) Ensure guest access to a site or OneDrive will expire automatically
    .NOTES
        CAT
            SharePoint Standards
        TAG
            "CIS"
        ADDEDCOMPONENT
            {"type":"number","name":"standards.SPExternalUserExpiration.Days","label":"Days until expiration (Default 60)"}
        IMPACT
            Medium Impact
        ADDEDDATE
            2024-07-09
        POWERSHELLEQUIVALENT
            Set-SPOTenant -ExternalUserExpireInDays 30 -ExternalUserExpirationRequired \$True
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'SPExternalUserExpiration' -TenantFilter $Tenant -RequiredCapabilities @('SHAREPOINTWAC', 'SHAREPOINTSTANDARD', 'SHAREPOINTENTERPRISE', 'ONEDRIVE_BASIC', 'ONEDRIVE_ENTERPRISE')

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.

    try {
        $CurrentState = Get-CIPPSPOTenant -TenantFilter $Tenant |
        Select-Object -Property _ObjectIdentity_, TenantFilter, ExternalUserExpireInDays, ExternalUserExpirationRequired
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the SPExternalUserExpiration state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $StateIsCorrect = ($CurrentState.ExternalUserExpireInDays -eq $Settings.Days) -and
    ($CurrentState.ExternalUserExpirationRequired -eq $true)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'SharePoint External User Expiration is already enabled.' -Sev Info
        } else {
            $Properties = @{
                ExternalUserExpireInDays       = $Settings.Days
                ExternalUserExpirationRequired = $true
            }

            try {
                $CurrentState | Set-CIPPSPOTenant -Properties $Properties
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully set External User Expiration' -Sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to set External User Expiration. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'External User Expiration is enabled' -Sev Info
        } else {
            $Message = 'External User Expiration is not set to the desired value.'
            Write-StandardsAlert -message $Message -object $CurrentState -tenant $Tenant -standardName 'SPExternalUserExpiration' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message $Message -Sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'ExternalUserExpiration' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
        if ($StateIsCorrect) {
            $FieldValue = $true
        } else {
            $FieldValue = $CurrentState
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.SPExternalUserExpiration' -FieldValue $FieldValue -TenantFilter $Tenant
        Add-CIPPBPAField -FieldName 'standards.SPExternalUserExpiration' -FieldValue $FieldValue -StoreAs bool -Tenant $Tenant
    }
}
