function Push-DBCacheOneDriveLongPaths {
    <#
    .SYNOPSIS
        Full-recount OneDrive path-length counts for one personal site (resumable).

    .DESCRIPTION
        Walks the site default drive via Graph root/delta (no item webUrl). Measures decoded
        cloud path length and inferred Windows sync full-path length in memory, increments
        counts, discards path strings. Writes one anonymized OneDriveLongPaths row:
        ownerPrincipalName, countOver260, countOver400.

        Checkpoints CurrentUri + running counts for timebox/throttle requeue. Does not use
        deltaLink incremental count math — each run recounts from scratch (resume continues
        the same full walk).

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = [string]$Item.TenantFilter
    $SiteId = [string]$Item.SiteId
    $OwnerPrincipalName = [string]($Item.OwnerPrincipalName ?? '')
    $ScanId = [string]$Item.ScanId
    $RequeueCount = [int]($Item.RequeueCount ?? 0)

    $CacheType = 'OneDriveLongPaths'
    $StateTable = Get-CippTable -tablename 'CippOneDriveLongPathsState'
    $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String

    # Superseded scan — overlapping ExecCIPPDBCache runs must not write.
    $CurrentScan = Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$SafeTenant' and RowKey eq 'scan'"
    if (-not $CurrentScan -or [string]$CurrentScan.ScanId -ne $ScanId) {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OneDrive long-paths: skipping superseded scan $ScanId" -sev Debug
        return @()
    }

    $SiteKeySegment = ($SiteId -replace '[/\\#?]', '_') -replace '[\u0000-\u001F\u007F-\u009F]', ''
    $CheckpointRowKey = "chk-$SiteKeySegment"

    $TimeboxSeconds = 540
    if ($env:CIPPNG -eq 'true') { $TimeboxSeconds = 1100 }
    if ($null -ne $env:CIPP_ONEDRIVE_LONGPATHS_TIMEBOX_SECONDS -and "$($env:CIPP_ONEDRIVE_LONGPATHS_TIMEBOX_SECONDS)" -ne '') {
        $Parsed = 0
        if ([int]::TryParse("$($env:CIPP_ONEDRIVE_LONGPATHS_TIMEBOX_SECONDS)", [ref]$Parsed) -and $Parsed -ge 0) {
            $TimeboxSeconds = $Parsed
        }
    }

    # Fixed length (C:\Users\ + \OneDrive - {org}\) computed once per tenant at fan-out; add UPN local-part after owner is known.
    $FixedLength = [int]($Item.InferredLocalRootFixedLength ?? 0)
    if ($FixedLength -le 0) {
        $OrgDisplayName = [string]($Item.OrgDisplayName ?? 'Organization')
        if ([string]::IsNullOrWhiteSpace($OrgDisplayName)) { $OrgDisplayName = 'Organization' }
        $FixedLength = ('C:\Users\').Length + ("\OneDrive - $OrgDisplayName\").Length
    }
    $Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    function Get-LongPathsCheckpoint {
        $Row = Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$SafeTenant' and RowKey eq '$CheckpointRowKey'"
        if (-not $Row -or [string]$Row.ScanId -ne $ScanId) { return $null }
        try { ($Row.StateJson | ConvertFrom-Json -ErrorAction Stop) } catch { $null }
    }

    function Save-LongPathsCheckpoint {
        param($State)
        Add-CIPPAzDataTableEntity @StateTable -Entity @{
            PartitionKey = $TenantFilter
            RowKey       = $CheckpointRowKey
            ScanId       = $ScanId
            StateJson    = [string]($State | ConvertTo-Json -Depth 5 -Compress)
        } -Force
    }

    function Remove-LongPathsCheckpoint {
        $Row = Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$SafeTenant' and RowKey eq '$CheckpointRowKey'"
        if ($Row) { Remove-CIPPAzDataTableEntity @StateTable -Entity $Row -Force }
    }

    function Invoke-LongPathsRequeue {
        param([int]$NextRequeueCount = $RequeueCount)
        $ResumeItem = [PSCustomObject]@{}
        foreach ($Property in $Item.PSObject.Properties) {
            $ResumeItem | Add-Member -NotePropertyName $Property.Name -NotePropertyValue $Property.Value -Force
        }
        $ResumeItem | Add-Member -NotePropertyName 'RequeueCount' -NotePropertyValue $NextRequeueCount -Force
        $null = Start-CIPPOrchestrator -InputObject ([PSCustomObject]@{
                Batch            = @($ResumeItem)
                OrchestratorName = "OneDriveLongPathsResume_$($TenantFilter)_$([guid]::NewGuid().ToString('N').Substring(0, 8))"
                SkipLog          = $true
            })
    }

    function Invoke-LongPathsTimeboxRequeue {
        param($State)
        if ($Stopwatch.Elapsed.TotalSeconds -lt $TimeboxSeconds) { return $false }
        Save-LongPathsCheckpoint -State $State
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OneDrive long-paths: timebox reached for $OwnerPrincipalName; requeueing" -sev Debug
        Invoke-LongPathsRequeue
        return $true
    }

    function Invoke-LongPathsThrottleRequeue {
        param([string]$ErrorMessage, $State)
        if ($ErrorMessage -notmatch 'throttl|too many requests|429') { return $false }
        if ($RequeueCount -ge 6) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OneDrive long-paths: still throttled after $RequeueCount resumes for $OwnerPrincipalName; giving up this scan" -sev Warning
            return $false
        }
        Save-LongPathsCheckpoint -State $State
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OneDrive long-paths: throttled for $OwnerPrincipalName; requeueing (attempt $($RequeueCount + 1))" -sev Info
        Invoke-LongPathsRequeue -NextRequeueCount ($RequeueCount + 1)
        return $true
    }

    try {
        $Drive = $null
        try {
            $Drive = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/$SiteId/drive?`$select=id,name,driveType,owner" -tenantid $TenantFilter -asapp $true
        } catch {
            if ($_.Exception.Message -match 'Access to this site has been blocked') {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'OneDrive long-paths: skipping locked OneDrive site' -sev Info
                return @()
            }
            throw
        }

        if (-not $Drive.id) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'OneDrive long-paths: no default drive for site' -sev Debug
            return @()
        }

        if ([string]::IsNullOrWhiteSpace($OwnerPrincipalName)) {
            $OwnerPrincipalName = [string]($Drive.owner.user.email ?? $Drive.owner.user.userPrincipalName ?? '')
        }
        if ([string]::IsNullOrWhiteSpace($OwnerPrincipalName)) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'OneDrive long-paths: skipping site with unresolved owner UPN' -sev Debug
            return @()
        }

        $LocalPart = $OwnerPrincipalName
        $At = $OwnerPrincipalName.IndexOf('@')
        if ($At -gt 0) { $LocalPart = $OwnerPrincipalName.Substring(0, $At) }
        $LocalRootLength = $FixedLength + $LocalPart.Length

        $DeltaSelect = 'id,name,parentReference,folder,file,deleted'
        $FullDeltaUri = "https://graph.microsoft.com/beta/drives/$($Drive.id)/root/delta?`$select=$DeltaSelect&`$top=999"

        $CountOver260 = 0
        $CountOver400 = 0
        $Uri = $FullDeltaUri

        $Checkpoint = Get-LongPathsCheckpoint
        if ($Checkpoint -and $Checkpoint.CurrentUri) {
            $Uri = [string]$Checkpoint.CurrentUri
            $CountOver260 = [int]($Checkpoint.CountOver260 ?? 0)
            $CountOver400 = [int]($Checkpoint.CountOver400 ?? 0)
        }

        while ($Uri) {
            try {
                $Page = New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -asapp $true -noPagination $true -SkipValueExtraction
            } catch {
                $ErrorMessage = $_.Exception.Message
                $State = @{
                    CurrentUri    = $Uri
                    CountOver260  = $CountOver260
                    CountOver400  = $CountOver400
                }
                if (Invoke-LongPathsThrottleRequeue -ErrorMessage $ErrorMessage -State $State) { return @() }
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OneDrive long-paths: delta failed for ${OwnerPrincipalName}: $ErrorMessage" -sev Warning
                return @()
            }

            $Values = @($Page.value)
            foreach ($PageItem in $Values) {
                if ($PageItem.deleted) { continue }
                if (-not $PageItem.file -and -not $PageItem.folder) { continue }

                $CloudLength = Get-CIPPDriveItemCloudPathLength -ParentPath ([string]$PageItem.parentReference.path) -Name ([string]$PageItem.name)
                if ($CloudLength -le 0) { continue }

                if ($CloudLength -gt 400) { $CountOver400++ }
                $InferredLocal = $LocalRootLength + $CloudLength
                if ($InferredLocal -gt 260) { $CountOver260++ }
            }

            $Next = $Page.'@odata.nextLink'
            $DeltaDone = $Page.'@odata.deltaLink'
            if ($Next) {
                $Uri = [string]$Next
            } elseif ($DeltaDone) {
                # Full recount complete — do not store deltaLink for incremental counts.
                $Uri = $null
            } else {
                $Uri = $null
            }

            if ($Uri) {
                $State = @{
                    CurrentUri   = $Uri
                    CountOver260 = $CountOver260
                    CountOver400 = $CountOver400
                }
                Save-LongPathsCheckpoint -State $State
                if (Invoke-LongPathsTimeboxRequeue -State $State) { return @() }
            }
        }

        $Row = [PSCustomObject]@{
            id                   = $OwnerPrincipalName
            ownerPrincipalName   = $OwnerPrincipalName
            countOver260         = [int]$CountOver260
            countOver400         = [int]$CountOver400
        }
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type $CacheType -Data @($Row) -Append -RunId $ScanId
        Remove-LongPathsCheckpoint
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OneDrive long-paths: cached counts for $OwnerPrincipalName (260=$CountOver260, 400=$CountOver400)" -sev Debug
        return @()
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OneDrive long-paths: site task failed: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        return @()
    }
}
