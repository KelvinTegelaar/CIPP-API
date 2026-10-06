BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $TestsRoot = Join-Path $RepoRoot 'Modules/CIPPTests/Public/Tests'
    . (Join-Path $TestsRoot 'ZTNA/Identity/Invoke-CippTestZTNA21811.ps1')
    . (Join-Path $TestsRoot 'CopilotReadiness/Identity/Invoke-CippTestCopilotReady004.ps1')
    . (Join-Path $TestsRoot 'CopilotReadiness/Identity/Invoke-CippTestCopilotReady007.ps1')

    function Get-CIPPTestData { param($TenantFilter, $Type) $script:Data[$Type] }
    function Add-CippTestResult { param($TenantFilter, $TestId, $TestType, $Status, $ResultMarkdown, $Risk, $Name, $UserImpact, $ImplementationEffort, $Category) $script:Result = @{ Status = $Status; Markdown = "$ResultMarkdown" } }
    function Write-LogMessage { }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    function New-User($Upn, [bool]$Enabled = $true, $Plans, $PasswordPolicies) {
        [pscustomobject]@{ id = [guid]::NewGuid().ToString(); userPrincipalName = $Upn; displayName = $Upn; accountEnabled = $Enabled; assignedPlans = $Plans; passwordPolicies = $PasswordPolicies }
    }
    function New-Plan($Service, $Status) { [pscustomobject]@{ service = $Service; capabilityStatus = $Status } }
}

Describe 'ZTNA21811 user domain matching' {
    It 'flags users on a misconfigured domain, its subdomains and any casing, but not opted-out users or other domains' {
        $script:Data = @{
            Domains = @(
                [pscustomobject]@{ id = 'contoso.com'; passwordValidityPeriodInDays = 90 }
                [pscustomobject]@{ id = 'sub.contoso.com'; passwordValidityPeriodInDays = 90 }
                [pscustomobject]@{ id = 'fabrikam.com'; passwordValidityPeriodInDays = 2147483647 }
            )
            Users   = @(
                New-User 'a@contoso.com'
                New-User 'b@sub.contoso.com'
                New-User 'c@CONTOSO.COM'
                New-User 'd@contoso.com' -PasswordPolicies 'DisablePasswordExpiration'
                New-User 'e@fabrikam.com'
                New-User 'f@contoso.com'
            )
        }

        Invoke-CippTestZTNA21811 -Tenant 't.com'

        $script:Result.Status | Should -Be 'Failed'
        $Rows = @([regex]::Matches($script:Result.Markdown, '(?m)^\| (\S+@\S+) \| \1 \| \S* \| 90 \|$').ForEach({ $_.Groups[1].Value }))
        $Rows | Should -Be @('a@contoso.com', 'b@sub.contoso.com', 'c@CONTOSO.COM', 'f@contoso.com')
    }
}

Describe 'Copilot readiness licensed-user filter' {
    BeforeEach {
        $script:Data = @{
            CopilotReadinessActivity = @(
                [pscustomobject]@{ userPrincipalName = 'licensed@t.com'; usesOutlookEmail = $true; onQualifiedUpdateChannel = $true }
            )
            Users                    = @(
                New-User 'licensed@t.com' -Plans @((New-Plan 'exchange' 'Deleted'), (New-Plan 'MicrosoftOffice' 'Enabled'))
                New-User 'singleplan@t.com' -Plans (New-Plan 'exchange' 'Enabled')
                New-User 'suspended@t.com' -Plans @((New-Plan 'MicrosoftOffice' 'Suspended'))
                New-User 'disabled@t.com' -Enabled $false -Plans @((New-Plan 'MicrosoftOffice' 'Enabled'))
                New-User 'noplans@t.com'
                New-User $null -Plans @((New-Plan 'MicrosoftOffice' 'Enabled'))
            )
        }
    }

    It 'counts enabled users holding any enabled plan' {
        Invoke-CippTestCopilotReady004 -Tenant 't.com'

        $script:Result.Status | Should -Be 'Passed'
        $script:Result.Markdown | Should -Match '\*\*1 of 2 licensed users \(50%\)\*\*'
    }

    It 'counts only enabled MicrosoftOffice plans for the M365 Apps checks' {
        Invoke-CippTestCopilotReady007 -Tenant 't.com'

        $script:Result.Status | Should -Be 'Passed'
        $script:Result.Markdown | Should -Match '\*\*1 of 1 M365 Apps licensed users \(100%\)\*\*'
    }
}
