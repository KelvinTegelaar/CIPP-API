BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public'

    function New-CIPPDbRequest { param($TenantFilter, $Type) }
    function New-ExoBulkRequest { param($tenantid, $cmdletArray, $useSystemMailbox, $Select, [int]$MaxConcurrency = 1, [switch]$Compliance) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) }
    function Set-CIPPDBCacheMailboxes { param($TenantFilter, $Types) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev) }
    function Get-CIPPBaselineCommand { param($Name) }

    . (Join-Path $Baselines 'PrepareHooks/Get-CIPPBaselineSetDefaultMailboxFontState.ps1')
    . (Join-Path $Baselines 'Executors/Invoke-CIPPBaselineExoBulkSweep.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheMailboxMessageConfiguration.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:Definition = Get-Content (Join-Path $script:RepoRoot 'Config/BaselineStandards/Exchange Standards/SetDefaultMailboxFont.json') -Raw | ConvertFrom-Json
    $script:Mailboxes = @(
        [PSCustomObject]@{ UPN = 'alice@contoso.com'; recipientTypeDetails = 'UserMailbox' }
        [PSCustomObject]@{ UPN = 'info@contoso.com'; recipientTypeDetails = 'SharedMailbox' }
        [PSCustomObject]@{ UPN = 'room@contoso.com'; recipientTypeDetails = 'RoomMailbox' }
        [PSCustomObject]@{ UPN = 'gone@contoso.com'; recipientTypeDetails = 'UserMailbox'; WhenSoftDeleted = '2026-01-01' }
    )
    function Get-FontRow { param($UPN, $Name = 'Aptos', $Size = 3, $Color = '#000000', $ErrorText) [PSCustomObject]@{ id = $UPN; DefaultFontName = $Name; DefaultFontSize = $Size; DefaultFontColor = $Color; error = $ErrorText } }
    function Invoke-Hook {
        param($Name = 'Aptos', $Size = '3', $Color = '#000000')
        Get-CIPPBaselineSetDefaultMailboxFontState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{ DefaultFontName = $Name; DefaultFontSize = $Size; DefaultFontColor = $Color } }) -TenantFilter $script:Tenant
    }
}

Describe 'Get-CIPPBaselineSetDefaultMailboxFontState' {
    BeforeEach {
        Mock New-CIPPDbRequest { @() }
        Mock New-ExoBulkRequest { @() }
    }

    It 'grades the MailboxMessageConfiguration cache and makes no live Exchange call' {
        Mock New-CIPPDbRequest { @(Get-FontRow 'alice@contoso.com') }
        $null = Invoke-Hook
        Should -Invoke New-CIPPDbRequest -Times 1 -Exactly -ParameterFilter { $Type -eq 'MailboxMessageConfiguration' }
        Should -Invoke New-ExoBulkRequest -Times 0 -Exactly
    }

    It 'is compliant when every mailbox matches, case-insensitively on name and colour' {
        Mock New-CIPPDbRequest { @(Get-FontRow 'alice@contoso.com' -Name 'aptos' -Size '3'; Get-FontRow 'info@contoso.com' -Color '#000000') }
        $Prepared = Invoke-Hook -Color '#000000'
        $Prepared.Current.offenders | Should -BeNullOrEmpty
        $Prepared.Current.unreadable | Should -BeNullOrEmpty
        $Prepared.Current.targets | Should -BeNullOrEmpty
    }

    It 'flags a mailbox that differs on name, size or colour and targets it by UPN' {
        Mock New-CIPPDbRequest { @(
                Get-FontRow 'a@contoso.com' -Name 'Calibri'
                Get-FontRow 'b@contoso.com' -Size 2
                Get-FontRow 'c@contoso.com' -Color '#FF0000'
                Get-FontRow 'd@contoso.com'
            ) }
        $Prepared = Invoke-Hook
        $Prepared.Current.offenders | Should -Be @('a@contoso.com', 'b@contoso.com', 'c@contoso.com')
        $Prepared.Current.targets.id | Should -Be @('a@contoso.com', 'b@contoso.com', 'c@contoso.com')
    }

    It 'reports failed reads and rows missing a size as unreadable, not compliant' {
        Mock New-CIPPDbRequest { @(
                Get-FontRow 'ok@contoso.com'
                Get-FontRow 'err@contoso.com' -ErrorText 'boom'
                Get-FontRow 'nosize@contoso.com' -Size $null
            ) }
        $Prepared = Invoke-Hook
        $Prepared.Current.unreadable | Should -Be @('err@contoso.com', 'nosize@contoso.com')
        $Prepared.Current.offenders | Should -BeNullOrEmpty
    }

    It 'returns No Data when no cached mailbox could be read' {
        Mock New-CIPPDbRequest { @(Get-FontRow 'a@contoso.com' -ErrorText 'denied') }
        $Prepared = Invoke-Hook
        $Prepared.Current | Should -BeNullOrEmpty
        $Prepared.NoDataReason | Should -Match 'no mailbox message configuration'
    }

    It 'returns a null Current on an empty cache so the engine collects' {
        $Prepared = Invoke-Hook
        $Prepared.Current | Should -BeNullOrEmpty
        $Prepared.NoDataReason | Should -BeNullOrEmpty
    }

    It 'rejects <Case> before reading anything' -ForEach @(
        @{ Case = 'a size out of range'; Size = '8'; Color = '#000000'; Reason = 'not a valid font size' }
        @{ Case = 'a non-numeric size'; Size = 'big'; Color = '#000000'; Reason = 'not a valid font size' }
        @{ Case = 'shorthand colour'; Size = '3'; Color = '#000'; Reason = 'not a valid hex colour' }
    ) {
        $Prepared = Invoke-Hook -Size $Size -Color $Color
        $Prepared.Current | Should -BeNullOrEmpty
        $Prepared.NoDataReason | Should -Match $Reason
        Should -Invoke New-CIPPDbRequest -Times 0 -Exactly
    }
}

