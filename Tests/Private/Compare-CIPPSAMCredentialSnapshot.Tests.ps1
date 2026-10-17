# The credential monitor must alert on CIPP-SAM credentials added or removed outside CIPP, never on
# the first run, and not again for changes CIPP itself made and acknowledged.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPSAMCredentials {}
    function Get-CIPPTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Send-CIPPAlert { param($Type, $Title, $HTMLContent, $JSONContent, $TenantFilter, $APIName) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Compare-CIPPSAMCredentialSnapshot.ps1')

    $script:Cred = {
        param($KeyId, $Name, $Owner = 'external', $Source = $null)
        [pscustomobject]@{ keyId = $KeyId; displayName = $Name; type = 'Secret'; thumbprint = $null; endDateTime = '2028-01-01T00:00:00Z'; owner = $Owner; source = $Source; actor = 'admin@contoso.com' }
    }
    $script:StateOf = { param($Creds) [pscustomobject]@{ ApplicationId = 'sam-app-id'; Credentials = @($Creds) } }
}

Describe 'Compare-CIPPSAMCredentialSnapshot' {
    BeforeEach {
        Mock Get-CIPPTable { @{} }
        Mock Add-CIPPAzDataTableEntity {}
        Mock Send-CIPPAlert {}
        Mock Write-LogMessage {}
    }

    It 'stores a snapshot and raises nothing on the first run' {
        Mock Get-CIPPAzDataTableEntity { $null }

        $null = Compare-CIPPSAMCredentialSnapshot -CredentialState (& $StateOf @(& $Cred 'k1' 'Existing'))

        Should -Invoke Send-CIPPAlert -Times 0 -Exactly
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.RowKey -eq 'Snapshot' -and $Entity.Snapshot -match 'k1' }
    }

    It 'alerts on every channel for a credential added outside CIPP, and on a removal' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ Snapshot = (ConvertTo-Json -Compress -InputObject @([pscustomobject]@{ keyId = 'k1'; displayName = 'Old'; type = 'Secret' })) } }

        $Changes = Compare-CIPPSAMCredentialSnapshot -CredentialState (& $StateOf @(& $Cred 'k2' 'Attacker'))

        @($Changes).Count | Should -Be 2
        Should -Invoke Send-CIPPAlert -Times 6 -Exactly
        Should -Invoke Send-CIPPAlert -Times 1 -Exactly -ParameterFilter { $Type -eq 'email' -and $Title -match 'added: Attacker' -and $HTMLContent -match 'not created by this CIPP instance; review it' }
        Should -Invoke Send-CIPPAlert -Times 1 -Exactly -ParameterFilter { $Type -eq 'webhook' -and $Title -match 'removed: Old' }
    }

    It 'labels a CIPP-created credential with its provenance' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ Snapshot = '[]' } }

        $null = Compare-CIPPSAMCredentialSnapshot -CredentialState (& $StateOf @(& $Cred 'k3' 'UpdateTokens' 'otherCipp' 'Manual'))

        Should -Invoke Send-CIPPAlert -Times 1 -Exactly -ParameterFilter { $Type -eq 'email' -and $HTMLContent -match 'Created by CIPP \(manual, by admin@contoso.com\)' }
    }

    It 'still alerts on acknowledged changes, worded as no action needed, and alerts unrelated ones for review' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ Snapshot = '[]' } }

        $null = Compare-CIPPSAMCredentialSnapshot -Acknowledge 'mine' -CredentialState (& $StateOf @((& $Cred 'mine' 'UpdateTokens' 'thisInstance' 'ScheduledRotation'), (& $Cred 'theirs' 'Unknown app')))

        Should -Invoke Send-CIPPAlert -Times 6 -Exactly
        Should -Invoke Send-CIPPAlert -Times 1 -Exactly -ParameterFilter { $Type -eq 'email' -and $Title -match 'UpdateTokens' -and $HTMLContent -match 'scheduled rotation\). No action needed' }
        Should -Invoke Send-CIPPAlert -Times 1 -Exactly -ParameterFilter { $Type -eq 'email' -and $Title -match 'Unknown app' -and $HTMLContent -match 'review it' }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.Snapshot -match 'mine' -and $Entity.Snapshot -match 'theirs' }
    }

    It 'words an acknowledged removal with the note instead of as an outside change' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ Snapshot = (ConvertTo-Json -Compress -InputObject @([pscustomobject]@{ keyId = 'gone'; displayName = 'Rewst'; type = 'Secret' })) } }

        $null = Compare-CIPPSAMCredentialSnapshot -Acknowledge 'gone' -AcknowledgeNote 'Revoked by CIPP (manual, by admin@contoso.com).' -CredentialState (& $StateOf @())

        Should -Invoke Send-CIPPAlert -Times 1 -Exactly -ParameterFilter { $Type -eq 'email' -and $Title -match 'removed: Rewst' -and $HTMLContent -match 'Revoked by CIPP \(manual, by admin@contoso.com\)\. No action needed' -and $HTMLContent -notmatch 'review it' }
    }

    It 'never throws when a notification channel fails' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ Snapshot = '[]' } }
        Mock Send-CIPPAlert { throw 'no channel' }

        { Compare-CIPPSAMCredentialSnapshot -CredentialState (& $StateOf @(& $Cred 'k4' 'New')) } | Should -Not -Throw
    }
}
