function Invoke-CippTestCISAMSEXO131 {
    <#
    .SYNOPSIS
    Tests MS.EXO.13.1 - Mailbox auditing SHALL be enabled

    .DESCRIPTION
    Checks if mailbox auditing is enabled in Exchange Online organization config

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )

    try {
        $OrgConfig = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoOrganizationConfig'

        if (-not $OrgConfig) {
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoOrganizationConfig cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Category 'Exchange Online' -TestId 'CISAMSEXO131' -TenantFilter $Tenant
            return
        }

        $OrgConfigObject = $OrgConfig | Select-Object -First 1

        if ($OrgConfigObject.AuditDisabled -eq $false) {
            $Result = '✅ **Pass**: Mailbox auditing is enabled for the organization.'
            $Status = 'Pass'
        } else {
            $Result = "❌ **Fail**: Mailbox auditing is disabled for the organization.`n`n"
            $Result += "**Current Setting:**`n"
            $Result += "- AuditDisabled: $($OrgConfigObject.AuditDisabled)"
            $Status = 'Fail'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO131' -Status $Status -ResultMarkdown $Result -Risk 'High' -Category 'Exchange Online'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Category 'Exchange Online' -TestId 'CISAMSEXO131' -TenantFilter $Tenant
    }
}
function Invoke-CippTestCISAMSEXO131 {
    <#
    .SYNOPSIS
    MS.EXO.13.1 - Mailbox auditing SHALL be enabled
    
    .DESCRIPTION
    Tests if mailbox auditing is enabled organization-wide
    
    .LINK
    https://github.com/cisagov/ScubaGear
    #>
    param($Tenant)
    
    try {
        $OrgConfig = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoOrganizationConfig'
        
        if (-not $OrgConfig) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO131' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoOrganizationConfig cache not found. Please ensure cache data is available.' -Risk 'High' -Name 'Mailbox auditing enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Exchange Online'
            return
        }
        
        $AuditDisabled = $OrgConfig.AuditDisabled
        
        # AuditDisabled should be False (meaning auditing is enabled)
        if ($AuditDisabled -eq $false) {
            $Status = 'Passed'
            $Result = "✅ Well done. Mailbox auditing is enabled organization-wide.`n`n"
            $Result += "**Current Configuration:**`n"
            $Result += "- Mailbox Auditing: **Enabled** ✅`n`n"
            $Result += 'Mailbox auditing helps track and log mailbox access and modifications for security and compliance purposes.'
        } else {
            $Status = 'Failed'
            $Result = "❌ Mailbox auditing is disabled organization-wide.`n`n"
            $Result += "**Current Configuration:**`n"
            $Result += "- Mailbox Auditing: **Disabled** ❌`n`n"
            $Result += '**Recommendation:** Enable mailbox auditing to track mailbox access and modifications. This is critical for security investigations and compliance requirements.'
        }
        
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO131' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Mailbox auditing enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Exchange Online'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run CISA test CISAMSEXO131: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO131' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Mailbox auditing enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Exchange Online'
    }
}
