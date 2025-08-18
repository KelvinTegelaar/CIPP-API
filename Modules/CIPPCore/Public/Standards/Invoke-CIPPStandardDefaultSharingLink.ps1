function Invoke-CIPPStandardDefaultSharingLink {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) DefaultSharingLink
    .SYNOPSIS
        (Label) Set Default Sharing Link Settings
    .DESCRIPTION
        (Helptext) Configure the SharePoint default sharing link type and permission. This setting controls both the type of sharing link created by default and the permission level assigned to those links.
        (DocsDescription) Sets the default sharing link type (Direct or Internal) and permission (View) in SharePoint and OneDrive. Direct sharing means links only work for specific people, while Internal sharing means links work for anyone in the organization.
    .NOTES
        CAT
            SharePoint Standards
        TAG
        ADDEDCOMPONENT
            [{"type":"autoComplete","multiple":false,"creatable":false,"label":"Default Sharing Link Type","name":"standards.DefaultSharingLink.SharingLinkType","options":[{"label":"Direct - Only specific people","value":"Direct"},{"label":"Internal - Anyone in the organization","value":"Internal"}]}]
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-06-13
        POWERSHELLEQUIVALENT
            Set-SPOTenant -DefaultSharingLinkType [Direct|Internal] -DefaultLinkPermission View
        RECOMMENDEDBY
            CIS
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'DefaultSharingLink' -TenantFilter $Tenant -RequiredCapabilities @('SHAREPOINTWAC', 'SHAREPOINTSTANDARD', 'SHAREPOINTENTERPRISE', 'SHAREPOINTENTERPRISE_EDU','ONEDRIVE_BASIC', 'ONEDRIVE_ENTERPRISE')

    # Determine the desired sharing link type (default to Internal if not specified)

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.
    $DesiredSharingLinkType = $Settings.SharingLinkType.value ?? 'Internal'

    # Map the string values to numeric values for SharePoint
    $SharingLinkTypeMap = @{
        'Direct'   = 1
        'Internal' = 2
        'Anyone'   = 3
    }
    $DesiredSharingLinkTypeValue = $SharingLinkTypeMap[$DesiredSharingLinkType]

    try {
        $CurrentState = Get-CIPPSPOTenant -TenantFilter $Tenant |
        Select-Object -Property _ObjectIdentity_, TenantFilter, DefaultSharingLinkType, DefaultLinkPermission
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the DefaultSharingLink state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    # Check if the current state matches the desired configuration
    $StateIsCorrect = ($CurrentState.DefaultSharingLinkType -eq $DesiredSharingLinkTypeValue) -and ($CurrentState.DefaultLinkPermission -eq 1)
    Write-Host "currentstate: $($CurrentState.DefaultSharingLinkType), $($CurrentState.DefaultLinkPermission). Desired: $DesiredSharingLinkTypeValue, 1"
    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Default sharing link settings are already configured correctly (Type: $DesiredSharingLinkType, Permission: View)" -Sev Info
        } else {
            $Properties = @{
                DefaultSharingLinkType = $DesiredSharingLinkTypeValue
                DefaultLinkPermission  = 1  # View
            }

            try {
                $CurrentState | Set-CIPPSPOTenant -Properties $Properties
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Successfully set default sharing link settings (Type: $DesiredSharingLinkType, Permission: View)" -Sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Failed to set default sharing link settings. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Default sharing link settings are configured correctly (Type: $DesiredSharingLinkType, Permission: View)" -Sev Info
        } else {
            # Determine current values for alert message
            $CurrentSharingType = switch ($CurrentState.DefaultSharingLinkType) {
                1 { 'Direct' }
                2 { 'Internal' }
                3 { 'Anyone' }
                default { 'Unknown' }
            }
            $CurrentPermission = switch ($CurrentState.DefaultLinkPermission) {
                0 { 'Edit' }
                1 { 'View' }
                2 { 'Edit' }
                default { 'Unknown' }
            }

            $Message = "Default sharing link settings are not configured correctly. Current: Type=$CurrentSharingType, Permission=$CurrentPermission. Expected: Type=$DesiredSharingLinkType, Permission=View"
            Write-StandardsAlert -message $Message -object $CurrentState -tenant $Tenant -standardName 'DefaultSharingLink' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message $Message -Sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'DefaultSharingLink' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
        if ($StateIsCorrect) {
            $FieldValue = $true
        } else {
            $FieldValue = $CurrentState
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.DefaultSharingLink' -FieldValue $FieldValue -Tenant $Tenant
    }
}
