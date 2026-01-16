function Invoke-CippTestZTNA21842 {
    <#
    .SYNOPSIS
    Block administrators from using SSPR
    #>
    param($Tenant)

    $TestId = 'ZTNA21842'
    #Tested
    try {
        # Get authorization policy
        $AuthorizationPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthorizationPolicy'

        if (-not $AuthorizationPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Block administrators from using SSPR' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'
            return
        }

        $AllowedToUseSspr = $AuthorizationPolicy.allowedToUseSspr
        $Passed = 'Failed'
        $UserMessage = ''

        if ($null -ne $AllowedToUseSspr -and $AllowedToUseSspr -eq $false) {
            $Passed = 'Passed'
            $UserMessage = '✅ Administrators are properly blocked from using Self-Service Password Reset, ensuring password changes go through controlled processes.'
        } else {
            $UserMessage = '❌ Administrators have access to Self-Service Password Reset, which bypasses security controls and administrative oversight.'
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $UserMessage -Risk 'High' -Name 'Block administrators from using SSPR' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Block administrators from using SSPR' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'
    }
}
