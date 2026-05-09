function Invoke-CippTestSMB1001_2_1 {
    <#
    .SYNOPSIS
    Tests SMB1001 (2.1) - Ensure strong password hygiene is maintained

    .DESCRIPTION
    Verifies the tenant has Entra ID password protection enabled with a custom banned-password
    list (the M365 mechanism that blocks weak / breached passwords required by SMB1001 2.1.vi).
    #>
    param($Tenant)

    $TestId = 'SMB1001_2_1'
    $Name = 'Strong password hygiene is maintained'

    try {
        $Settings = Get-CIPPTestData -TenantFilter $Tenant -Type 'Settings'

        if (-not $Settings) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'Settings cache not found. Please refresh the cache for this tenant.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Password Hygiene'
            return
        }

        $PwdSetting = $Settings | Where-Object {
            $_.templateId -eq '5cf42378-d67d-4f36-ba46-e8b86229381d' -or $_.displayName -eq 'Password Rule Settings'
        } | Select-Object -First 1

        if (-not $PwdSetting) {
            $Status = 'Failed'
            $Result = 'Entra ID Password Rule Settings not found. Configure a custom banned-password list to satisfy SMB1001 (2.1.vi) — passwords must not appear in previous data breaches.'
        } else {
            $Enforce = ($PwdSetting.values | Where-Object { $_.name -eq 'EnableBannedPasswordCheck' }).value
            $Custom = ($PwdSetting.values | Where-Object { $_.name -eq 'BannedPasswordList' }).value

            if ($Enforce -eq 'True' -and -not [string]::IsNullOrWhiteSpace($Custom)) {
                $WordCount = ($Custom -split '\t').Count
                $Status = 'Passed'
                $Result = "Custom banned passwords are enforced ($WordCount banned term(s))."
            } else {
                $Status = 'Failed'
                $Result = "Entra ID Password Protection is not fully configured.`n`n- EnableBannedPasswordCheck: $Enforce`n- BannedPasswordList length: $($Custom.Length)"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Password Hygiene'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Password Hygiene'
    }
}
