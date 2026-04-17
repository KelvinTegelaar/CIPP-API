function Invoke-CippTestCISAMSEXO71 {
    <#
    .SYNOPSIS
    Tests MS.EXO.7.1 - External sender warnings SHALL be implemented

    .DESCRIPTION
    Checks if external sender warnings are enabled in Exchange Online organization config

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
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoOrganizationConfig cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Name 'External sender warnings SHALL be implemented' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO71' -TenantFilter $Tenant
            return
        }

        $OrgConfigObject = $OrgConfig | Select-Object -First 1

        if ($OrgConfigObject.ExternalInOutlook -eq $true) {
            $Result = '✅ **Pass**: External sender warnings are enabled in Outlook.'
            $Status = 'Passed'
        } else {
            $Result = "❌ **Fail**: External sender warnings are not enabled in Outlook.`n`n"
            $Result += "**Current Setting:**`n"
            $Result += "- ExternalInOutlook: $($OrgConfigObject.ExternalInOutlook)"
            $Status = 'Failed'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO71' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'External sender warnings SHALL be implemented' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'External sender warnings SHALL be implemented' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Email Protection' -TestId 'CISAMSEXO71' -TenantFilter $Tenant
    }
}
