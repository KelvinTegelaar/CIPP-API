function Invoke-CippTestCIS_5_2_3_2 {
    <#
    .SYNOPSIS
    Tests CIS M365 6.0.1 (5.2.3.2) - Custom banned passwords lists SHALL be used
    #>
    param($Tenant)

    try {
        $Settings = Get-CIPPTestData -TenantFilter $Tenant -Type 'Settings'

        if (-not $Settings) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_2' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Settings cache not found.' -Risk 'Medium' -Name 'Custom banned passwords lists are used' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
            return
        }

        $PwdSetting = $Settings | Where-Object { $_.templateId -eq '5cf42378-d67d-4f36-ba46-e8b86229381d' -or $_.displayName -eq 'Password Rule Settings' } | Select-Object -First 1

        if (-not $PwdSetting) {
            $Status = 'Failed'
            $Result = 'Password Rule Settings not found in directory settings — custom banned passwords have not been configured.'
        } else {
            $Enforce = ($PwdSetting.values | Where-Object { $_.name -eq 'EnableBannedPasswordCheck' }).value
            $Custom = ($PwdSetting.values | Where-Object { $_.name -eq 'BannedPasswordList' }).value

            if ($Enforce -eq 'True' -and -not [string]::IsNullOrWhiteSpace($Custom)) {
                $Status = 'Passed'
                $Result = "Custom banned passwords are enforced ($([int](($Custom -split '\t').Count)) words)."
            } else {
                $Status = 'Failed'
                $Result = "Custom banned passwords not fully configured. EnableBannedPasswordCheck: $Enforce; BannedPasswordList length: $([int]($Custom).Length)"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_2' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Custom banned passwords lists are used' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId 'CIS_5_2_3_2' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Custom banned passwords lists are used' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Authentication'
    }
}
