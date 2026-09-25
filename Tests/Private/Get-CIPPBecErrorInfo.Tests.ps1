BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecErrorInfo.ps1')
}

Describe 'Get-CIPPBecErrorInfo' {
    It 'treats a missing mailbox as not-applicable, not a failure' {
        $I = Get-CIPPBecErrorInfo -Message 'Ex41BAF5|Microsoft.Exchange.Configuration.Tasks.ManagementObjectNotFoundException|The specified mailbox Identity:"alex@contoso.com" doesn''t exist.'
        $I.Skipped | Should -BeTrue
        $I.Message | Should -Be 'This user has no Exchange Online mailbox.'
        $I.Requirement | Should -Match 'no Exchange Online mailbox'
    }

    It 'treats a not-a-recipient error as not-applicable' {
        $I = Get-CIPPBecErrorInfo -Message "Get-RecipientPermission: Ex6F9304|Type|Couldn't find 'alex@contoso.com' as a recipient."
        $I.Skipped | Should -BeTrue
    }

    It 'treats an Intune 404 / not-provisioned as not-applicable with a retry hint' {
        $I = Get-CIPPBecErrorInfo -Message 'Intune returned an unexpected error (HTTP 404). ... the tenant does not have Intune provisioned. Microsoft support reference (Activity ID): 1967-68c5'
        $I.Skipped | Should -BeTrue
        $I.Message | Should -Match 'rerun'
        $I.Message | Should -Not -Match 'Activity ID'
    }

    It 'treats Intune "not applicable to target tenant" (no Intune licence) as not-applicable' {
        $I = Get-CIPPBecErrorInfo -Message 'Request not applicable to target tenant. - Operation ID (for customer support): 6f1b - Activity ID: 1967-68c5 - Url: https://fef.msub03.manage.microsoft.com/DeviceFE/StatelessDeviceFEService/deviceManagement/users(''guid'')/managedDevices?api-version=5024-03-01'
        $I.Skipped | Should -BeTrue
        $I.Message | Should -Be 'Intune is not licensed for this tenant.'
        $I.Requirement | Should -Match 'Intune licence'
    }

    It 'keeps a transient Intune service error as a failure, not a skip' {
        $I = Get-CIPPBecErrorInfo -Message 'Intune returned an unexpected error (HTTP 503). This is a failure inside the Intune service itself and is usually transient. Rerun the check to retry. Microsoft support reference (Activity ID): 1967-68c5'
        $I.Skipped | Should -BeFalse
        $I.Message | Should -Match 'transient'
        $I.Message | Should -Not -Match 'Activity ID'
    }

    It 'strips the Exchange diagnostic prefix from a real failure' {
        $I = Get-CIPPBecErrorInfo -Message 'Ex3F6FA7|Microsoft.Exchange.Management.Tasks.SomeException|The server is busy, try again.'
        $I.Skipped | Should -BeFalse
        $I.Message | Should -Be 'The server is busy, try again.'
    }

    It 'passes a plain message through and drops a support-reference tail' {
        $I = Get-CIPPBecErrorInfo -Message 'Graph request failed. Microsoft support reference (Activity ID): abc-123'
        $I.Skipped | Should -BeFalse
        $I.Message | Should -Be 'Graph request failed.'
    }

    It 'returns null for an empty error' {
        (Get-CIPPBecErrorInfo -Message '').Message | Should -BeNullOrEmpty
        (Get-CIPPBecErrorInfo -Message $null).Skipped | Should -BeFalse
    }
}
