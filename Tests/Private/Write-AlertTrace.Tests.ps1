# Pester tests for Write-AlertTrace

BeforeAll {
    # Resolve by name under Modules/ so the test survives the function moving between modules.
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Write-AlertTrace.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Write-AlertTrace.ps1 under Modules/' }

    # Stub every CIPP helper the function calls so Pester's Mock has a command to replace.
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Get-CIPPTable { param($tablename) }
    function Remove-SnoozedAlerts { param($Data, $CmdletName, $TenantFilter) }

    . $FunctionPath
}

Describe 'Write-AlertTrace' {
    BeforeEach {
        Mock -CommandName Get-CIPPTable -MockWith { @{ TableName = 'AlertLastRun' } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        # Pass items through unfiltered (nothing snoozed) unless a test overrides this.
        Mock -CommandName Remove-SnoozedAlerts -MockWith { $Data }

        $script:AlertData = @([pscustomobject]@{ UserPrincipalName = 'admin@contoso.com'; Message = 'MFA disabled' })
    }

    It 'writes a new row and returns the data when no row exists for today' {
        $Result = Write-AlertTrace -cmdletName 'Get-CIPPAlertMFAAdmins' -tenantFilter 'contoso.com' -data $script:AlertData

        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Entity.RowKey -eq 'contoso.com-Get-CIPPAlertMFAAdmins' -and
            $Entity.CmdletName -eq 'Get-CIPPAlertMFAAdmins' -and
            -not [string]::IsNullOrWhiteSpace($Entity.LastSeen)
        }
        @($Result).Count | Should -Be 1
        @($Result)[0].UserPrincipalName | Should -Be 'admin@contoso.com'
    }

    It 'writes a new row and returns the data when the stored data differs' {
        $OldData = ConvertTo-Json -InputObject @([pscustomobject]@{ UserPrincipalName = 'other@contoso.com' }) -Compress -Depth 10 | Out-String
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{ RowKey = 'contoso.com-Get-CIPPAlertMFAAdmins'; LogData = $OldData }
        }

        $Result = Write-AlertTrace -cmdletName 'Get-CIPPAlertMFAAdmins' -tenantFilter 'contoso.com' -data $script:AlertData

        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly
        @($Result)[0].UserPrincipalName | Should -Be 'admin@contoso.com'
    }

    It 'refreshes LastSeen but returns nothing when the stored data is unchanged' {
        # Output drives notifications, so an unchanged persisting condition must stay
        # silent; the LastSeen stamp is what tells the scheduler the alert still fires.
        $StoredData = ConvertTo-Json -InputObject $script:AlertData -Compress -Depth 10 | Out-String
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{ RowKey = 'contoso.com-Get-CIPPAlertMFAAdmins'; LogData = $StoredData }
        }

        $Result = Write-AlertTrace -cmdletName 'Get-CIPPAlertMFAAdmins' -tenantFilter 'contoso.com' -data $script:AlertData

        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            -not [string]::IsNullOrWhiteSpace($Entity.LastSeen)
        }
        $Result | Should -BeNullOrEmpty
    }

    It 'returns null and writes nothing when every item is snoozed' {
        Mock -CommandName Remove-SnoozedAlerts -MockWith { @() }

        $Result = Write-AlertTrace -cmdletName 'Get-CIPPAlertMFAAdmins' -tenantFilter 'contoso.com' -data $script:AlertData

        $Result | Should -BeNullOrEmpty
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly
    }
}
