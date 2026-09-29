BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:OriginalRoot = $env:CIPPRootPath
    $env:CIPPRootPath = $RepoRoot
    function Search-CIPPBecAuditLog { param($TenantFilter, $StartDate, $EndDate, $Operations, $UserIds, $RecordType, $ObjectIds, $Anchor, $PageSize, $MaxPages) }
    function Get-NormalizedError { param($message) $message }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecHeuristics.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/New-CIPPBecCollectorResult.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/ConvertTo-CIPPBecHostAddress.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecMailActivity.ps1')
    $script:Heuristics = Get-CIPPBecHeuristics
    $script:Upn = 'victim@contoso.com'
    $script:Start = [datetime]::new(2026, 8, 13, 0, 0, 0, [System.DateTimeKind]::Utc)
    $script:End = [datetime]::new(2026, 8, 20, 0, 0, 0, [System.DateTimeKind]::Utc)

    # One record the way Search-CIPPBecAuditLog hands it back: AuditData already parsed. MailItemsAccessed
    # reports its IP as ClientIPAddress; the other mailbox operations use ClientIP.
    function New-Record {
        param(
            [string]$Operation,
            [string]$Actor = 'victim@contoso.com',
            [string]$ClientIP = '198.51.100.7',
            [string]$ClientInfo = 'Client=OWA;Mozilla/5.0',
            [string]$AccessType,
            [int]$OperationCount,
            [string]$Owner,
            [string]$When = '2026-08-15T09:00:00Z',
            [string]$SessionId,
            [switch]$LegacyIPProperty,
            [switch]$AccessTypeInProperties
        )
        $AuditData = [ordered]@{
            Operation        = $Operation
            CreationTime     = $When
            UserId           = $Actor
            ClientInfoString = $ClientInfo
            LogonType        = 0
        }
        if ($LegacyIPProperty) { $AuditData.ClientIP = $ClientIP } else { $AuditData.ClientIPAddress = $ClientIP }
        if ($AccessType -and $AccessTypeInProperties) { $AuditData.OperationProperties = @([pscustomobject]@{ Name = 'MailAccessType'; Value = $AccessType }, [pscustomobject]@{ Name = 'IsThrottled'; Value = 'False' }) }
        elseif ($AccessType) { $AuditData.MailAccessType = $AccessType }
        if ($SessionId) { $AuditData.SessionId = $SessionId }
        if ($OperationCount) { $AuditData.OperationCount = $OperationCount }
        if ($Owner) { $AuditData.MailboxOwnerUPN = $Owner }
        [pscustomobject]@{
            Identity  = [guid]::NewGuid().ToString()
            Operation = $Operation
            UserId    = $Actor
            AuditData = [pscustomobject]$AuditData
        }
    }
    function New-Search {
        param($Records, [bool]$Complete = $true, $Cap = $null)
        [pscustomobject]@{ Records = @($Records); Complete = $Complete; Cap = $Cap; Pages = 1 }
    }
}

AfterAll {
    $env:CIPPRootPath = $script:OriginalRoot
}

