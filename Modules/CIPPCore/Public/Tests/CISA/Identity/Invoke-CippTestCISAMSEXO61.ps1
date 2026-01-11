function Invoke-CippTestCISAMSEXO61 {
    <#
    .SYNOPSIS
    Tests MS.EXO.6.1 - Contact folders SHALL NOT be shared with all domains

    .DESCRIPTION
    Checks if sharing policies allow sharing contact folders with external domains

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )

    try {
        $SharingPolicies = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoSharingPolicy'

        if (-not $SharingPolicies) {
            Add-CippTestResult -Status 'Skipped' -ResultMarkdown 'ExoSharingPolicy cache not found. Please refresh the cache for this tenant.' -Risk 'Medium' -Category 'Exchange Online' -TestId 'CISAMSEXO61' -TenantFilter $Tenant
            return
        }

        $FailedPolicies = [System.Collections.Generic.List[object]]::new()

        foreach ($Policy in $SharingPolicies) {
            if ($Policy.Enabled) {
                # Check if any domain allows contact sharing (ContactsSharing capability)
                $ContactSharingDomains = $Policy.Domains | Where-Object { $_ -match 'ContactsSharing' }
                if ($ContactSharingDomains) {
                    $FailedPolicies.Add([PSCustomObject]@{
                            'Policy Name' = $Policy.Name
                            'Enabled'     = $Policy.Enabled
                            'Issue'       = 'Allows contact sharing with external domains'
                        })
                }
            }
        }

        if ($FailedPolicies.Count -eq 0) {
            $Result = '✅ **Pass**: No sharing policies allow contact folder sharing with external domains.'
            $Status = 'Pass'
        } else {
            $Result = "❌ **Fail**: $($FailedPolicies.Count) sharing policy/policies allow contact folder sharing:`n`n"
            $Result += ($FailedPolicies | ConvertTo-Html -Fragment | Out-String)
            $Status = 'Fail'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO61' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Category 'Exchange Online'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Category 'Exchange Online' -TestId 'CISAMSEXO61' -TenantFilter $Tenant
    }
}
function Invoke-CippTestCISAMSEXO61 {
    <#
    .SYNOPSIS
    MS.EXO.6.1 - Contact folder sharing SHALL be restricted
    
    .DESCRIPTION
    Tests if contact folder sharing with external users is restricted
    
    .LINK
    https://github.com/cisagov/ScubaGear
    #>
    param($Tenant)
    
    try {
        $OrgConfig = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ExoOrganizationConfig'
        
        if (-not $OrgConfig) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO61' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'ExoOrganizationConfig cache not found. Please ensure cache data is available.' -Risk 'Medium' -Name 'Contact folder sharing restricted' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Exchange Online'
            return
        }
        
        # Check if external sharing of contacts is disabled
        $SharingPolicy = $OrgConfig.DefaultSharingPolicy
        
        $Status = 'Skipped'
        $Result = "⚠️ **Additional Data Required**`n`n"
        $Result += "This test requires sharing policy details to verify contact folder sharing restrictions.`n`n"
        $Result += "**Current Organization Configuration:**`n"
        $Result += "- Default Sharing Policy: $($SharingPolicy)`n`n"
        $Result += "**Manual verification recommended:**`n"
        $Result += "1. Navigate to Exchange Admin Center > Organization > Sharing`n"
        $Result += "2. Verify that contact folder sharing with external domains is disabled or limited`n"
        $Result += "3. Check that the default policy does not allow 'ContactsSharing' for external domains`n"
        
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO61' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Contact folder sharing restricted' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Exchange Online'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run CISA test CISAMSEXO61: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CISAMSEXO61' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test execution failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Contact folder sharing restricted' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Exchange Online'
    }
}
