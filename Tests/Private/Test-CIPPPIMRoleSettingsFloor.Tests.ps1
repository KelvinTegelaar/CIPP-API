# Pester tests for the PIM role settings secure floor and its normaliser.
#
# The floor is what stops a PIM role settings template - saved through the editor, hand-edited in
# the templates table, or deployed by the PIMRoleSettings standard - from weakening a tenant's
# privileged access. Templates below it are rejected, never clamped, so each rule gets a test
# proving it rejects, plus the one case that is allowed-but-warned (activation above 8h, up to 24h).

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/PIM/Test-CIPPPIMRoleSettingsFloor.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/PIM/ConvertTo-CIPPPIMRoleSettings.ps1')

    function New-SecureSettings {
        param([hashtable]$Override = @{})
        $Settings = @{
            activationMaxDuration                 = 'PT8H'
            activationRequires                    = 'MFA'
            authenticationContextClaimValue       = ''
            activationRequiresJustification       = $true
            activationRequiresTicket              = $false
            activationRequiresApproval            = $false
            approvers                             = ''
            eligibilityMaxDuration                = 'P365D'
            activeAssignmentMaxDuration           = 'P180D'
            activeAssignmentRequiresMfa           = $true
            activeAssignmentRequiresJustification = $true
            notificationRecipients                = ''
            notificationLevel                     = 'All'
        }
        foreach ($Key in $Override.Keys) { $Settings[$Key] = $Override[$Key] }
        return ConvertTo-CIPPPIMRoleSettings -InputObject $Settings
    }
}

Describe 'Test-CIPPPIMRoleSettingsFloor' {
    It 'accepts the secure defaults with no warnings' {
        $Result = Test-CIPPPIMRoleSettingsFloor -Settings (New-SecureSettings)
        $Result.Valid | Should -BeTrue
        $Result.Errors | Should -BeNullOrEmpty
        $Result.Warnings | Should -BeNullOrEmpty
    }

    It 'rejects a null settings object' {
        (Test-CIPPPIMRoleSettingsFloor -Settings $null).Valid | Should -BeFalse
    }

    Context 'activation' {
        It 'warns, but allows, an activation maximum between 8h and 24h' {
            $Result = Test-CIPPPIMRoleSettingsFloor -Settings (New-SecureSettings @{ activationMaxDuration = 'PT12H' })
            $Result.Valid | Should -BeTrue
            $Result.Warnings | Should -Match 'exceeds the recommended PT8H'
        }

        It 'allows exactly 24h' {
            (Test-CIPPPIMRoleSettingsFloor -Settings (New-SecureSettings @{ activationMaxDuration = 'PT24H' })).Valid | Should -BeTrue
        }

        It 'rejects an activation maximum above 24h' {
            $Result = Test-CIPPPIMRoleSettingsFloor -Settings (New-SecureSettings @{ activationMaxDuration = 'PT25H' })
            $Result.Valid | Should -BeFalse
            $Result.Errors | Should -Match 'exceeds the maximum of PT24H'
        }

        It 'rejects an activation with no expiration' {
            $Result = Test-CIPPPIMRoleSettingsFloor -Settings (New-SecureSettings @{ activationMaxDuration = $null })
            # The normaliser substitutes the secure default for an absent value, so feed the
            # canonical object directly to simulate a policy that does not require expiration.
            $Settings = New-SecureSettings
            $Settings.activationMaxDuration = $null
            $Result = Test-CIPPPIMRoleSettingsFloor -Settings $Settings
            $Result.Valid | Should -BeFalse
            $Result.Errors | Should -Match 'Role activation must expire'
        }

        It 'rejects activation without MFA or an authentication context' {
            $Result = Test-CIPPPIMRoleSettingsFloor -Settings (New-SecureSettings @{ activationRequires = 'None' })
            $Result.Valid | Should -BeFalse
            $Result.Errors | Should -Match 'must require MFA or an authentication context'
        }

        It 'accepts an authentication context with a claim value in place of MFA' {
            $Result = Test-CIPPPIMRoleSettingsFloor -Settings (New-SecureSettings @{ activationRequires = 'AuthenticationContext'; authenticationContextClaimValue = 'c1' })
            $Result.Valid | Should -BeTrue
        }

        It 'rejects an authentication context without a claim value' {
            $Result = Test-CIPPPIMRoleSettingsFloor -Settings (New-SecureSettings @{ activationRequires = 'AuthenticationContext' })
            $Result.Valid | Should -BeFalse
            $Result.Errors | Should -Match 'claim value'
        }

        It 'rejects activation without a justification' {
            $Result = Test-CIPPPIMRoleSettingsFloor -Settings (New-SecureSettings @{ activationRequiresJustification = $false })
            $Result.Valid | Should -BeFalse
            $Result.Errors | Should -Match 'Role activation must require a justification'
        }

        It 'rejects approval without approvers' {
            $Result = Test-CIPPPIMRoleSettingsFloor -Settings (New-SecureSettings @{ activationRequiresApproval = $true })
            $Result.Valid | Should -BeFalse
            $Result.Errors | Should -Match 'no approvers'
        }

        It 'accepts approval with approvers' {
            (Test-CIPPPIMRoleSettingsFloor -Settings (New-SecureSettings @{ activationRequiresApproval = $true; approvers = 'Security Team' })).Valid | Should -BeTrue
        }
    }

    Context 'eligibility and active assignments' {
        It 'rejects eligibility beyond a year' {
            $Result = Test-CIPPPIMRoleSettingsFloor -Settings (New-SecureSettings @{ eligibilityMaxDuration = 'P400D' })
            $Result.Valid | Should -BeFalse
            $Result.Errors | Should -Match 'Eligible assignments.*exceeds the maximum of P365D'
        }

        It 'rejects eligibility with no expiration (permanent eligibility)' {
            $Settings = New-SecureSettings
            $Settings.eligibilityMaxDuration = ''
            $Result = Test-CIPPPIMRoleSettingsFloor -Settings $Settings
            $Result.Valid | Should -BeFalse
            $Result.Errors | Should -Match 'Eligible assignments must expire'
        }

        It 'rejects active assignments beyond a year' {
            $Result = Test-CIPPPIMRoleSettingsFloor -Settings (New-SecureSettings @{ activeAssignmentMaxDuration = 'P2Y' })
            $Result.Valid | Should -BeFalse
            $Result.Errors | Should -Match 'Active assignments.*exceeds the maximum of P365D'
        }

        It 'rejects active assignments with no expiration (permanent active)' {
            $Settings = New-SecureSettings
            $Settings.activeAssignmentMaxDuration = $null
            $Result = Test-CIPPPIMRoleSettingsFloor -Settings $Settings
            $Result.Valid | Should -BeFalse
            $Result.Errors | Should -Match 'Active assignments must expire'
        }

        It 'rejects active assignments without a justification' {
            $Result = Test-CIPPPIMRoleSettingsFloor -Settings (New-SecureSettings @{ activeAssignmentRequiresJustification = $false })
            $Result.Valid | Should -BeFalse
            $Result.Errors | Should -Match 'active assignment must require a justification'
        }

        It 'reports every violation at once' {
            $Settings = New-SecureSettings @{ activationRequires = 'None'; activationRequiresJustification = $false; eligibilityMaxDuration = 'P2Y' }
            $Result = Test-CIPPPIMRoleSettingsFloor -Settings $Settings
            $Result.Errors.Count | Should -Be 3
        }
    }

    Context 'notifications' {
        It 'rejects an invalid recipient address' {
            $Result = Test-CIPPPIMRoleSettingsFloor -Settings (New-SecureSettings @{ notificationRecipients = 'soc@contoso.com, not-an-address' })
            $Result.Valid | Should -BeFalse
            $Result.Errors | Should -Match "'not-an-address' is not a valid"
        }

        It 'rejects an unknown notification level when recipients are set' {
            $Result = Test-CIPPPIMRoleSettingsFloor -Settings (New-SecureSettings @{ notificationRecipients = 'soc@contoso.com'; notificationLevel = 'Everything' })
            $Result.Valid | Should -BeFalse
            $Result.Errors | Should -Match 'notificationLevel'
        }

        It 'accepts valid recipients' {
            (Test-CIPPPIMRoleSettingsFloor -Settings (New-SecureSettings @{ notificationRecipients = 'soc@contoso.com; ops@contoso.com'; notificationLevel = 'Critical' })).Valid | Should -BeTrue
        }
    }
}

