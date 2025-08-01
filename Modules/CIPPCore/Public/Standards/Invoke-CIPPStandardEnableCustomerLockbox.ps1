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
            "CIS"
            "CustomerLockBoxEnabled"
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2024-01-08
        POWERSHELLEQUIVALENT
            Set-OrganizationConfig -CustomerLockBoxEnabled \$true
        RECOMMENDEDBY
            "CIS"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'EnableCustomerLockbox'
    $TestResult = Test-CIPPStandardLicense -StandardName 'EnableCustomerLockbox' -TenantFilter $Tenant -RequiredCapabilities @('CustomerLockbox')

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.

    try {
        $CustomerLockboxStatus = (New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig').CustomerLockboxEnabled
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the EnableCustomerLockbox state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

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
            Write-StandardsAlert -message 'Customer Lockbox is not enabled' -object $CustomerLockboxStatus -tenant $tenant -standardName 'EnableCustomerLockbox' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Customer Lockbox is not enabled' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $state = $CustomerLockboxStatus ? $true : $false
        Set-CIPPStandardsCompareField -FieldName 'standards.EnableCustomerLockbox' -FieldValue $state -Tenant $tenant
        Add-CIPPBPAField -FieldName 'CustomerLockboxEnabled' -FieldValue $CustomerLockboxStatus -StoreAs bool -Tenant $tenant
    }
}
