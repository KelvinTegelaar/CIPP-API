function Invoke-CIPPStandardFormsPhishingProtection {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) FormsPhishingProtection
    .SYNOPSIS
        (Label) Enable internal phishing protection for Forms
    .DESCRIPTION
        (Helptext) Enables internal phishing protection for Microsoft Forms to help prevent malicious forms from being created and shared within the organization. This feature scans forms created by internal users for potential phishing content and suspicious patterns.
        (DocsDescription) Enables internal phishing protection for Microsoft Forms by setting the isInOrgFormsPhishingScanEnabled property to true. This security feature helps protect organizations from internal phishing attacks through Microsoft Forms by automatically scanning forms created by internal users for potential malicious content, suspicious links, and phishing patterns. When enabled, Forms will analyze form content and block or flag potentially dangerous forms before they can be shared within the organization.
    .NOTES
        CAT
            Global Standards
        TAG
            "CIS"
            "Security"
            "PhishingProtection"
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2025-06-06
        POWERSHELLEQUIVALENT
            Graph API
        RECOMMENDEDBY
            "CIS"
            "CIPP"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param ($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'FormsPhishingProtection'

    $Uri = 'https://graph.microsoft.com/beta/admin/forms/settings'

    try {
        $CurrentState = (New-GraphGetRequest -Uri $Uri -tenantid $Tenant).isInOrgFormsPhishingScanEnabled
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not get current Forms settings. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Return
    }

    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate Forms phishing protection'

        # Check if phishing protection is already enabled
        if ($CurrentState -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Forms internal phishing protection is already enabled.' -sev Info
        } else {
            # Enable Forms phishing protection
            try {
                $Body = @{
                    isInOrgFormsPhishingScanEnabled = $true
                } | ConvertTo-Json -Depth 10 -Compress

                $null = New-GraphPostRequest -Uri $Uri -Body $Body -TenantID $Tenant -Type PATCH

                # Refresh the current state after enabling
                $CurrentState = New-GraphGetRequest -Uri $Uri -tenantid $Tenant
                Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Successfully enabled Forms internal phishing protection.' -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to enable Forms internal phishing protection. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($CurrentState -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Forms internal phishing protection is enabled.' -sev Info
        } else {
            Write-StandardsAlert -message 'Forms internal phishing protection is not enabled' -object $CurrentState -tenant $Tenant -standardName 'FormsPhishingProtection' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Forms internal phishing protection is not enabled.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Set-CIPPStandardsCompareField -FieldName 'standards.FormsPhishingProtection' -FieldValue $CurrentState -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'FormsPhishingProtection' -FieldValue $CurrentState -StoreAs bool -Tenant $Tenant
    }
}
