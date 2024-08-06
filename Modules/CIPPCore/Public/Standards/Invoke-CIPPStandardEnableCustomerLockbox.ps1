function Invoke-CIPPStandardEnableCustomerLockbox {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) EnableCustomerLockbox
    .SYNOPSIS
        (Label) Enable Customer Lockbox
    .DESCRIPTION
        (Helptext) Enables Customer Lockbox that offers an approval process for Microsoft support to access organization data
        (DocsDescription) Customer Lockbox ensures that Microsoft can't access your content to do service operations without your explicit approval. Customer Lockbox ensures only authorized requests allow access to your organizations data.
    .NOTES
        CAT
            Global Standards
        TAG
            "lowimpact"
            "CIS"
            "CustomerLockBoxEnabled"
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        POWERSHELLEQUIVALENT
            Set-OrganizationConfig -CustomerLockBoxEnabled \$true
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/edit-standards
    #>

    param($Tenant, $Settings)

    $CustomerLockboxStatus = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig').CustomerLockboxEnabled
    if ($Settings.remediate -eq $true) {
        Write-Host 'Time to remediate'
        try {

            if ($CustomerLockboxStatus) {
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Customer Lockbox already enabled' -sev Info
            } else {
                New-ExoRequest -tenantid $Tenant -cmdlet 'Set-OrganizationConfig' -cmdParams @{ CustomerLockboxEnabled = $true } -UseSystemMailbox $true
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Successfully enabled Customer Lockbox' -sev Info
            }
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            if ($ErrorMessage -match 'Ex5E8EA4') {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable Customer Lockbox. E5 license required. Error: $ErrorMessage" -sev Error
            } else {
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to enable Customer Lockbox. Error: $ErrorMessage" -sev Error
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($CustomerLockboxStatus) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Customer Lockbox is enabled' -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Customer Lockbox is not enabled' -sev Alert
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'CustomerLockboxEnabled' -FieldValue $CustomerLockboxStatus -StoreAs bool -Tenant $tenant
    }
}
