function Invoke-CIPPStandardunmanagedSync {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) unmanagedSync
    .SYNOPSIS
        (Label) Restrict access to SharePoint and OneDrive from unmanaged devices
    .DESCRIPTION
        (Helptext) Entra P1 required. Block or limit access to SharePoint and OneDrive content from unmanaged devices (those not hybrid AD joined or compliant in Intune). These controls rely on Microsoft Entra Conditional Access policies and can take up to 24 hours to take effect.
        (DocsDescription) Entra P1 required. Block or limit access to SharePoint and OneDrive content from unmanaged devices (those not hybrid AD joined or compliant in Intune). These controls rely on Microsoft Entra Conditional Access policies and can take up to 24 hours to take effect. 0 = Allow Access, 1 = Allow limited, web-only access, 2 = Block access. All information about this can be found in Microsofts documentation [here.](https://learn.microsoft.com/en-us/sharepoint/control-access-from-unmanaged-devices)
    .NOTES
        CAT
            SharePoint Standards
        TAG
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"name":"standards.unmanagedSync.state","label":"State","options":[{"label":"Allow limited, web-only access","value":"1"},{"label":"Block access","value":"2"}],"required":false}
        IMPACT
            High Impact
        ADDEDDATE
            2025-06-13
        POWERSHELLEQUIVALENT
            Set-SPOTenant -ConditionalAccessPolicy AllowFullAccess \| AllowLimitedAccess \| BlockAccess
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'unmanagedSync' -TenantFilter $Tenant -RequiredCapabilities @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1')
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'unmanagedSync'

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.

    $CurrentState = Get-CIPPSPOTenant -TenantFilter $Tenant | Select-Object _ObjectIdentity_, TenantFilter, ConditionalAccessPolicy

    $WantedState = [int]($Settings.state.value ?? 2) # Default to 2 (Block Access) if not set, for pre v8.0.3 standard compatibility
    $Label = $Settings.state.label ?? 'Block Access' # Default label if not set, for pre v8.0.3 standard compatibility
    $StateIsCorrect = ($CurrentState.ConditionalAccessPolicy -eq $WantedState)

    if ($Settings.remediate -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Sync for unmanaged devices is already correctly set to: $Label" -sev Info
        } else {
            try {
                $CurrentState | Set-CIPPSPOTenant -Properties @{ConditionalAccessPolicy = $WantedState }
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Successfully set the unmanaged Sync state to: $Label" -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to disable Sync for unmanaged devices: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {

        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Sync for unmanaged devices is correctly set to: $Label" -sev Info
        } else {
            Write-StandardsAlert -message "Sync for unmanaged devices is not correctly set to $Label, but instead $($CurrentState.ConditionalAccessPolicy)" -object $CurrentState -tenant $Tenant -standardName 'unmanagedSync' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Sync for unmanaged devices is not correctly set to $Label, but instead $($CurrentState.ConditionalAccessPolicy)" -sev Info
        }
    }

    if ($Settings.report -eq $true) {

        $State = $StateIsCorrect ? $true : $CurrentState.ConditionalAccessPolicy
        Set-CIPPStandardsCompareField -FieldName 'standards.unmanagedSync' -FieldValue $State -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'unmanagedSync' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
