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
        [string[]]$Recipients = @(),

        # A document library to copy into as well: site (URL), library (list id) and an optional folder in it.
        $Library,

        # Off by default: version history can use many times the space of the current versions.
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
    $LibrarySiteUrl = [string]($Library.site.value ?? $Library.site)
    $LibraryListId = [string]($Library.library.value ?? $Library.library)
    $LibraryFolder = ([string]$Library.folder).Trim().Trim('/')
    if ($RecipientIds.Count -eq 0 -and -not $LibraryListId) {
        throw [System.ArgumentException]::new('At least one recipient or a document library is required.')
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

    $Children = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/drives/$($Source.DriveId)/root/children?`$select=id,name,size,folder,file,package,specialFolder&`$top=999" -tenantid $TenantFilter -asapp $true)
    # Shortcuts only links other people's folders, so it is not the leaver's to copy.
    $RootItems = @($Children | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.name) -and ($_.folder -or $_.file -or $_.package) -and $_.specialFolder.name -ne 'shortcuts' })
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
    # Free space each destination needs. With version history that is the library's StorageMetrics
    # TotalSize (every version, not the recycle bin), which the delta file sizes do not include.
    $RequiredBytes = $SourceBytes
    if ($IncludeVersionHistory) {
        $TotalSize = $null
        if ($Source.ListId -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
            try {
                $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
                $Metrics = New-GraphGetRequest -uri "$($Source.SiteUrl)/_api/web/lists(guid'$($Source.ListId)')/RootFolder?`$select=StorageMetrics&`$expand=StorageMetrics" -tenantid $TenantFilter -scope "$($SharePointInfo.SharePointUrl)/.default" -extraHeaders @{ Accept = 'application/json;odata=nometadata' } -UseCertificate -AsApp $true
                $TotalSize = ConvertTo-SPOAdminListInt64 -Raw $Metrics.StorageMetrics.TotalSize
            } catch {
                Write-Information "OneDrive copy: could not read the storage metrics of $($Source.UserPrincipalName)'s OneDrive: $($_.Exception.Message)"
            }
        }
        if ($null -ne $TotalSize) {
            $RequiredBytes = [Math]::Max($SourceBytes, [int64]$TotalSize)
        } else {
            $Warnings.Add('The size of the version history could not be read, so free space was checked against current versions only.')
        }
    }
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
        if ($null -ne $Target.QuotaRemaining -and $Target.QuotaRemaining -lt $RequiredBytes) {
            $Problems.Add("Recipient $($Target.UserPrincipalName) does not have enough space: the copy needs $RequiredBytes bytes and $($Target.QuotaRemaining) are free.")
            continue
        }
        if ($null -eq $Target.QuotaRemaining) {
            $Warnings.Add("Free space in $($Target.UserPrincipalName)'s OneDrive could not be read, so it was not checked.")
        }
        $Targets.Add($Target)
    }
    if ($LibraryListId) {
        $SiteUri = $null
        $FolderSegments = @(if ($LibraryFolder) { $LibraryFolder -split '/' })
        if (-not [System.Uri]::TryCreate($LibrarySiteUrl, [System.UriKind]::Absolute, [ref]$SiteUri) -or $SiteUri.Scheme -ne 'https') {
            $Problems.Add("The document library's site '$LibrarySiteUrl' is not a SharePoint site URL.")
        } elseif ($LibraryListId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
            $Problems.Add("'$LibraryListId' is not a document library id.")
        } elseif ($FolderSegments.Where({ $_ -in @('', '.', '..') }, 'First').Count -gt 0) {
            $Problems.Add("'$LibraryFolder' is not a valid folder path.")
        } else {
            $SitePath = $SiteUri.AbsolutePath.TrimEnd('/')
            $SiteSegment = if ($SitePath) { "$($SiteUri.Host):$($SitePath):" } else { $SiteUri.Host }
            $EscapedFolder = ($FolderSegments | ForEach-Object { [System.Uri]::EscapeDataString($_) }) -join '/'
            $Drive = $null
            $Parent = $null
            try {
                $Drive = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/sites/$SiteSegment/lists/$LibraryListId/drive?`$select=id,name,webUrl,quota" -tenantid $TenantFilter -asapp $true
                $Parent = if ($EscapedFolder) { New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/drives/$($Drive.id)/root:/$EscapedFolder`?`$select=id,folder" -tenantid $TenantFilter -asapp $true }
            } catch {
                if ($_.Exception.Message -notmatch 'itemNotFound|ResourceNotFound|not found|could not be found|does not exist|404') { throw }
            }
            if (-not $Drive.id) {
                $Problems.Add("The document library was not found on $LibrarySiteUrl.")
            } elseif ($EscapedFolder -and -not $Parent.folder) {
                $Problems.Add("The folder '$LibraryFolder' was not found in the document library $([System.Uri]::UnescapeDataString([string]$Drive.webUrl)).")
            } else {
                $DriveWebUrl = ([string]$Drive.webUrl).TrimEnd('/')
                $Target = [PSCustomObject]@{
                    Kind              = 'Library'
                    UserId            = [string]$Drive.id
                    UserPrincipalName = [System.Uri]::UnescapeDataString((@($DriveWebUrl -replace '^https://', '') + @(if ($EscapedFolder) { $EscapedFolder }) -join '/'))
                    DriveId           = [string]$Drive.id
                    DriveWebUrl       = $DriveWebUrl
                    ParentPath        = $EscapedFolder
                    QuotaRemaining    = if ($null -ne $Drive.quota.remaining) { [int64]$Drive.quota.remaining } else { $null }
                }
                if ($null -ne $Target.QuotaRemaining -and $Target.QuotaRemaining -lt $RequiredBytes) {
                    $Problems.Add("The site holding $($Target.UserPrincipalName) does not have enough space: the copy needs $RequiredBytes bytes and $($Target.QuotaRemaining) are free.")
                } else {
                    if ($null -eq $Target.QuotaRemaining) { $Warnings.Add("Free space on the site holding $($Target.UserPrincipalName) could not be read, so it was not checked.") }
                    $Targets.Add($Target)
                }
            }
        }
    }
    # Checked for every recipient before any folder is created, so a later clash leaves no empty folders behind.
    foreach ($Target in $Targets) {
        $Existing = $null
        $ItemPath = (@(@($Target.ParentPath).Where({ $_ })) + [System.Uri]::EscapeDataString($FolderName)) -join '/'
        try {
            $Existing = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/drives/$($Target.DriveId)/root:/$ItemPath`?`$select=id,name,folder,file,package" -tenantid $TenantFilter -asapp $true
        } catch {
            if ($_.Exception.Message -notmatch 'itemNotFound|ResourceNotFound|not found|could not be found|does not exist|404') { throw }
        }
        if ($Existing.id -and -not $Existing.folder) {
            $Problems.Add("$($Target.UserPrincipalName) already has a file named $FolderName where the copy folder goes. Rename it and try again.")
        }
    }
    if ($Problems.Count -gt 0) {
        throw [System.ArgumentException]::new("OneDrive copy not started. $($Problems -join ' ')")
    }

    # Graph's webUrl for an Office file can be a _layouts/Doc.aspx link, so build the path from the library URL.
    $SourceUris = @($RootItems | ForEach-Object {
            "$($Source.DriveWebUrl)/$([System.Uri]::EscapeDataString([string]$_.name))"
        })

    $Prepared = @{}
    foreach ($Target in $Targets) {
        $Folder = $null
        $Created = $false
        $ParentPath = [string]$Target.ParentPath
        $ItemPath = (@(@($ParentPath).Where({ $_ })) + [System.Uri]::EscapeDataString($FolderName)) -join '/'
        $FolderPath = "https://graph.microsoft.com/v1.0/drives/$($Target.DriveId)/root:/$ItemPath"
        $ChildrenUri = if ($ParentPath) { "https://graph.microsoft.com/v1.0/drives/$($Target.DriveId)/root:/$($ParentPath):/children" } else { "https://graph.microsoft.com/v1.0/drives/$($Target.DriveId)/root/children" }
        try {
            $Body = ConvertTo-Json -Compress -InputObject @{
                name                                = $FolderName
                folder                              = @{}
                '@microsoft.graph.conflictBehavior' = 'fail'
            }
            $Folder = New-GraphPOSTRequest -uri $ChildrenUri -tenantid $TenantFilter -type POST -body $Body -AsApp $true
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
            throw [System.ArgumentException]::new("$($Target.UserPrincipalName) already has a file named $FolderName where the copy folder goes. Rename it and try again.")
        }
        $Prepared[$Target.UserId] = @{ Created = $Created; DestinationUri = "$($Target.DriveWebUrl)/$ItemPath" }
    }

    if (-not $OperationId) { $OperationId = [guid]::NewGuid().ToString() }
    $Expiry = ([DateTime]::UtcNow.AddDays(14)).ToString('o')
    $RecipientRecords = [System.Collections.Generic.List[object]]::new()
    $Index = 0
    foreach ($Target in $Targets) {
        $SubOperationId = "$OperationId-r$Index"
        $DestinationUri = $Prepared[$Target.UserId].DestinationUri
        $Record = [ordered]@{
            Index             = $Index
            UserId            = $Target.UserId
            UserPrincipalName = $Target.UserPrincipalName
            FolderName        = $FolderName
            FolderCreated     = [bool]$Prepared[$Target.UserId].Created
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
                HandleStates      = [CIPP.CippJson]::ToJson(@($Jobs | ForEach-Object { [PSCustomObject]@{ Status = 'Queued'; IsComplete = $false } }), 4)
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
    $Summary = @($RecipientRecords | ForEach-Object {
            [PSCustomObject]@{ UserPrincipalName = $_.UserPrincipalName; State = if ($_.StartError) { 'Failed' } else { 'Queued' }; Message = if ($_.StartError) { $_.StartError } else { 'Copy queued.' }; ItemsCopied = 0; BytesCopied = 0; JobsComplete = 0; JobsTotal = $_.JobCount }
        })
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
        ExpectedBytes         = $RequiredBytes
        IncludeVersionHistory = $IncludeVersionHistory
        Expiry                = $Expiry
        Recipients            = [CIPP.CippJson]::ToJson(@($RecipientRecords), 4) ?? [string](ConvertTo-Json -InputObject @($RecipientRecords) -Compress -Depth 4)
        State                 = 'Queued'
        RecipientSummary      = [CIPP.CippJson]::ToJson($Summary, 3) ?? (ConvertTo-Json -InputObject $Summary -Compress -Depth 3)
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
        ExpectedBytes   = $RequiredBytes
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
        Message         = "Started copying $($Source.UserPrincipalName)'s OneDrive into a $FolderName folder for $Names. Follow it on the OneDrive Copies page (ListOneDriveCopyToUser) and remove licences only once it is Completed."
    }
}