Describe 'Set-CIPPDBCacheMailboxMessageConfiguration' {
    BeforeEach {
        Mock New-CIPPDbRequest { $script:Mailboxes }
        Mock New-ExoBulkRequest { @($cmdletArray | ForEach-Object { [PSCustomObject]@{ OperationGuid = $_.OperationGuid; Identity = "CN=$($_.OperationGuid)"; DefaultFontName = 'Aptos'; DefaultFontSize = 3; DefaultFontColor = '#000000' } }) }
        Mock Add-CIPPDbItem {}
        Mock Set-CIPPDBCacheMailboxes {}
        Mock Write-LogMessage {}
    }

    It 'reads only live user and shared mailboxes, batched and fanned out under the EXO ceiling' {
        Set-CIPPDBCacheMailboxMessageConfiguration -TenantFilter $script:Tenant
        Should -Invoke New-ExoBulkRequest -Times 1 -Exactly -ParameterFilter {
            $Ids = @($cmdletArray | ForEach-Object { $_.CmdletInput.Parameters.Identity })
            $Select -eq 'Identity,DefaultFontName,DefaultFontSize,DefaultFontColor' -and
            @($cmdletArray.CmdletInput.CmdletName | Sort-Object -Unique) -eq 'Get-MailboxMessageConfiguration' -and
            ($Ids -join ',') -eq 'alice@contoso.com,info@contoso.com' -and
            $MaxConcurrency -eq 32
        }
    }

    It 'writes one row per mailbox keyed by UPN, carrying read failures and missing responses as errors' {
        Mock New-ExoBulkRequest { @([PSCustomObject]@{ OperationGuid = 'alice@contoso.com'; error = 'denied' }) }
        Set-CIPPDBCacheMailboxMessageConfiguration -TenantFilter $script:Tenant
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter {
            $Rows = @($Data)
            $Type -eq 'MailboxMessageConfiguration' -and $AddCount -and $ClearOnEmpty -and $Rows.Count -eq 2 -and
            $Rows[0].id -eq 'alice@contoso.com' -and $Rows[0].error -eq 'denied' -and
            $Rows[1].id -eq 'info@contoso.com' -and $Rows[1].error -eq 'no response'
        }
    }

    It 'stores the font values of a successful read with no error' {
        Set-CIPPDBCacheMailboxMessageConfiguration -TenantFilter $script:Tenant
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter {
            $Row = @($Data)[0]
            $Row.DefaultFontName -eq 'Aptos' -and $Row.DefaultFontSize -eq 3 -and $Row.DefaultFontColor -eq '#000000' -and $null -eq $Row.error
        }
    }

    It 'collects the mailbox list first when it has never been cached' {
        Mock New-CIPPDbRequest { @() }
        Set-CIPPDBCacheMailboxMessageConfiguration -TenantFilter $script:Tenant
        Should -Invoke Set-CIPPDBCacheMailboxes -Times 1 -Exactly -ParameterFilter { $Types -eq 'None' }
        Should -Invoke New-ExoBulkRequest -Times 0 -Exactly
    }
}

Describe 'SetDefaultMailboxFont definition' {
    It 'reads its own cache and keeps it fresh through requiredCaches' {
        $script:Definition.read.cacheType | Should -Be 'MailboxMessageConfiguration'
        @($script:Definition.read.requiredCaches) | Should -Contain 'MailboxMessageConfiguration'
    }

    It 'grades unreadable mailboxes as drift alongside offenders' {
        @($script:Definition.expected.PSObject.Properties.Name) | Should -Be @('offenders', 'unreadable')
    }

    It 'declares the size as a number so the engine writes an integer' {
        $script:Definition.variables.DefaultFontSize.type | Should -Be 'number'
        $script:Definition.remediate.executor | Should -Be 'ExoBulkSweep'
    }

    It 'sends Set-MailboxMessageConfiguration with all three values to each offender only, fanned out under the EXO ceiling' {
        Mock New-ExoBulkRequest { @() }
        $Json = (ConvertTo-Json -Depth 20 -Compress -InputObject $script:Definition.remediate).
        Replace('"%DefaultFontName%"', '"Aptos"').Replace('"%DefaultFontSize%"', '3').Replace('"%DefaultFontColor%"', '"#000000"')
        $Current = [PSCustomObject]@{ targets = @([PSCustomObject]@{ id = 'a@contoso.com' }) }
        Invoke-CIPPBaselineExoBulkSweep -Remediate ($Json | ConvertFrom-Json) -TenantFilter $script:Tenant -Current $Current
        Should -Invoke New-ExoBulkRequest -Times 1 -Exactly -ParameterFilter {
            $P = $cmdletArray[0].CmdletInput.Parameters
            @($cmdletArray).Count -eq 1 -and $cmdletArray[0].CmdletInput.CmdletName -eq 'Set-MailboxMessageConfiguration' -and
            $P.Identity -eq 'a@contoso.com' -and $P.DefaultFontName -eq 'Aptos' -and $P.DefaultFontSize -eq 3 -and $P.DefaultFontSize -is [long] -and $P.DefaultFontColor -eq '#000000' -and
            $MaxConcurrency -eq 16
        }
    }
}
