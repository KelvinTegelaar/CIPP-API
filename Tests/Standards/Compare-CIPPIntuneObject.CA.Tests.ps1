# Pester tests for Compare-CIPPIntuneObject -CompareType 'ca'.
#
# Regression under test: a CA template stores grantControls.authenticationStrength as a bare
# { id } reference, while Graph returns the strength fully expanded on read. The shared exclusion
# list drops id/createdDateTime/lastModifiedDateTime but not displayName/description/policyType/
# requirementsSatisfied/allowedCombinations, so every drift run reported five phantom differences
# that remediation could never clear - and with auto-remediate on, PATCHed the policy every cycle.
#
# Both the ConditionalAccessTemplate standard and Invoke-CIPPCATemplateBatch reach this through
# -CompareType 'ca', so fixing it here covers both.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')

    # The strength as Graph returns it inside a CA policy read.
    function New-ExpandedStrength {
        param(
            $Id = '00000000-0000-0000-0000-000000000002',
            $DisplayName = 'Multifactor authentication'
        )
        [pscustomobject]@{
            id                    = $Id
            createdDateTime       = '2021-12-01T08:00:00Z'
            modifiedDateTime      = '2021-12-01T08:00:00Z'
            displayName           = $DisplayName
            description           = 'Combinations of methods that satisfy strong authentication, such as a password + SMS'
            policyType            = 'builtIn'
            requirementsSatisfied = 'mfa'
            allowedCombinations   = @('windowsHelloForBusiness', 'fido2', 'x509CertificateMultiFactor', 'password,sms')
        }
    }

    function New-CAPolicy {
        param($Strength, $State = 'enabled')
        $GrantControls = [pscustomobject]@{ operator = 'OR'; builtInControls = @() }
        if ($Strength) {
            $GrantControls | Add-Member -NotePropertyName 'authenticationStrength' -NotePropertyValue $Strength
        }
        [pscustomobject]@{
            displayName   = 'Require MFA for all Users'
            state         = $State
            conditions    = [pscustomobject]@{
                users        = [pscustomobject]@{ includeUsers = @('All'); excludeUsers = @() }
                applications = [pscustomobject]@{ includeApplications = @('All') }
            }
            grantControls = $GrantControls
        }
    }
}

Describe "Compare-CIPPIntuneObject -CompareType 'ca'" {
    It 'reports no drift for an id-only template against the expanded live policy' {
        $Template = New-CAPolicy -Strength ([pscustomobject]@{ id = '00000000-0000-0000-0000-000000000002' })

        $Compare = Compare-CIPPIntuneObject -ReferenceObject $Template -DifferenceObject (New-CAPolicy -Strength (New-ExpandedStrength)) -CompareType 'ca'

        $Compare | Should -BeNullOrEmpty
    }

    It 'reports no drift when allowedCombinations come back in a different order' {
        $LiveStrength = New-ExpandedStrength
        $LiveStrength.allowedCombinations = @('password,sms', 'fido2', 'windowsHelloForBusiness', 'x509CertificateMultiFactor')

        $Compare = Compare-CIPPIntuneObject -ReferenceObject (New-CAPolicy -Strength (New-ExpandedStrength)) -DifferenceObject (New-CAPolicy -Strength $LiveStrength) -CompareType 'ca'

        $Compare | Should -BeNullOrEmpty
    }

    It 'still reports drift when the tenant uses a different strength' {
        $Template = New-CAPolicy -Strength (New-ExpandedStrength -Id '00000000-0000-0000-0000-000000000004' -DisplayName 'Phishing-resistant MFA')

        $Compare = @(Compare-CIPPIntuneObject -ReferenceObject $Template -DifferenceObject (New-CAPolicy -Strength (New-ExpandedStrength)) -CompareType 'ca')

        $Compare.Count | Should -Be 1
        $Compare[0].Property | Should -Be 'grantControls.authenticationStrength.displayName'
        $Compare[0].ExpectedValue | Should -Be 'Phishing-resistant MFA'
        $Compare[0].ReceivedValue | Should -Be 'Multifactor authentication'
    }

    It 'still reports drift when the tenant policy dropped the strength entirely' {
        $Compare = @(Compare-CIPPIntuneObject -ReferenceObject (New-CAPolicy -Strength (New-ExpandedStrength)) -DifferenceObject (New-CAPolicy) -CompareType 'ca')

        $Compare.Count | Should -Be 1
        $Compare[0].Property | Should -Be 'grantControls.authenticationStrength'
    }

    It 'still reports genuine drift elsewhere in the policy' {
        $Compare = @(Compare-CIPPIntuneObject -ReferenceObject (New-CAPolicy -Strength (New-ExpandedStrength) -State 'enabled') -DifferenceObject (New-CAPolicy -Strength (New-ExpandedStrength) -State 'disabled') -CompareType 'ca')

        $Compare.Count | Should -Be 1
        $Compare[0].Property | Should -Be 'state'
    }

    It 'does not mutate the objects it was given' {
        $Live = New-CAPolicy -Strength (New-ExpandedStrength)

        $null = Compare-CIPPIntuneObject -ReferenceObject (New-CAPolicy -Strength (New-ExpandedStrength)) -DifferenceObject $Live -CompareType 'ca'

        $Live.grantControls.authenticationStrength.allowedCombinations | Should -Not -BeNullOrEmpty
        $Live.grantControls.authenticationStrength.policyType | Should -Be 'builtIn'
    }

    It 'leaves comparisons that did not opt in alone' {
        $Template = New-CAPolicy -Strength ([pscustomobject]@{ id = '00000000-0000-0000-0000-000000000002' })

        $Compare = @(Compare-CIPPIntuneObject -ReferenceObject $Template -DifferenceObject (New-CAPolicy -Strength (New-ExpandedStrength)))

        $Compare.Property | Should -Contain 'grantControls.authenticationStrength.allowedCombinations'
    }
}
