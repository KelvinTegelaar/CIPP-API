function New-CIPPBecRunRequest {
    <#
    .SYNOPSIS
        Prepares a BEC investigation: the history row, the live-progress job and the queue item.
    .DESCRIPTION
        Every way of starting a run (the user's page, the bulk action) goes through here so the run
        is visible the same way everywhere: a Waiting row in BecReports (the history), an
        async-deployment job keyed on the case id (the live progress the page polls; Queued until a
        worker picks it up) and the batch item to hand to Start-CIPPOrchestrator. Nothing is queued
        here; the caller queues one or many items. Every run is the full investigation.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserId
        Object id of the user to investigate.
    .PARAMETER UserPrincipalName
        UPN of the user (used by the run and as the progress row name).
    .PARAMETER DisplayName
        Display name for the history row.
    .PARAMETER RequestedBy
        Who asked for the run.
    .PARAMETER QueueId
        Optional CIPP queue entry id (bulk runs).
    .PARAMETER RequestedFromIP
        The requesting technician's address (first x-forwarded-for hop). The run treats it as the
        technician's, never the user's or the attacker's.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$UserId,
        [string]$UserPrincipalName,
        [string]$DisplayName,
        [string]$RequestedBy = 'CIPP',
        [string]$QueueId,
        [string]$RequestedFromIP
    )

    # The UPN drives every mailbox-scoped collector and the audit-record attribution in the run; a blank
    # one makes those throw "empty string" and the tenant-wide record filter match everything. Resolve it
    # from the object id when the caller didn't supply one (an API/MCP client, or a race on the page) so
    # the run, the history row and the progress name all carry a real user.
    if ([string]::IsNullOrWhiteSpace($UserPrincipalName)) {
        try {
            $Resolved = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserId)?`$select=userPrincipalName,displayName" -tenantid $TenantFilter -AsApp $true
            if (-not [string]::IsNullOrWhiteSpace($Resolved.userPrincipalName)) { $UserPrincipalName = [string]$Resolved.userPrincipalName }
            if ([string]::IsNullOrWhiteSpace($DisplayName) -and -not [string]::IsNullOrWhiteSpace($Resolved.displayName)) { $DisplayName = [string]$Resolved.displayName }
        } catch {
            Write-Information "BEC: could not resolve a UPN for $UserId in $TenantFilter`: $($_.Exception.Message)"
        }
    }

    $CaseId = New-CIPPBecCaseId
    $Name = if ([string]::IsNullOrWhiteSpace($UserPrincipalName)) { $UserId } else { $UserPrincipalName }
    if ($PSCmdlet.ShouldProcess("$Name in $TenantFilter", "Prepare BEC investigation $CaseId")) {
        $Properties = @{
            UserId            = $UserId
            UserPrincipalName = [string]$UserPrincipalName
            Status            = 'Waiting'
            RequestedBy       = $RequestedBy
            RequestedAt       = (Get-Date).ToUniversalTime().ToString('o')
        }
        if ($DisplayName) { $Properties.DisplayName = $DisplayName }
        if ($QueueId) { $Properties.QueueId = $QueueId }
        if ($RequestedFromIP) { $Properties.RequestedFromIP = $RequestedFromIP }
        $null = Set-CIPPBecReport -TenantFilter $TenantFilter -CaseId $CaseId -Replace -Properties $Properties
        # The progress job: every step pending, row status queued, until Push-BECRun takes over.
        $null = New-CIPPAsyncDeployment -JobId $CaseId -Names @($Name) -StepTitles @((Get-CIPPBecRunSteps).Title) -Source 'BEC' -TenantFilter $TenantFilter
    }

    $Item = @{
        FunctionName = 'BECRun'
        UserID       = $UserId
        TenantFilter = $TenantFilter
        userName     = [string]$UserPrincipalName
        CaseId       = $CaseId
    }
    if ($RequestedFromIP) { $Item.RequestedFromIP = $RequestedFromIP; $Item.RequestedBy = $RequestedBy }
    if ($QueueId) {
        $Item.QueueId = $QueueId
        $Item.QueueName = "BEC investigation $Name"
    }

    return [pscustomobject]@{
        CaseId = $CaseId
        Item   = $Item
    }
}
