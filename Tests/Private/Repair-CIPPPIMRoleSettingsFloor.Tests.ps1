# Pester tests for Repair-CIPPPIMRoleSettingsFloor.
#
# Capturing a role's live PIM settings into a template must never store anything below the
# secure floor: offending values are raised to the closest value the floor allows, every raise
# is reported, and settings already at or above the floor pass through untouched. Whatever goes
# in, the repaired output must always satisfy Test-CIPPPIMRoleSettingsFloor.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/PIM/Repair-CIPPPIMRoleSettingsFloor.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/PIM/Test-CIPPPIMRoleSettingsFloor.ps1')

    function New-CapturedSettings {
        param([hashtable]$Overrides = @{})
        $Settings = @{
            activationMaxDuration                 = 'PT4H'
            activationRequires                    = 'MFA'
            authenticationContextClaimValue       = ''
            activationRequiresJustification       = $true
            activationRequiresTicket              = $false
            activationRequiresApproval            = $false
            approvers                             = ''
            eligibilityMaxDuration                = 'P180D'
            activeAssignmentMaxDuration           = 'P90D'
            activeAssignmentRequiresMfa           = $true
            activeAssignmentRequiresJustification = $true
            notificationRecipients                = ''
            notificationLevel                     = 'All'
        }
        foreach ($Key in $Overrides.Keys) { $Settings[$Key] = $Overrides[$Key] }
        [pscustomobject]$Settings
    }
}

Describe 'Repair-CIPPPIMRoleSettingsFloor' {
    It 'passes compliant settings through untouched with no adjustments' {
        $Input = New-CapturedSettings
        $Result = Repair-CIPPPIMRoleSettingsFloor -Settings $Input
        $Result.Adjustments.Count | Should -Be 0
        foreach ($Property in $Input.PSObject.Properties.Name) {
            $Result.Settings.$Property | Should -Be $Input.$Property -Because $Property
        }
    }

    It 'raises permanent (null) durations to the floor maximum' {
        $Result = Repair-CIPPPIMRoleSettingsFloor -Settings (New-CapturedSettings @{
                activationMaxDuration       = $null
                eligibilityMaxDuration      = $null
                activeAssignmentMaxDuration = $null
            })
        $Result.Settings.activationMaxDuration | Should -Be 'PT24H'
        $Result.Settings.eligibilityMaxDuration | Should -Be 'P365D'
        $Result.Settings.activeAssignmentMaxDuration | Should -Be 'P365D'
        $Result.Adjustments.Count | Should -Be 3
        ($Result.Adjustments -join ' ') | Should -Match 'permanent allowed'
    }

    It 'lowers durations above the floor maximum instead of refusing them' {
        $Result = Repair-CIPPPIMRoleSettingsFloor -Settings (New-CapturedSettings @{
                activationMaxDuration  = 'P2D'
                eligibilityMaxDuration = 'P10Y'
            })
        $Result.Settings.activationMaxDuration | Should -Be 'PT24H'
        $Result.Settings.eligibilityMaxDuration | Should -Be 'P365D'
        $Result.Adjustments.Count | Should -Be 2
    }

    It 'requires MFA when activation demanded neither MFA nor an authentication context' {
        $Result = Repair-CIPPPIMRoleSettingsFloor -Settings (New-CapturedSettings @{ activationRequires = 'None' })
        $Result.Settings.activationRequires | Should -Be 'MFA'
        ($Result.Adjustments -join ' ') | Should -Match 'MFA'
    }

    It 'keeps a valid authentication context in place of MFA' {
        $Result = Repair-CIPPPIMRoleSettingsFloor -Settings (New-CapturedSettings @{
                activationRequires              = 'AuthenticationContext'
                authenticationContextClaimValue = 'c1'
            })
        $Result.Adjustments.Count | Should -Be 0
        $Result.Settings.activationRequires | Should -Be 'AuthenticationContext'
        $Result.Settings.authenticationContextClaimValue | Should -Be 'c1'
    }

    It 'falls back to MFA when the authentication context has no usable claim value' {
        $Result = Repair-CIPPPIMRoleSettingsFloor -Settings (New-CapturedSettings @{
                activationRequires              = 'AuthenticationContext'
                authenticationContextClaimValue = ''
            })
        $Result.Settings.activationRequires | Should -Be 'MFA'
        ($Result.Adjustments -join ' ') | Should -Match 'claim value'
    }

    It 'enables missing justifications' {
        $Result = Repair-CIPPPIMRoleSettingsFloor -Settings (New-CapturedSettings @{
                activationRequiresJustification       = $false
                activeAssignmentRequiresJustification = $false
            })
        $Result.Settings.activationRequiresJustification | Should -BeTrue
        $Result.Settings.activeAssignmentRequiresJustification | Should -BeTrue
        $Result.Adjustments.Count | Should -Be 2
    }

    It 'disables approval when no approver could be captured' {
        $Result = Repair-CIPPPIMRoleSettingsFloor -Settings (New-CapturedSettings @{
                activationRequiresApproval = $true
                approvers                  = ''
            })
        $Result.Settings.activationRequiresApproval | Should -BeFalse
        ($Result.Adjustments -join ' ') | Should -Match 'approval disabled'
    }

    It 'keeps approval with captured approvers' {
        $Result = Repair-CIPPPIMRoleSettingsFloor -Settings (New-CapturedSettings @{
                activationRequiresApproval = $true
                approvers                  = 'SOC Approvers'
            })
        $Result.Adjustments.Count | Should -Be 0
        $Result.Settings.activationRequiresApproval | Should -BeTrue
        $Result.Settings.approvers | Should -Be 'SOC Approvers'
    }

    It 'drops notification recipients that are not e-mail addresses and fixes an invalid level' {
        $Result = Repair-CIPPPIMRoleSettingsFloor -Settings (New-CapturedSettings @{
                notificationRecipients = 'soc@msp.example, not-an-address'
                notificationLevel      = 'Everything'
            })
        $Result.Settings.notificationRecipients | Should -Be 'soc@msp.example'
        $Result.Settings.notificationLevel | Should -Be 'All'
        $Result.Adjustments.Count | Should -Be 2
    }

    It 'always produces settings that satisfy the secure floor' {
        $Cases = @(
            (New-CapturedSettings @{ activationMaxDuration = $null; activationRequires = 'None'; activationRequiresJustification = $false; eligibilityMaxDuration = $null; activeAssignmentMaxDuration = $null; activeAssignmentRequiresJustification = $false })
            (New-CapturedSettings @{ activationMaxDuration = 'garbage'; eligibilityMaxDuration = '-P1D'; notificationRecipients = 'nope'; notificationLevel = 'x' })
            (New-CapturedSettings @{ activationRequires = 'AuthenticationContext'; authenticationContextClaimValue = 'zzz'; activationRequiresApproval = $true; approvers = '' })
        )
        foreach ($Case in $Cases) {
            $Result = Repair-CIPPPIMRoleSettingsFloor -Settings $Case
            (Test-CIPPPIMRoleSettingsFloor -Settings $Result.Settings).Valid | Should -BeTrue
        }
    }
}
