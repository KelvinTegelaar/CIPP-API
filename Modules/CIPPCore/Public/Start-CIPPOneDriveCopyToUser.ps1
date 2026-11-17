function Start-CIPPOneDriveCopyToUser {
    <#
    .SYNOPSIS
        Copies a leaver's OneDrive root contents into a folder named after the leaver's UPN in each recipient's OneDrive.
    .DESCRIPTION
        Every check runs before anything is written; any refusal throws ArgumentException naming every problem.
        Root items are submitted to SharePoint CreateCopyJobs (KeepBoth) and polled by Update-CIPPOneDriveCopyToUserStatus.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        # UPN or object id of the user whose OneDrive is copied.
        [Parameter(Mandatory = $true)]
        [string]$Leaver,

        # UPNs or object ids of the users who receive the copy.
        [Parameter(Mandatory = $true)]
        [string[]]$Recipients,

        # Off by default: version history can use many times the space the quota check counts.
        [bool]$IncludeVersionHistory = $false,

        [string]$StartedBy,

        # Lets the offboarding job name the operation up front so its licence step waits for exactly this copy.
        [string]$OperationId,

        # Graph can read a just-blocked account as enabled for a short while; re-read it before refusing.
        [switch]$WaitForSignInBlock,

        [int[]]$SignInBlockRetrySeconds = @(5, 10, 15, 15),

        $Headers,
        $APIName = 'OneDrive Copy To User'
    )

    $TableName = 'OneDriveCopyToUser'
    $MaxRecipients = 10
    $MaxRootItems = 1000
    $MaxSourceItems = 100000
    $DeltaPageSize = 999
    $MaxDeltaPages = 1000
    $JobsPerRequest = 100
    $KeepBoth = 2
    $PerJobByteLimit = 100GB

    if ($OperationId -and $OperationId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
        throw [System.ArgumentException]::new('OperationId is not a valid operation id.')
    }
    if (-not $StartedBy) {
        $Principal = try { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json } catch { $null }
        $StartedBy = $Principal.userDetails ?? $Headers.'x-ms-client-principal-name' ?? 'CIPP'
    }
    $PartitionKey = Get-CIPPOneDriveCopyTenantKey -TenantFilter $TenantFilter
    if ($OperationId) {
        $IdTable = Get-CIPPTable -TableName $TableName
        $SafeKey = $PartitionKey -replace "'", "''"
        if (@(Get-CIPPAzDataTableEntity @IdTable -Filter "PartitionKey eq '$SafeKey' and RowKey eq '$OperationId'").Count -gt 0) {
            throw [System.ArgumentException]::new("OneDrive copy $OperationId already exists; it was not started again.")
        }
    }

    $RecipientIds = @($Recipients | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } |
            Sort-Object -Unique)
    if ($RecipientIds.Count -eq 0) {
        throw [System.ArgumentException]::new('At least one recipient is required.')
    }
    if ($RecipientIds.Count -gt $MaxRecipients) {
        throw [System.ArgumentException]::new("At most $MaxRecipients recipients can receive one copy.")
    }

    $Source = Get-CIPPOneDriveCopyUser -TenantFilter $TenantFilter -UserId $Leaver -Kind Leaver
    $FolderName = $Source.UserPrincipalName
    if ($WaitForSignInBlock) {
        foreach ($Delay in $SignInBlockRetrySeconds) {
            if ($Source.AccountEnabled -eq $false) { break }
            Write-Information "OneDrive copy: $($Source.UserPrincipalName) still reads as able to sign in; checking again in $Delay s"
            Start-Sleep -Seconds $Delay
            $Recheck = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($Source.UserId)?`$select=id,accountEnabled" -tenantid $TenantFilter -asapp $true
            $Source.AccountEnabled = $Recheck.accountEnabled
        }
    }
    # A leaver who can still sign in could keep changing the files while they are copied.
    if ($Source.AccountEnabled -ne $false) {
        throw [System.ArgumentException]::new("Leaver $($Source.UserPrincipalName) can still sign in. Block sign-in for the account first, then start the copy.")
    }

    $Children = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/drives/$($Source.DriveId)/root/children?`$select=id,name,size,folder,file,package&`$top=999" -tenantid $TenantFilter -asapp $true)
    $RootItems = @($Children | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.name) -and ($_.folder -or $_.file -or $_.package) })
    if ($RootItems.Count -eq 0) {
        throw [System.ArgumentException]::new("Leaver $($Source.UserPrincipalName)'s OneDrive has nothing to copy.")
    }
    if ($RootItems.Count -gt $MaxRootItems) {
        throw [System.ArgumentException]::new("Leaver $($Source.UserPrincipalName)'s OneDrive has $($RootItems.Count) items at its root (limit $MaxRootItems). Group files into folders and try again.")
    }

    # Graph's folder sizes lag recent uploads, so every file is counted from delta instead.
    $SourceFileCount = [int64]0
    $SourceBytes = [int64]0
    $SourceItemCount = [int64]0
    $Pages = 0
    $NextUri = "https://graph.microsoft.com/v1.0/drives/$($Source.DriveId)/root/delta?`$select=id,name,size,file,folder,package,deleted,root&`$top=$DeltaPageSize"
    while ($NextUri) {
        if (++$Pages -gt $MaxDeltaPages) {
            throw "Enumerating $($Source.UserPrincipalName)'s OneDrive did not finish after $MaxDeltaPages pages."
        }
        $Page = New-GraphGetRequest -uri $NextUri -tenantid $TenantFilter -asapp $true -noPagination $true -SkipValueExtraction
        foreach ($Item in @($Page.value)) {
            if ($null -eq $Item -or $Item.deleted -or $Item.root) { continue }
            $SourceItemCount++
            if ($Item.file) {
                $SourceFileCount++
                $SourceBytes = $SourceBytes + [int64]($Item.size ?? 0)
            }
        }
        if ($SourceItemCount -gt $MaxSourceItems) {
            throw [System.ArgumentException]::new("Leaver $($Source.UserPrincipalName)'s OneDrive has more than $MaxSourceItems files and folders (limit $MaxSourceItems). It is too large to copy this way.")
        }
        $NextUri = [string]$Page.'@odata.nextLink'
    }

    $Warnings = [System.Collections.Generic.List[string]]::new()
    $Oversized = @($RootItems | Where-Object { [int64]($_.size ?? 0) -gt $PerJobByteLimit })
    if ($Oversized.Count -gt 0) {
        $Warnings.Add("$($Oversized.Count) root item(s) are larger than 100 GB, SharePoint's limit for one copy job. Those items are likely to fail; split them into smaller folders and copy again.")
    }

    $Targets = [System.Collections.Generic.List[object]]::new()
    $Problems = [System.Collections.Generic.List[string]]::new()
    foreach ($RecipientId in $RecipientIds) {
        try {
            $Target = Get-CIPPOneDriveCopyUser -TenantFilter $TenantFilter -UserId $RecipientId -Kind Recipient
        } catch [System.ArgumentException] {
            $Problems.Add($_.Exception.Message)
            continue
        }
        if ($Target.UserId -eq $Source.UserId) {
            $Problems.Add("Recipient $($Target.UserPrincipalName) is the leaver.")
            continue
        }
        if ($Targets.Where({ $_.UserId -eq $Target.UserId }, 'First').Count -gt 0) { continue }
        if ($Target.DriveHost -ne $Source.DriveHost) {
            $Problems.Add("Recipient $($Target.UserPrincipalName)'s OneDrive is not in the same tenant as the leaver's.")
            continue
        }
        if ($null -ne $Target.QuotaRemaining -and $Target.QuotaRemaining -lt $SourceBytes) {
            $Problems.Add("Recipient $($Target.UserPrincipalName) does not have enough space: the copy needs $SourceBytes bytes and $($Target.QuotaRemaining) are free.")
            continue
        }
        if ($null -eq $Target.QuotaRemaining) {
            $Warnings.Add("Free space in $($Target.UserPrincipalName)'s OneDrive could not be read, so it was not checked.")
        }
        $Targets.Add($Target)
    }
    # Checked for every recipient before any folder is created, so a later clash leaves no empty folders behind.
    foreach ($Target in $Targets) {
        $Existing = $null
        try {
            $Existing = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/drives/$($Target.DriveId)/root:/$([System.Uri]::EscapeDataString($FolderName))?`$select=id,name,folder,file,package" -tenantid $TenantFilter -asapp $true
        } catch {
            if ($_.Exception.Message -notmatch 'itemNotFound|ResourceNotFound|not found|could not be found|does not exist|404') { throw }
        }
        if ($Existing.id -and -not $Existing.folder) {
            $Problems.Add("Recipient $($Target.UserPrincipalName) already has a file named $FolderName at the root of their OneDrive. Rename it and try again.")
        }
    }
    if ($Problems.Count -gt 0) {
        throw [System.ArgumentException]::new("OneDrive copy not started. $($Problems -join ' ')")
    }

    # Graph's webUrl for an Office file can be a _layouts/Doc.aspx link, so build the path from the library URL.
    $SourceUris = @($RootItems | ForEach-Object {
            "$($Source.DriveWebUrl)/$([System.Uri]::EscapeDataString([string]$_.name))"
        })

    $FolderCreated = @{}
    foreach ($Target in $Targets) {
        $Folder = $null
        $Created = $false
        $FolderPath = "https://graph.microsoft.com/v1.0/drives/$($Target.DriveId)/root:/$([System.Uri]::EscapeDataString($FolderName))"
        try {
            $Body = ConvertTo-Json -Compress -InputObject @{
                name                                = $FolderName
                folder                              = @{}
                '@microsoft.graph.conflictBehavior' = 'fail'
            }
            $Folder = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/drives/$($Target.DriveId)/root/children" -tenantid $TenantFilter -type POST -body $Body -AsApp $true
            $Created = $true
        } catch {
            $CreateError = $_
            if ($CreateError.Exception.Message -notmatch 'nameAlreadyExists|already exists|conflict|409') { throw }
            $Folder = New-GraphGetRequest -uri "$FolderPath`?`$select=id,name,webUrl,folder,file" -tenantid $TenantFilter -asapp $true
        }
        if (-not $Folder.id) {
            throw "Could not create or find the folder $FolderName in $($Target.UserPrincipalName)'s OneDrive."
        }
        if (-not $Created -and -not $Folder.folder) {
            throw [System.ArgumentException]::new("Recipient $($Target.UserPrincipalName) already has a file named $FolderName at the root of their OneDrive. Rename it and try again.")
        }
        $FolderCreated[$Target.UserId] = $Created
    }

    if (-not $OperationId) { $OperationId = (New-Guid).Guid }
    $Expiry = ([DateTime]::UtcNow.AddDays(14)).ToString('o')
    $RecipientRecords = [System.Collections.Generic.List[object]]::new()
    $Index = 0
    foreach ($Target in $Targets) {
        $SubOperationId = "$OperationId-r$Index"
        $DestinationUri = "$($Target.DriveWebUrl)/$([System.Uri]::EscapeDataString($FolderName))"
        $Record = [ordered]@{
            Index             = $Index
            UserId            = $Target.UserId
            UserPrincipalName = $Target.UserPrincipalName
            FolderName        = $FolderName
            FolderCreated     = [bool]$FolderCreated[$Target.UserId]
            SubOperationId    = $SubOperationId
            JobCount          = 0
            StartError        = $null
        }
        try {
            $Jobs = [System.Collections.Generic.List[object]]::new()
            $BadBatches = [System.Collections.Generic.List[string]]::new()
            for ($i = 0; $i -lt $SourceUris.Count; $i += $JobsPerRequest) {
                $Batch = @($SourceUris[$i..([Math]::Min($i + $JobsPerRequest, $SourceUris.Count) - 1)])
                $BatchJobs = @(Invoke-CIPPSharePointCreateCopyJobs -TenantFilter $TenantFilter -SourceSiteUrl $Source.SiteUrl `
                        -ExportObjectUris $Batch -DestinationUri $DestinationUri -NameConflictBehavior $KeepBoth `
                        -SameWebCopyMoveOptimization $false -IgnoreVersionHistory (-not $IncludeVersionHistory) | Where-Object { $null -ne $_ })
                # SharePoint bundles a batch's items into 1..N jobs; anything else cannot be confirmed.
                if ($BatchJobs.Count -lt 1 -or $BatchJobs.Count -gt $Batch.Count) {
                    $BadBatches.Add("$($BatchJobs.Count) copy job(s) for $($Batch.Count) root item(s)")
                }
                foreach ($Job in $BatchJobs) { $Jobs.Add($Job) }
            }
            $Record.JobCount = $Jobs.Count
            if ($BadBatches.Count -gt 0) {
                $Record.StartError = "Copy failed to start: SharePoint returned $($BadBatches -join ', ')."
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -sev Error `
                    -message "OneDrive copy $OperationId for $($Target.UserPrincipalName): $($Record.StartError)"
            }
            Set-CIPPSharePointLibraryCopyOperation -TenantFilter $PartitionKey -OperationId $SubOperationId -TableName $TableName -Entity @{
                SourceSiteUrl     = $Source.SiteUrl
                SourceSiteName    = $Source.UserPrincipalName
                SourceLibraryName = 'OneDrive'
                DestSiteName      = $Target.UserPrincipalName
                DestLibraryName   = $FolderName
                StartedBy         = $StartedBy
                Status            = 'Processing'
                JobHandleCount    = $Jobs.Count
                Expiry            = $Expiry
                CopyJobInfos      = @($Jobs)
                HandleStates      = (ConvertTo-Json -InputObject @($Jobs | ForEach-Object { [PSCustomObject]@{ Status = 'Queued'; IsComplete = $false } }) -Compress -Depth 4)
            }
        } catch {
            $Detail = (Get-CippException -Exception $_).NormalizedError
            $Detail = [regex]::Replace([string]$Detail, 'https?://[^\s''"]+', '[url redacted]', 'IgnoreCase')
            $Record.StartError = "Copy failed to start: $Detail"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -sev Error `
                -message "OneDrive copy $OperationId could not start for $($Target.UserPrincipalName): $Detail" -LogData (Get-CippException -Exception $_)
        }
        $RecipientRecords.Add([PSCustomObject]$Record)
        $Index++
    }

    if ($RecipientRecords.Where({ -not $_.StartError }, 'First').Count -eq 0) {
        throw "OneDrive copy failed to start for every recipient. $(@($RecipientRecords | ForEach-Object { "$($_.UserPrincipalName): $($_.StartError)" }) -join ' ')"
    }

    $StartedAt = [DateTimeOffset]::UtcNow
    $StartedUtc = $StartedAt.UtcDateTime.ToString('o')
    $Table = Get-CIPPTable -TableName $TableName
    Add-CIPPAzDataTableEntity @Table -Force -Entity @{
        PartitionKey          = $PartitionKey
        RowKey                = $OperationId
        Kind                  = 'Operation'
        LeaverId              = $Source.UserId
        LeaverUPN             = $Source.UserPrincipalName
        StartedBy             = [string]$StartedBy
        StartedUtc            = $StartedUtc
        StartedUnix           = [int64]$StartedAt.ToUnixTimeSeconds()
        RootItemCount         = $RootItems.Count
        SourceFileCount       = $SourceFileCount
        SourceBytes           = $SourceBytes
        ExpectedBytes         = $SourceBytes
        IncludeVersionHistory = $IncludeVersionHistory
        Expiry                = $Expiry
        Recipients            = (ConvertTo-Json -InputObject @($RecipientRecords) -Compress -Depth 4)
    }

    $Names = ($RecipientRecords | ForEach-Object { $_.UserPrincipalName }) -join ', '
    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -sev Info `
        -message "OneDrive copy $OperationId started by $StartedBy`: $($Source.UserPrincipalName) to $Names (folder $FolderName, $($RootItems.Count) root items, $SourceFileCount files, $SourceBytes bytes)"

    [PSCustomObject]@{
        OperationId     = $OperationId
        Leaver          = $Source.UserPrincipalName
        FolderName      = $FolderName
        RootItemCount   = $RootItems.Count
        SourceFileCount = $SourceFileCount
        SourceBytes     = $SourceBytes
        ExpectedBytes   = $SourceBytes
        StartedBy       = [string]$StartedBy
        StartedUtc      = $StartedUtc
        Recipients      = @($RecipientRecords | ForEach-Object {
                [PSCustomObject]@{
                    UserPrincipalName = $_.UserPrincipalName
                    FolderCreated     = $_.FolderCreated
                    State             = if ($_.StartError) { 'Failed' } else { 'Queued' }
                    JobCount          = $_.JobCount
                    Message           = if ($_.StartError) { $_.StartError } else { 'Copy queued.' }
                }
            })
        Warnings        = @($Warnings)
        Message         = 'OneDrive copy started. Poll ListOneDriveCopyToUser with the OperationId until State is Completed before removing licences.'
    }
}
