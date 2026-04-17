function Invoke-CIPPStandardSPDirectSharing {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SPDirectSharing
    .SYNOPSIS
        (Label) Default sharing to Direct users
    .DESCRIPTION
        (Helptext) This standard has been deprecated in favor of the Default Sharing Link standard.
        (DocsDescription) This standard has been deprecated in favor of the Default Sharing Link standard.
    .NOTES
        CAT
            SharePoint Standards
        TAG
        EXECUTIVETEXT
            Configures SharePoint and OneDrive to share files directly with specific people rather than creating anonymous links, improving security by ensuring only intended recipients can access shared documents. This reduces the risk of accidental data exposure through link sharing.
        ADDEDCOMPONENT
        IMPACT
            Medium Impact
        ADDEDDATE
            2024-07-09
        POWERSHELLEQUIVALENT
            Set-SPOTenant -DefaultSharingLinkType Direct
        RECOMMENDEDBY
            "CIS"
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'SPDirectSharing' -TenantFilter $Tenant -RequiredCapabilities @('SHAREPOINTWAC', 'SHAREPOINTSTANDARD', 'SHAREPOINTENTERPRISE', 'SHAREPOINTENTERPRISE_EDU', 'ONEDRIVE_BASIC', 'ONEDRIVE_ENTERPRISE')

    if ($TestResult -eq $false) {
        return $true
    } #we're done.


    Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'The default sharing to Direct users standard has been deprecated in favor of the "Set Default Sharing Link Settings" standard. Please update your standards to use new standard. However this will continue to function.' -Sev Alert
    try {
        $CurrentState = Get-CIPPSPOTenant -TenantFilter $Tenant |
            Select-Object -Property _ObjectIdentity_, TenantFilter, DefaultSharingLinkType
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the SPDirectSharing state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $StateIsCorrect = ($CurrentState.DefaultSharingLinkType -eq 'Direct' -or $CurrentState.DefaultSharingLinkType -eq 1)

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'SharePoint Default Direct Sharing is already enabled' -Sev Info
        } else {
            $Properties = @{
                DefaultSharingLinkType = 1
            }

            try {
                $CurrentState | Set-CIPPSPOTenant -Properties $Properties
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'Successfully set the SharePoint Default Direct Sharing to Direct' -Sev Info
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to set the SharePoint Default Direct Sharing to Direct. Error: $ErrorMessage" -Sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message 'SharePoint Direct Sharing is enabled' -Sev Info
        } else {
            $Message = 'SharePoint Default Direct Sharing is not enabled.'
            Write-StandardsAlert -message $Message -object $CurrentState -tenant $Tenant -standardName 'SPDirectSharing' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message $Message -Sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'DirectSharing' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant

        $CurrentValue = @{
            DefaultSharingLinkType = $CurrentState.DefaultSharingLinkType
        }
        $ExpectedValue = @{
            DefaultSharingLinkType = 1
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.SPDirectSharing' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
    }
}
