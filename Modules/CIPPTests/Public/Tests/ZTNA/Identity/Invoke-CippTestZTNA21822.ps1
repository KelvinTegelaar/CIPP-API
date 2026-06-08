function Invoke-CippTestZTNA21822 {
    <#
    .SYNOPSIS
    Guest access is limited to approved tenants
    #>
    param($Tenant)
    #Tested
    $TestId = 'ZTNA21822'

    try {
        # Get B2B management policy from cache
        $B2BManagementPolicyObject = Get-CIPPTestData -TenantFilter $Tenant -Type 'B2BManagementPolicy'

        $Passed = 'Failed'
        $AllowedDomains = @()
        $BlockedDomains = @()

        if ($B2BManagementPolicyObject -and $B2BManagementPolicyObject.definition) {
            $B2BManagementPolicy = ($B2BManagementPolicyObject.definition | ConvertFrom-Json).B2BManagementPolicy
            $AllowedDomains = $B2BManagementPolicy.InvitationsAllowedAndBlockedDomainsPolicy.AllowedDomains
            $BlockedDomains = $B2BManagementPolicy.InvitationsAllowedAndBlockedDomainsPolicy.BlockedDomains

            if ($AllowedDomains -and $AllowedDomains.Count -gt 0) {
                $Passed = 'Passed'
            }
        }

        if ($Passed -eq 'Passed') {
            $ResultMarkdown = [System.Text.StringBuilder]::new("Guest access is limited to approved tenants.`n")
        } else {
            $ResultMarkdown = [System.Text.StringBuilder]::new("Guest access is not limited to approved tenants.`n")
        }

        $null = $ResultMarkdown.Append("`n`n## [Collaboration restrictions](https://entra.microsoft.com/#view/Microsoft_AAD_IAM/CompanyRelationshipsMenuBlade/~/Settings/menuId/)`n`n")
        $null = $ResultMarkdown.Append('The tenant is configured to: ')

        if ($Passed -eq 'Passed') {
            $null = $ResultMarkdown.Append("**Allow invitations only to the specified domains (most restrictive)** ✅`n")
        } else {
            if ($BlockedDomains -and $BlockedDomains.Count -gt 0) {
                $null = $ResultMarkdown.Append("**Deny invitations to the specified domains** ❌`n")
            } else {
                $null = $ResultMarkdown.Append("**Allow invitations to be sent to any domain (most inclusive)** ❌`n")
            }
        }

        if (($AllowedDomains -and $AllowedDomains.Count -gt 0) -or ($BlockedDomains -and $BlockedDomains.Count -gt 0)) {
            $null = $ResultMarkdown.Append("| Domain | Status |`n")
            $null = $ResultMarkdown.Append("| :--- | :--- |`n")

            foreach ($Domain in $AllowedDomains) {
                $null = $ResultMarkdown.Append("| $Domain | ✅ Allowed |`n")
            }

            foreach ($Domain in $BlockedDomains) {
                $null = $ResultMarkdown.Append("| $Domain | ❌ Blocked |`n")
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'Medium' -Name 'Guest access is limited to approved tenants' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Access control'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Guest access is limited to approved tenants' -UserImpact 'Medium' -ImplementationEffort 'High' -Category 'Access control'
    }
}
