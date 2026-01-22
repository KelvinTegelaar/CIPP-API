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
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoOrganizationConfig cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name 'Mailbox auditing SHALL be enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Audit & Compliance' -TestId 'CISAMSEXO131' -TenantFilter $Tenant
            return
        }

        $OrgConfigObject = $OrgConfig | Select-Object -First 1

        if ($OrgConfigObject.AuditDisabled -eq $false) {
            $Result = '✅ **Pass**: Mailbox auditing is enabled for the organization.'
            $Status = 'Passed'
        } else {
            $Result = "❌ **Fail**: Mailbox auditing is disabled for the organization.`n`n"
            $Result += "**Current Setting:**`n"
            $Result += "- AuditDisabled: $($OrgConfigObject.AuditDisabled)"
            $Status = 'Failed'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO131' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Mailbox auditing SHALL be enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Audit & Compliance'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Mailbox auditing SHALL be enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Audit & Compliance' -TestId 'CISAMSEXO131' -TenantFilter $Tenant
    }
}