Describe 'Get-CIPPBecMailActivity' {
    BeforeEach {
        $script:UserRecords = @()
        $script:OwnerRecords = @()
        $script:UserComplete = $true
        $script:UserCap = $null
        # The user-scoped search carries UserIds; the tenant-wide SendAs/SendOnBehalf search does not.
        Mock Search-CIPPBecAuditLog { New-Search -Records $script:OwnerRecords }
        Mock Search-CIPPBecAuditLog -ParameterFilter { $null -ne $UserIds } { New-Search -Records $script:UserRecords -Complete $script:UserComplete -Cap $script:UserCap }
    }

    It 'reduces the user''s records to counts per operation, IP and client with first/last seen, summing aggregated OperationCount' {
        $script:UserRecords = @(
            (New-Record -Operation 'MailItemsAccessed' -AccessType 'Bind' -OperationCount 12 -When '2026-08-15T09:00:00Z')
            (New-Record -Operation 'MailItemsAccessed' -AccessType 'Bind' -OperationCount 8 -When '2026-08-16T11:30:00Z')
            (New-Record -Operation 'MailItemsAccessed' -AccessType 'Sync' -OperationCount 3 -ClientIP '203.0.113.9' -ClientInfo 'Client=REST;python-requests')
            (New-Record -Operation 'HardDelete' -ClientIP '203.0.113.9' -ClientInfo 'Client=REST;python-requests' -LegacyIPProperty)
            (New-Record -Operation 'Send' -When '2026-08-17T08:00:00Z')
        )
        $Result = Get-CIPPBecMailActivity -TenantFilter 'contoso.com' -UserPrincipalName $script:Upn -StartDate $script:Start -EndDate $script:End -Heuristics $script:Heuristics -Anchor $script:Upn

        Should -Invoke Search-CIPPBecAuditLog -Times 1 -ParameterFilter { $UserIds -contains 'victim@contoso.com' -and $Operations -contains 'MailItemsAccessed' -and $Operations -contains 'Send' -and $MaxPages -eq 10 -and $Anchor -eq 'victim@contoso.com' -and $TenantFilter -eq 'contoso.com' }
        $Result.Complete | Should -BeTrue
        $Result.Cap | Should -BeNullOrEmpty
        $Result.Error | Should -BeNullOrEmpty
        $Result.Count | Should -Be 4
        $Result.Data.Count | Should -Be 4
        $Bind = $Result.Data[0]
        $Bind.PSObject.Properties.Name | Should -Be @('Operation', 'ClientIP', 'ClientInfoString', 'MailAccessType', 'LogonType', 'Actor', 'MailboxOwner', 'Count', 'Records', 'FirstSeen', 'LastSeen', 'SessionIds')
        $Bind.Operation | Should -Be 'MailItemsAccessed'
        $Bind.Count | Should -Be 20 -Because 'aggregated MailItemsAccessed records contribute their OperationCount'
        $Bind.Records | Should -Be 2
        $Bind.ClientIP | Should -Be '198.51.100.7'
        $Bind.MailAccessType | Should -Be 'Bind'
        $Bind.Actor | Should -Be 'victim@contoso.com'
        $Bind.MailboxOwner | Should -Be 'victim@contoso.com' -Because 'the actor owns the mailbox when no MailboxOwnerUPN is recorded'
        $Bind.FirstSeen | Should -Be '2026-08-15T09:00:00Z'
        $Bind.LastSeen | Should -Be '2026-08-16T11:30:00Z'
        $Result.Data[1].Count | Should -Be 3 -Because 'groups sort by count, descending'
        ($Result.Data | Where-Object { $_.Operation -eq 'HardDelete' }).ClientIP | Should -Be '203.0.113.9' -Because 'the ClientIP property is read as well as ClientIPAddress'

        $Result.Summary.Records | Should -Be 5
        $Result.Summary.MailItemsAccessedCount | Should -Be 23
        $Result.Summary.HardDeleteCount | Should -Be 1
        $Result.Summary.SoftDeleteCount | Should -Be 0
        $Result.Summary.SendCount | Should -Be 1
        $Result.Summary.ByOperation.MailItemsAccessed | Should -Be 23
        $Result.Summary.DistinctClientIPs | Should -Be 2
        $Result.Summary.HardDeleteExceeded | Should -BeFalse
        $Result.Summary.SendAsByOthersCount | Should -Be 0
    }

    It 'keeps tenant-wide SendAs/SendOnBehalf records only where the user is the owner or the actor, and counts sends by others' {
        $script:OwnerRecords = @(
            (New-Record -Operation 'SendAs' -Actor 'attacker@contoso.com' -Owner $script:Upn -ClientIP '203.0.113.9')
            (New-Record -Operation 'SendAs' -Actor 'attacker@contoso.com' -Owner $script:Upn -ClientIP '203.0.113.9' -When '2026-08-15T10:00:00Z')
            (New-Record -Operation 'SendOnBehalf' -Actor 'assistant@contoso.com' -Owner 'other@contoso.com')
            (New-Record -Operation 'SendAs' -Actor $script:Upn -Owner 'shared@contoso.com')
            [pscustomobject]@{ Identity = 'no-auditdata'; Operation = 'SendAs'; AuditData = $null }
        )
        $Result = Get-CIPPBecMailActivity -TenantFilter 'contoso.com' -UserPrincipalName $script:Upn -StartDate $script:Start -EndDate $script:End -Heuristics $script:Heuristics

        Should -Invoke Search-CIPPBecAuditLog -Times 1 -ParameterFilter { $null -eq $UserIds -and $Operations -contains 'SendAs' -and $Operations -contains 'SendOnBehalf' -and $Operations -notcontains 'Send' }
        $Result.Complete | Should -BeTrue
        $Result.Data.Count | Should -Be 2
        $Result.Data.Actor | Should -Not -Contain 'assistant@contoso.com' -Because 'a delegation on another mailbox is not this user''s activity'
        $ByAttacker = $Result.Data | Where-Object { $_.Actor -eq 'attacker@contoso.com' }
        $ByAttacker.Count | Should -Be 2
        $ByAttacker.MailboxOwner | Should -Be 'victim@contoso.com'
        $Result.Summary.Records | Should -Be 3
        $Result.Summary.ByOperation.SendAs | Should -Be 3
        $Result.Summary.SendAsByOthersCount | Should -Be 2 -Because 'the user sending as a shared mailbox is not someone else sending as the user'
    }

    It 'flags HardDeleteExceeded from the heuristics threshold, with the threshold itself counting as exceeded' {
        $Threshold = [int]$script:Heuristics.mailActivity.hardDeleteThreshold
        $script:UserRecords = @(1..$Threshold | ForEach-Object { New-Record -Operation 'HardDelete' })
        $Result = Get-CIPPBecMailActivity -TenantFilter 'contoso.com' -UserPrincipalName $script:Upn -StartDate $script:Start -EndDate $script:End -Heuristics $script:Heuristics
        $Result.Summary.HardDeleteCount | Should -Be $Threshold
        $Result.Summary.HardDeleteThreshold | Should -Be $Threshold
        $Result.Summary.HardDeleteExceeded | Should -BeTrue
        $Result.Data.Count | Should -Be 1 -Because 'identical records from one IP and client collapse into one group'
        $Result.Data[0].Records | Should -Be $Threshold

        $script:UserRecords = @(1..($Threshold - 1) | ForEach-Object { New-Record -Operation 'HardDelete' })
        $Result = Get-CIPPBecMailActivity -TenantFilter 'contoso.com' -UserPrincipalName $script:Upn -StartDate $script:Start -EndDate $script:End -Heuristics $script:Heuristics
        $Result.Summary.HardDeleteCount | Should -Be ($Threshold - 1)
        $Result.Summary.HardDeleteExceeded | Should -BeFalse
    }

    It 'stores every group, busiest first, and passes caps.mailActivityPages on as the audit-log slice budget' {
        $Budget = [pscustomobject]@{
            mailActivity = $script:Heuristics.mailActivity
            caps         = [pscustomobject]@{ mailActivityPages = 2 }
        }
        $script:UserRecords = @(1..5 | ForEach-Object { New-Record -Operation 'MailItemsAccessed' -ClientIP "203.0.113.$_" -OperationCount $_ })
        $Result = Get-CIPPBecMailActivity -TenantFilter 'contoso.com' -UserPrincipalName $script:Upn -StartDate $script:Start -EndDate $script:End -Heuristics $Budget

        Should -Invoke Search-CIPPBecAuditLog -Times 1 -ParameterFilter { $null -ne $UserIds -and $MaxPages -eq 2 }
        $Result.Data.Count | Should -Be 5
        @($Result.Data | ForEach-Object Count) | Should -Be @(5, 4, 3, 2, 1)
        $Result.Count | Should -Be 5
        $Result.Complete | Should -BeTrue
        $Result.Cap | Should -BeNullOrEmpty
        $Result.Error | Should -BeNullOrEmpty
        $Result.Summary.MailItemsAccessedCount | Should -Be 15
        $Result.Summary.DistinctClientIPs | Should -Be 5
    }

    It 'reports a capped audit search as incomplete with the search''s own cap text and still returns the partial rows' {
        $script:UserRecords = @((New-Record -Operation 'SoftDelete'))
        $script:UserComplete = $false
        $script:UserCap = '10 pages of 5000 records in a 60-minute slice'
        $Result = Get-CIPPBecMailActivity -TenantFilter 'contoso.com' -UserPrincipalName $script:Upn -StartDate $script:Start -EndDate $script:End -Heuristics $script:Heuristics
        $Result.Complete | Should -BeFalse
        $Result.Cap | Should -Be '10 pages of 5000 records in a 60-minute slice'
        $Result.Error | Should -BeNullOrEmpty
        $Result.Data.Count | Should -Be 1
        $Result.Summary.SoftDeleteCount | Should -Be 1
    }

    It 'records a failed user search as an error and still returns what the send-as search found' {
        Mock Search-CIPPBecAuditLog -ParameterFilter { $null -ne $UserIds } { throw 'UAL unavailable' }
        $script:OwnerRecords = @((New-Record -Operation 'SendOnBehalf' -Actor 'attacker@contoso.com' -Owner $script:Upn))
        $Result = Get-CIPPBecMailActivity -TenantFilter 'contoso.com' -UserPrincipalName $script:Upn -StartDate $script:Start -EndDate $script:End -Heuristics $script:Heuristics
        Should -Invoke Search-CIPPBecAuditLog -Exactly -Times 2
        $Result.Complete | Should -BeFalse
        $Result.Error | Should -Be 'user activity search: UAL unavailable'
        $Result.Cap | Should -BeNullOrEmpty
        $Result.Data.Count | Should -Be 1
        $Result.Data[0].Operation | Should -Be 'SendOnBehalf'
        $Result.Summary.SendAsByOthersCount | Should -Be 1
    }

    It 'truncates long client info strings and skips records that carry no AuditData' {
        $LongInfo = 'Client=REST;' + ('x' * 200)
        $script:UserRecords = @(
            (New-Record -Operation 'MailItemsAccessed' -ClientInfo $LongInfo -OperationCount 4)
            [pscustomobject]@{ Identity = 'broken'; Operation = 'HardDelete'; AuditData = $null }
        )
        $Result = Get-CIPPBecMailActivity -TenantFilter 'contoso.com' -UserPrincipalName $script:Upn -StartDate $script:Start -EndDate $script:End -Heuristics $script:Heuristics
        $Result.Complete | Should -BeTrue
        $Result.Data.Count | Should -Be 1
        $Result.Data[0].ClientInfoString.Length | Should -Be 123
        $Result.Data[0].ClientInfoString | Should -BeLike 'Client=REST;x*...'
        $Result.Summary.HardDeleteCount | Should -Be 0
        $Result.Summary.MailItemsAccessedCount | Should -Be 4
    }

    It 'reads the access type from OperationProperties, lists the sessions per row, and hands the raw records on' {
        $script:UserRecords = @(
            New-Record -Operation 'MailItemsAccessed' -AccessType 'Sync' -AccessTypeInProperties -SessionId 'S1'
            New-Record -Operation 'MailItemsAccessed' -AccessType 'Sync' -AccessTypeInProperties -SessionId 'S2'
            New-Record -Operation 'MailItemsAccessed' -AccessType 'Sync' -AccessTypeInProperties -SessionId 'S1'
        )
        $Result = Get-CIPPBecMailActivity -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -StartDate '2026-08-14' -EndDate '2026-08-21' -Heuristics $script:Heuristics -Anchor 'victim@contoso.com'
        $Result.Data[0].MailAccessType | Should -Be 'Sync'
        @($Result.Data[0].SessionIds | Sort-Object) | Should -Be @('S1', 'S2')
        $Result.Records.Count | Should -Be 3 -Because 'the attacker-activity pass reads item detail from the same search'
    }
}
