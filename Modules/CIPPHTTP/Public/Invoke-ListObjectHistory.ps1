function Invoke-ListObjectHistory {
    <#
    .SYNOPSIS
        In progress concept - Rvd
        Returns a transformed timeline of audit events for any tenant object over a configurable period.

    .DESCRIPTION
        Aggregates change history from Graph directoryAudits and (for Exchange objects) the Unified Audit Log.
        Returns a normalised timeline array with parsed property changes, actor details, and source metadata.
        Supports users, groups, applications, service principals, devices, administrative units,
        conditional access policies, shared mailboxes, distribution lists, and mail contacts.

    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.AuditLog.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $ObjectId = $Request.Query.objectId ?? $Request.Query.id ?? $Request.Body.objectId ?? $Request.Body.id
    $ObjectType = $Request.Query.objectType ?? $Request.Body.objectType
    $Days = try { [int]($Request.Query.days ?? $Request.Body.days ?? 30) } catch { 30 }

    #region Validation
    if (-not $ObjectId) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{ Results = 'Error: objectId is required' }
        }
    }

    try {
        $ObjectId = ConvertTo-CIPPODataFilterValue -Value $ObjectId -Type Guid
    } catch {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{ Results = 'Error: objectId must be a valid GUID' }
        }
    }

    if (-not $TenantFilter) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{ Results = 'Error: tenantFilter is required' }
        }
    }

    if ($Days -lt 1) { $Days = 1 }
    if ($Days -gt 90) { $Days = 90 }
    #endregion

    $StartTime = (Get-Date).AddDays(-$Days).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $TypeKey = ($ObjectType ?? '').Trim().ToLowerInvariant()
    $Warnings = [System.Collections.Generic.List[string]]::new()
    $Sources = [System.Collections.Generic.List[string]]::new()

    #region Resolve object and classify source lanes
    $ResolveUri = if ($TypeKey -eq 'conditionalaccesspolicy') {
        "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$ObjectId"
    } else {
        "https://graph.microsoft.com/v1.0/directoryObjects/$ObjectId"
    }

    $ResolvedObject = $null
    $ResolvedAs = $null
    $ResolvedDisplayName = $null
    try {
        $ResolvedObject = New-GraphGetRequest -uri $ResolveUri -tenantid $TenantFilter -ErrorAction Stop
        $ODataType = $ResolvedObject.'@odata.type' -replace '^#microsoft\.graph\.', ''
        $ResolvedAs = if ($TypeKey -eq 'conditionalaccesspolicy') { 'conditionalAccessPolicy' } else { $ODataType ?? 'directoryObject' }
        $ResolvedDisplayName = $ResolvedObject.displayName ?? $ResolvedObject.userPrincipalName ?? $ResolvedObject.appId ?? $ObjectId
    } catch {
        $ResolvedAs = if ($TypeKey) { $TypeKey } else { 'directoryObject' }
        $ResolvedDisplayName = $ObjectId
    }

    # Classify which audit sources to query based on resolved type
    $ExchangeOnlyTypes = @('mailbox', 'sharedmailbox', 'distributionlist', 'mailcontact', 'resource', 'roommailbox', 'equipmentmailbox')
    $EntraOnlyTypes = @('application', 'serviceprincipal', 'device', 'administrativeunit', 'conditionalaccesspolicy')

    $QueryDirectoryAudits = $true
    $QueryExchangeAudit = $false
    $ExchangeAnchor = $null

    if ($TypeKey -in $ExchangeOnlyTypes) {
        # Caller explicitly said this is an Exchange object — skip Graph, go Exchange only
        $QueryDirectoryAudits = $false
        $QueryExchangeAudit = $true
        $ExchangeAnchor = $ResolvedObject.userPrincipalName ?? $ResolvedObject.mail
    } elseif ($TypeKey -in $EntraOnlyTypes) {
        # Pure Entra object — Graph directoryAudits only
        $QueryDirectoryAudits = $true
        $QueryExchangeAudit = $false
    } elseif ($ResolvedObject.mail -and $ResolvedAs -in @('user', 'group')) {
        # Mail-enabled user or group — query both
        $QueryDirectoryAudits = $true
        $QueryExchangeAudit = $true
        $ExchangeAnchor = $ResolvedObject.userPrincipalName ?? $ResolvedObject.mail
    }
    # else: unknown type or resolution failed — default is Graph directoryAudits only
    #endregion

    #region Helper: parse modifiedProperties
    $ParseModifiedProperties = {
        param([array]$Properties)
        foreach ($Prop in $Properties) {
            $OldVal = $null
            $NewVal = $null
            if ($Prop.oldValue -and $Prop.oldValue -ne '[]' -and $Prop.oldValue -ne 'null') {
                $OldVal = try { $Prop.oldValue | ConvertFrom-Json -ErrorAction Stop } catch { $Prop.oldValue }
            }
            if ($Prop.newValue -and $Prop.newValue -ne '[]' -and $Prop.newValue -ne 'null') {
                $NewVal = try { $Prop.newValue | ConvertFrom-Json -ErrorAction Stop } catch { $Prop.newValue }
            }
            if ($null -ne $OldVal -or $null -ne $NewVal) {
                [PSCustomObject]@{
                    property = $Prop.displayName
                    oldValue = $OldVal
                    newValue = $NewVal
                }
            }
        }
    }
    #endregion

    #region Helper: normalize initiatedBy
    $NormalizeActor = {
        param($InitiatedBy)
        if ($InitiatedBy.user) {
            [PSCustomObject]@{
                displayName = $InitiatedBy.user.displayName ?? $InitiatedBy.user.userPrincipalName
                id          = $InitiatedBy.user.id
                upn         = $InitiatedBy.user.userPrincipalName
                type        = 'user'
            }
        } elseif ($InitiatedBy.app) {
            [PSCustomObject]@{
                displayName = $InitiatedBy.app.displayName
                id          = $InitiatedBy.app.servicePrincipalId ?? $InitiatedBy.app.appId
                upn         = $null
                type        = 'app'
            }
        } else {
            [PSCustomObject]@{
                displayName = 'Unknown'
                id          = $null
                upn         = $null
                type        = 'unknown'
            }
        }
    }
    #endregion

    #region Query Graph directoryAudits
    [array]$DirectoryTimeline = @()
    if ($QueryDirectoryAudits) {
        try {
            $Filter = "activityDateTime ge $StartTime and targetResources/any(s:s/id eq '$ObjectId')"
            $Uri = "https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?`$filter=$Filter&`$orderby=activityDateTime desc"

            Write-LogMessage -API $APIName -message "Object history: querying directoryAudits for $ObjectId (last $Days days)" -Sev 'Debug' -tenant $TenantFilter

            [array]$RawAudits = New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -ComplexFilter -ErrorAction Stop

            [array]$DirectoryTimeline = @(foreach ($Event in $RawAudits) {
                $TargetResource = $Event.targetResources | Where-Object { $_.id -eq $ObjectId } | Select-Object -First 1
                $TargetResource = $TargetResource ?? ($Event.targetResources | Select-Object -First 1)

                [PSCustomObject]@{
                    id            = $Event.id
                    timestamp     = $Event.activityDateTime
                    activity      = $Event.activityDisplayName
                    category      = $Event.category
                    operationType = $Event.operationType
                    result        = $Event.result
                    actor         = & $NormalizeActor $Event.initiatedBy
                    target        = $TargetResource.displayName ?? $TargetResource.userPrincipalName ?? $ObjectId
                    changes       = @(& $ParseModifiedProperties ($TargetResource.modifiedProperties ?? @()))
                    source        = 'directoryAudit'
                }
            })
            [void]$Sources.Add('directoryAudit')
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API $APIName -tenant $TenantFilter -message "Object history: directoryAudits failed - $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            [void]$Warnings.Add("Directory audit query failed: $($ErrorMessage.NormalizedError)")
        }
    }
    #endregion

    #region Query Exchange Unified Audit Log
    [array]$ExchangeTimeline = @()
    if ($QueryExchangeAudit) {
        if ($ExchangeAnchor) {
            try {
                $SessionId = "ObjectHistory_$(Get-Random -Minimum 10000 -Maximum 99999)"
                $SearchParam = @{
                    SessionCommand = 'ReturnLargeSet'
                    ObjectIds      = @($ExchangeAnchor)
                    SessionId      = $SessionId
                    StartDate      = (Get-Date).AddDays(-$Days)
                    EndDate        = (Get-Date)
                    ResultSize     = 5000
                }

                $ExchangeLogs = [System.Collections.Generic.List[object]]::new()
                $MaxPages = 10
                $Page = 0
                do {
                    $Batch = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Search-UnifiedAuditLog' -cmdParams $SearchParam -Anchor $ExchangeAnchor)
                    foreach ($Item in $Batch) { [void]$ExchangeLogs.Add($Item) }
                    $Page++
                } while ($Batch.Count -eq 5000 -and $Page -lt $MaxPages)

                [array]$ExchangeTimeline = @(foreach ($Log in $ExchangeLogs) {
                    $AuditData = try { $Log.AuditData | ConvertFrom-Json -ErrorAction Stop } catch { $null }
                    if (-not $AuditData) { continue }

                    [PSCustomObject]@{
                        id            = $AuditData.Id ?? $Log.Identity
                        timestamp     = $Log.CreationDate ?? $AuditData.CreationTime
                        activity      = $AuditData.Operation
                        category      = 'ExchangeItem'
                        operationType = $AuditData.Operation
                        result        = if ($AuditData.ResultStatus -eq 'Succeeded' -or $AuditData.ResultStatus -eq 'True') { 'success' } else { $AuditData.ResultStatus ?? 'success' }
                        actor         = [PSCustomObject]@{
                            displayName = $AuditData.UserId
                            id          = $AuditData.UserId
                            upn         = $AuditData.UserId
                            type        = 'user'
                        }
                        target        = $AuditData.ObjectId ?? $ExchangeAnchor
                        changes       = @(
                            if ($AuditData.Parameters) {
                                foreach ($Param in $AuditData.Parameters) {
                                    [PSCustomObject]@{
                                        property = $Param.Name
                                        oldValue = $null
                                        newValue = $Param.Value
                                    }
                                }
                            }
                        )
                        source        = 'exchangeAudit'
                    }
                })
                [void]$Sources.Add('exchangeAudit')
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API $APIName -tenant $TenantFilter -message "Object history: Exchange UAL failed - $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
                [void]$Warnings.Add("Exchange audit query failed: $($ErrorMessage.NormalizedError)")
            }
        } else {
            [void]$Warnings.Add('Exchange audit skipped: could not determine mailbox anchor (UPN/mail)')
        }
    }
    #endregion

    #region Merge and sort timeline
    $Timeline = @($DirectoryTimeline + $ExchangeTimeline | Where-Object { $_ } | Sort-Object -Property timestamp -Descending)
    #endregion

    $Body = [PSCustomObject]@{
        objectId            = $ObjectId
        objectType          = $ObjectType
        resolvedObject      = $ResolvedObject
        resolvedAs          = $ResolvedAs
        resolvedDisplayName = $ResolvedDisplayName
        days                = $Days
        activityFromUtc     = $StartTime
        totalEvents         = $Timeline.Count
        sources             = @($Sources)
        warnings            = @($Warnings)
        timeline            = @($Timeline)
    }

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    }
}
