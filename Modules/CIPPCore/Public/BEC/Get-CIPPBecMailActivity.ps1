function Get-CIPPBecMailActivity {
    <#
    .SYNOPSIS
        Counts the investigated user's mailbox activity from the unified audit log, bucketed by client IP and application.
    .DESCRIPTION
        Answers "what did they read, delete and send, and from where" without storing a single item:
        MailItemsAccessed, HardDelete, SoftDelete, MoveToDeletedItems and Send records attributed to the
        user, plus tenant-wide SendAs/SendOnBehalf records whose mailbox owner is the user, are reduced
        to counts per Operation x ClientIP x client application x access type with first/last seen
        times. Aggregated MailItemsAccessed records contribute their OperationCount. No subjects,
        folders or item ids are kept in the counts. MailItemsAccessed is part of Audit (Standard) for
        E3/E5 licences; when the log does not carry it the other operations still count. Each row also
        lists the mailbox SessionIds it saw (one session moving between addresses is one actor), and
        the raw records ride along on the result (Records, not stored) so the attacker-activity pass
        can take item-level detail for the attacker's addresses without searching again.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserPrincipalName
        The investigated user.
    .PARAMETER StartDate
        Window start (UTC).
    .PARAMETER EndDate
        Window end (UTC).
    .PARAMETER Heuristics
        The BEC heuristics object (mailActivity section, caps).
    .PARAMETER Anchor
        Anchor mailbox for the EXO requests.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$UserPrincipalName,
        [Parameter(Mandatory = $true)][datetime]$StartDate,
        [Parameter(Mandatory = $true)][datetime]$EndDate,
        [Parameter(Mandatory = $true)]$Heuristics,
        [string]$Anchor
    )

    $UserOps = @($Heuristics.mailActivity.userOperations)
    $OwnerOps = @($Heuristics.mailActivity.mailboxOwnerOperations)
    $MaxPages = [int]($Heuristics.caps.mailActivityPages ?? 10)
    $HardDeleteThreshold = [int]($Heuristics.mailActivity.hardDeleteThreshold ?? 20)

    $Groups = @{}
    $AllRecords = [System.Collections.Generic.List[object]]::new()
    $Errors = [System.Collections.Generic.List[string]]::new()
    $Complete = $true
    $Cap = $null
    $RecordCount = 0

    $Accumulate = {
        param($Record)
        $AD = $Record.AuditData
        if (-not $AD) { return }
        $Operation = [string]($AD.Operation ?? $Record.Operation)
        $ClientIP = [string](ConvertTo-CIPPBecHostAddress -Address ($AD.ClientIP ?? $AD.ClientIPAddress))
        $ClientInfo = [string]($AD.ClientInfoString ?? $AD.ClientAppId ?? $AD.ClientApplication)
        if ($ClientInfo.Length -gt 120) { $ClientInfo = $ClientInfo.Substring(0, 120) + '...' }
        # real records carry the access type in OperationProperties; older payloads had it at the top
        $AccessType = [string]($AD.MailAccessType ?? (@($AD.OperationProperties) | Where-Object { $_.Name -eq 'MailAccessType' } | Select-Object -First 1).Value)
        $Actor = [string]$AD.UserId
        $Owner = [string]($AD.MailboxOwnerUPN ?? $Actor)
        $Key = "$Operation|$ClientIP|$ClientInfo|$AccessType|$Actor|$Owner"
        $Count = if ($AD.OperationCount) { [int]$AD.OperationCount } else { 1 }
        $When = try { ([datetime]$AD.CreationTime).ToUniversalTime() } catch { $null }
        if (-not $Groups.ContainsKey($Key)) {
            $Groups[$Key] = [pscustomobject]@{
                Operation        = $Operation
                ClientIP         = $ClientIP
                ClientInfoString = $ClientInfo
                MailAccessType   = $AccessType
                LogonType        = $AD.LogonType
                Actor            = $Actor
                MailboxOwner     = $Owner
                Count            = 0
                Records          = 0
                FirstSeen        = $When
                LastSeen         = $When
                SessionIds       = [System.Collections.Generic.HashSet[string]]::new()
            }
        }
        $Group = $Groups[$Key]
        if ($AD.SessionId) { $null = $Group.SessionIds.Add([string]$AD.SessionId) }
        $AllRecords.Add($Record)
        $Group.Count = $Group.Count + $Count
        $Group.Records = $Group.Records + 1
        if ($When) {
            if (-not $Group.FirstSeen -or $When -lt $Group.FirstSeen) { $Group.FirstSeen = $When }
            if (-not $Group.LastSeen -or $When -gt $Group.LastSeen) { $Group.LastSeen = $When }
        }
    }

    if ($UserOps.Count -gt 0) {
        try {
            $Search = Search-CIPPBecAuditLog -TenantFilter $TenantFilter -StartDate $StartDate -EndDate $EndDate -Operations $UserOps -UserIds @($UserPrincipalName) -Anchor $Anchor -MaxPages $MaxPages
            foreach ($Record in $Search.Records) { & $Accumulate $Record; $RecordCount++ }
            if (-not $Search.Complete) { $Complete = $false; $Cap = $Search.Cap }
        } catch {
            $Errors.Add("user activity search: $((Get-NormalizedError -message $_.Exception.Message))")
        }
    }
    if ($OwnerOps.Count -gt 0) {
        try {
            $Search = Search-CIPPBecAuditLog -TenantFilter $TenantFilter -StartDate $StartDate -EndDate $EndDate -Operations $OwnerOps -Anchor $Anchor -MaxPages $MaxPages
            foreach ($Record in $Search.Records) {
                $AD = $Record.AuditData
                if (-not $AD) { continue }
                if ($AD.MailboxOwnerUPN -ne $UserPrincipalName -and $AD.UserId -ne $UserPrincipalName) { continue }
                & $Accumulate $Record
                $RecordCount++
            }
            if (-not $Search.Complete) { $Complete = $false; $Cap = $Search.Cap }
        } catch {
            $Errors.Add("send-as search: $((Get-NormalizedError -message $_.Exception.Message))")
        }
    }

    $Rows = @($Groups.Values | ForEach-Object {
            $_.FirstSeen = if ($_.FirstSeen) { $_.FirstSeen.ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
            $_.LastSeen = if ($_.LastSeen) { $_.LastSeen.ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
            $_.SessionIds = @($_.SessionIds)
            $_
        } | Sort-Object -Property Count -Descending)

    $ByOperation = @{}
    foreach ($Row in $Rows) { $ByOperation[$Row.Operation] = [int]($ByOperation[$Row.Operation] ?? 0) + $Row.Count }
    $Summary = [pscustomobject]@{
        Records                = $RecordCount
        ByOperation            = [pscustomobject]$ByOperation
        MailItemsAccessedCount = [int]($ByOperation['MailItemsAccessed'] ?? 0)
        HardDeleteCount        = [int]($ByOperation['HardDelete'] ?? 0)
        SoftDeleteCount        = [int]($ByOperation['SoftDelete'] ?? 0)
        SendCount              = [int]($ByOperation['Send'] ?? 0)
        HardDeleteThreshold    = $HardDeleteThreshold
        HardDeleteExceeded     = ([int]($ByOperation['HardDelete'] ?? 0) -ge $HardDeleteThreshold)
        DistinctClientIPs      = @($Rows.ClientIP | Where-Object { $_ } | Select-Object -Unique).Count
        SendAsByOthersCount    = [int](@($Rows | Where-Object { $_.Operation -in $OwnerOps -and $_.MailboxOwner -eq $UserPrincipalName -and $_.Actor -ne $UserPrincipalName } | Measure-Object -Property Count -Sum).Sum)
    }

    $Result = New-CIPPBecCollectorResult -Data $Rows -Complete ($Complete -and $Errors.Count -eq 0) -Cap $Cap -Error ($(if ($Errors.Count -gt 0) { $Errors -join '; ' } else { $null })) -Count $Rows.Count
    $Result | Add-Member -NotePropertyName 'Summary' -NotePropertyValue $Summary -Force
    $Result | Add-Member -NotePropertyName 'Records' -NotePropertyValue $AllRecords.ToArray() -Force
    return $Result
}
