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
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoOrganizationConfig cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Category 'Exchange Online' -TestId 'CISAMSEXO71' -TenantFilter $Tenant
            return
        }

        $OrgConfigObject = $OrgConfig | Select-Object -First 1

        if ($OrgConfigObject.ExternalInOutlook -eq $true) {
            $Result = '✅ **Pass**: External sender warnings are enabled in Outlook.'
            $Status = 'Pass'
        } else {
            $Result = "❌ **Fail**: External sender warnings are not enabled in Outlook.`n`n"
            $Result += "**Current Setting:**`n"
            $Result += "- ExternalInOutlook: $($OrgConfigObject.ExternalInOutlook)"
            $Status = 'Fail'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO71' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Category 'Exchange Online'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Category 'Exchange Online' -TestId 'CISAMSEXO71' -TenantFilter $Tenant
    }
}
function Invoke-CippTestCISAMSEXO71 {
    <#
    .SYNOPSIS
    MS.EXO.7.1 - External sender warnings SHALL be implemented
    
    .DESCRIPTION
    Tests if external sender warning is configured in Exchange transport rules
    
    .LINK
    https://github.com/cisagov/ScubaGear
    #>
    param($Tenant)
    
    try {
        $TransportRules = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoTransportRules'
        
        if (-not $TransportRules) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO71' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoTransportRules cache not found. Please ensure cache data is available.' -Risk 'Medium' -Name 'External sender warnings implemented' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Exchange Online'
            return
        }
        
        # Look for external sender warning rules
        $ExternalSenderRules = $TransportRules | Where-Object {
            ($_.FromScope -eq 'NotInOrganization') -and
            ($_.PrependSubject -or $_.SetHeaderName -or $_.ApplyHtmlDisclaimerText) -and
            ($_.State -eq 'Enabled')
        }
        
        if ($ExternalSenderRules.Count -gt 0) {
            $Status = 'Passed'
            $Result = "✅ Well done. Your tenant has external sender warning rules configured.`n`n"
            $Result += "**Active External Sender Warning Rules:**`n`n"
            $Result += "| Rule Name | Priority | Action |`n"
            $Result += "| --- | --- | --- |`n"
            
            foreach ($rule in $ExternalSenderRules | Sort-Object Priority) {
                $action = if ($rule.PrependSubject) { 'Prepend Subject' }
                elseif ($rule.SetHeaderName) { 'Set Header' }
                elseif ($rule.ApplyHtmlDisclaimerText) { 'Add Disclaimer' }
                else { 'Modified Message' }
                $Result += "| $($rule.Name) | $($rule.Priority) | $action |`n"
            }
        } else {
            $Status = 'Failed'
            $Result = "❌ No external sender warning rules found.`n`n"
            $Result += "**Recommendation:** Create a transport rule to warn users about external senders.`n`n"
            $Result += "**Example configurations:**`n"
            $Result += "- Add '[EXTERNAL]' prefix to subject line for emails from outside organization`n"
            $Result += "- Add HTML disclaimer banner warning users the email is from external sender`n"
            $Result += "- Add custom header for client-side filtering`n"
        }
        
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO71' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'External sender warnings implemented' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Exchange Online'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run CISA test CISAMSEXO71: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO71' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'External sender warnings implemented' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Exchange Online'
    }
}