Describe 'ConvertTo-CIPPPIMRoleSettings' {
    It 'unwraps autoComplete label/value objects and string booleans from a request body' {
        $Body = [pscustomobject]@{
            activationMaxDuration           = [pscustomobject]@{ label = '4 hours'; value = 'PT4H' }
            activationRequires              = @{ label = 'MFA'; value = 'MFA' }
            activationRequiresJustification = 'true'
            activationRequiresTicket        = 'false'
            notificationRecipients          = @('a@contoso.com', [pscustomobject]@{ label = 'b@contoso.com'; value = 'b@contoso.com' })
        }
        $Settings = ConvertTo-CIPPPIMRoleSettings -InputObject $Body
        $Settings.activationMaxDuration | Should -Be 'PT4H'
        $Settings.activationRequires | Should -Be 'MFA'
        $Settings.activationRequiresJustification | Should -BeTrue
        $Settings.activationRequiresTicket | Should -BeFalse
        $Settings.notificationRecipients | Should -Be 'a@contoso.com, b@contoso.com'
    }

    It 'applies the secure defaults for missing properties' {
        $Settings = ConvertTo-CIPPPIMRoleSettings -InputObject @{}
        $Settings.activationMaxDuration | Should -Be 'PT8H'
        $Settings.activationRequires | Should -Be 'MFA'
        $Settings.activationRequiresJustification | Should -BeTrue
        $Settings.eligibilityMaxDuration | Should -Be 'P365D'
        $Settings.activeAssignmentMaxDuration | Should -Be 'P180D'
        $Settings.activeAssignmentRequiresJustification | Should -BeTrue
        (Test-CIPPPIMRoleSettingsFloor -Settings $Settings).Valid | Should -BeTrue
    }
}
