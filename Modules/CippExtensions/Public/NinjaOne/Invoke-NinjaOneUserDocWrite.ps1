function Invoke-NinjaOneUserDocWrite {
    <#
    .FUNCTIONALITY
    Internal
    .SYNOPSIS
    Builds NinjaOne user documents from staged inputs and writes the changed ones, in waves of 100-document batches.
    .DESCRIPTION
    Each item carries the user's document inputs (the JSON the sync fingerprints) and the state of their map row.
    A document whose fields hash the same as the last write gets only its map row refreshed; the rest are created
    or patched with just their changed fields. After a wave in which NinjaOne timed out, the remaining items wait
    for the next sync. Returns counts per outcome.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Items,
        [Parameter(Mandatory)]$Configuration,
        [Parameter(Mandatory)]$Token,
        [Parameter(Mandatory)]$Customer,
        [Parameter(Mandatory)]$TemplateId,
        [Parameter(Mandatory)]$OrganizationId,
        [string]$CIPPUrl,
        [int]$Concurrency = 8,
        [int]$TimeoutSec = 300
    )

    $Stats = [ordered]@{ SkipContent = 0; Create = 0; UpdateNoMap = 0; UpdateDocMoved = 0; UpdateDocEdited = 0; UpdateChanged = 0; Written = 0; Failed = 0; Unsent = 0; Stopped = $false; EditedSample = $null; ChangedFields = [ordered]@{} }
    $UsersMapTable = Get-CippTable -tablename 'NinjaOneUserMap'
    $Domain = $Customer.defaultDomainName
    $ItemById = @{}
    $Creations = [System.Collections.Generic.List[object]]::new()
    $Updates = [System.Collections.Generic.List[object]]::new()
    $Refreshes = [System.Collections.Generic.List[object]]::new()
    $MapRow = {
        param($Item, $NinjaOneID, $FieldHashes, $DocUpdateTime)
        [PSCustomObject]@{ PartitionKey = $Customer.customerId; RowKey = $Item.UserId; NinjaOneID = $NinjaOneID; M365ID = $Item.UserId; FieldHashes = "$FieldHashes"; InputHash = "$($Item.InputHash)"; DocUpdateTime = "$DocUpdateTime" }
    }

    foreach ($Item in $Items) {
        try {
            $Doc = [CIPP.CippJson]::ConvertFromJson($Item.Input).Doc
            $UserId = $Doc.Id
            $Links = @(
                @{ Name = 'Entra ID'; Link = "https://aad.portal.azure.com/$Domain/#blade/Microsoft_AAD_IAM/UserDetailsMenuBlade/Profile/userId/$UserId"; Icon = 'fas fa-users-cog' },
                @{ Name = 'Sign-In Logs'; Link = "https://aad.portal.azure.com/$Domain/#blade/Microsoft_AAD_IAM/UserDetailsMenuBlade/SignIns/userId/$UserId"; Icon = 'fas fa-users-cog' },
                @{ Name = 'Teams Admin'; Link = "https://admin.teams.microsoft.com/users/$UserId/account?delegatedOrg=$Domain"; Icon = 'fas fa-users' },
                @{ Name = 'Intune (User)'; Link = "https://endpoint.microsoft.com/$Domain/#blade/Microsoft_AAD_IAM/UserDetailsMenuBlade/Profile/userId/$UserId"; Icon = 'fas fa-laptop' },
                @{ Name = 'Intune (Devices)'; Link = "https://endpoint.microsoft.com/$Domain/#blade/Microsoft_AAD_IAM/UserDetailsMenuBlade/Devices/userId/$UserId"; Icon = 'fas fa-laptop' }
            )
            $CIPPLinks = @(
                @{ Name = 'View User'; Link = "https://$CIPPUrl/identity/administration/users/user?userId=$UserId&tenantFilter=$Domain"; Icon = 'far fa-eye' },
                @{ Name = 'Edit User'; Link = "https://$CIPPUrl/identity/administration/users/user/edit?userId=$UserId&tenantFilter=$Domain"; Icon = 'fas fa-users-cog' },
                @{ Name = 'Research Compromise'; Link = "https://$CIPPUrl/identity/administration/bec/case?userId=$UserId&tenantFilter=$Domain"; Icon = 'fas fa-user-secret' }
            )
            $UserLinksHTML = '<div class="row g-3"><div class="col-md-12 col-lg-6 d-flex">' + (Get-NinjaOneLinks -Data $Links -Title 'Portals' -SmallCols 2 -MedCols 3 -LargeCols 3 -XLCols 3) + '</div><div class="col-md-12 col-lg-6 d-flex">' + (Get-NinjaOneLinks -Data $CIPPLinks -Title 'CIPP Links' -SmallCols 2 -MedCols 3 -LargeCols 3 -XLCols 3) + '</div></div>'
            $UserSummaryHTML = '<div class="row g-3">' +
            '<div class="col-xl-4 col-lg-6 col-md-12 col-sm-12 d-flex">' + (Get-NinjaOneInfoCard -Title 'User Details' -Data $Doc.Overview -Icon 'fas fa-user') +
            '</div><div class="col-xl-4 col-lg-6 col-md-12 col-sm-12 d-flex">' + (Get-NinjaOneInfoCard -Title 'Mailbox Details' -Data $Doc.Mailbox -Icon 'fas fa-envelope') +
            '</div><div class="col-xl-4 col-lg-6 col-md-12 col-sm-12 d-flex">' + (Get-NinjaOneInfoCard -Title 'Mailbox Settings' -Data $Doc.Settings -Icon 'fas fa-envelope') +
            '</div><div class="col-xl-4 col-lg-6 col-md-12 col-sm-12 d-flex">' + (Get-NinjaOneInfoCard -Title 'OneDrive Details' -Data $Doc.OneDrive -Icon 'fas fa-envelope') +
            '</div><div class="col-xl-4 col-lg-6 col-md-12 col-sm-12 d-flex">' + (Get-NinjaOneCard -Title 'Assigned Conditional Access Policies' -Body $Doc.Policies) +
            '</div><div class="col-xl-4 col-lg-6 col-md-12 col-sm-12 d-flex">' +
            '</div></div></div>'
            $UserDeviceDetailHTML = ([System.Web.HttpUtility]::HtmlDecode(($Doc.Devices | ConvertTo-Html -As Table -Fragment)) -replace '<th>', '<th style="white-space: nowrap;">') -replace '<td>', '<td style="white-space: nowrap;">'
            $UserFields = @{
                cippUserLinks   = @{'html' = $UserLinksHTML }
                cippUserSummary = @{'html' = $UserSummaryHTML }
                cippUserGroups  = @{'html' = "$($Doc.Groups | ConvertTo-Html -As Table -Fragment)" }
                cippUserDevices = @{'html' = $UserDeviceDetailHTML }
                cippUserID      = $UserId
                cippUserUPN     = $Doc.Upn
            }

            $FieldHashes = [ordered]@{ '_name' = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes("$($Doc.Name)".ToCharArray()))).Substring(0, 16) }
            $Keys = [string[]]$UserFields.Keys
            [array]::Sort($Keys, [System.StringComparer]::Ordinal)
            foreach ($Key in $Keys) {
                $Value = $UserFields[$Key]
                $FieldHashes[$Key] = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes("$(if ($Value -is [hashtable]) { $Value.html } else { $Value })".ToCharArray()))).Substring(0, 16)
            }
            $FieldHashText = @(foreach ($Key in $FieldHashes.Keys) { "$Key=$($FieldHashes[$Key])" }) -join ';'
            # What NinjaOne holds is what we last wrote only while the document is untouched since that write
            $StoredHashes = $null
            if ($Item.DocUntouched) {
                $StoredHashes = @{}
                foreach ($Pair in "$($Item.MapFieldHashes)".Split(';')) { $Kv = $Pair.Split('=', 2); $StoredHashes[$Kv[0]] = $Kv[1] }
            }

            if ($StoredHashes -and $Item.MapFieldHashes -eq $FieldHashText) {
                # Inputs moved but the document did not: remember them so the next run skips the build
                $Stats.SkipContent++
                $Refreshes.Add((& $MapRow $Item $Item.MapNinjaOneID $Item.MapFieldHashes $Item.MapDocUpdateTime))
                if ($Refreshes.Count -ge 500) { Add-CIPPAzDataTableEntity @UsersMapTable -Entity @($Refreshes) -Force; $Refreshes.Clear() }
                continue
            }
            $ItemById[[string]$UserId] = @{ Item = $Item; Fields = $FieldHashText }
            if ($Item.DocumentId) {
                $Reason = if (-not $Item.MapFieldHashes) { 'UpdateNoMap' } elseif ("$($Item.MapNinjaOneID)" -ne "$($Item.DocumentId)") { 'UpdateDocMoved' } elseif (-not $Item.DocUntouched) { 'UpdateDocEdited' } else { 'UpdateChanged' }
                $Stats[$Reason]++
                if ($Reason -eq 'UpdateDocEdited' -and -not $Stats.EditedSample) { $Stats.EditedSample = "stored $($Item.MapDocUpdateTime), NinjaOne $($Item.NinjaDocUpdateTime)" }
                # Unchanged fields are left out; cippUserID always goes so the response can be matched to the user
                $SendFields = $UserFields
                if ($StoredHashes) {
                    $SendFields = @{ cippUserID = $UserId }
                    foreach ($Key in $UserFields.Keys) {
                        if ($StoredHashes[$Key] -ne $FieldHashes[$Key]) { $SendFields[$Key] = $UserFields[$Key]; $Stats.ChangedFields[$Key] = 1 + $Stats.ChangedFields[$Key] }
                    }
                    if ($StoredHashes['_name'] -ne $FieldHashes['_name']) { $Stats.ChangedFields['_name'] = 1 + $Stats.ChangedFields['_name'] }
                }
                $Updates.Add((@{ documentId = $Item.DocumentId; documentName = $Doc.Name; fields = $SendFields } | ConvertTo-Json -Depth 100))
            } else {
                $Stats.Create++
                $Creations.Add((@{ documentName = $Doc.Name; documentTemplateId = $TemplateId; organizationId = [int]$OrganizationId; fields = $UserFields } | ConvertTo-Json -Depth 100))
            }
        } catch {
            $Stats.Failed++
            Write-Error "User $($Item.UserId): failed to build the NinjaOne user document: $_"
        }
    }
    if ($Refreshes.Count) { Add-CIPPAzDataTableEntity @UsersMapTable -Entity @($Refreshes) -Force }

    $Batches = @(
        foreach ($Pending in @(@{ Kind = 'creation'; Method = 'POST'; Bodies = $Creations }, @{ Kind = 'update'; Method = 'PATCH'; Bodies = $Updates })) {
            for ($Offset = 0; $Offset -lt $Pending.Bodies.Count; $Offset += 100) {
                [PSCustomObject]@{ Kind = $Pending.Kind; Method = $Pending.Method; Bodies = $Pending.Bodies.GetRange($Offset, [Math]::Min(100, $Pending.Bodies.Count - $Offset)) }
            }
        })
    for ($Wave = 0; $Wave -lt $Batches.Count; $Wave += $Concurrency) {
        $WaveBatches = @($Batches[$Wave..([Math]::Min($Wave + $Concurrency - 1, $Batches.Count - 1))])
        if ($Stats.Stopped) {
            foreach ($Batch in $WaveBatches) { $Stats.Unsent = $Stats.Unsent + $Batch.Bodies.Count }
            continue
        }
        $WaveTimer = [System.Diagnostics.Stopwatch]::StartNew()
        $WaveResults = @(Invoke-NinjaOneRequestBatch -Configuration $Configuration -Token $Token -Concurrency $Concurrency -MaxRetries 0 -TimeoutSec $TimeoutSec -Requests @(
                foreach ($Batch in $WaveBatches) { @{ Method = $Batch.Method; Path = '/api/v2/organization/documents'; Body = "[$($Batch.Bodies -join ',')]" } }))
        Write-Information "Wrote NinjaOne user documents: batches $($Wave + 1)-$($Wave + $WaveBatches.Count) of $($Batches.Count) ($(@(foreach ($Batch in $WaveBatches) { "$($Batch.Bodies.Count) $($Batch.Kind)" }) -join ', ')) in $([int]$WaveTimer.Elapsed.TotalSeconds) s"
        for ($i = 0; $i -lt $WaveBatches.Count; $i++) {
            $Result = $WaveResults[$i]
            if ($Result.IsSuccess) {
                $MapWrites = foreach ($UserDoc in @($Result.Result.Content | ConvertFrom-Json -Depth 100)) {
                    if ($null -eq $UserDoc -or $UserDoc -eq '') { continue }
                    $UserId = (@($UserDoc.updatedFields) + @($UserDoc.fields)).Where({ $_.name -eq 'cippUserID' }, 'First')[0].value
                    $Written = if ($UserId) { $ItemById[[string]$UserId] }
                    if (-not $Written) {
                        Write-Error "Unmatched Doc: $($UserDoc | ConvertTo-Json -Depth 100)"
                        continue
                    }
                    $Stats.Written++
                    & $MapRow $Written.Item $UserDoc.documentId $Written.Fields $UserDoc.documentUpdateTime
                }
                if ($MapWrites) { Add-CIPPAzDataTableEntity @UsersMapTable -Entity @($MapWrites) -Force }
                continue
            }
            $Stats.Failed = $Stats.Failed + $WaveBatches[$i].Bodies.Count
            if ($Result.TimedOut) {
                $Stats.Stopped = $true
                Write-LogMessage -tenant $Domain -API 'NinjaOneSync' -message "NinjaOne did not answer a user document write for $($Customer.displayName) within $TimeoutSec seconds. The remaining user document writes are skipped this run and retried on the next sync." -Sev 'Warning'
            }
            $Reason = if ($Result.Error) { $Result.Error } else { "HTTP $($Result.StatusCode) $($Result.Result.Content)" }
            Write-LogMessage -tenant $Domain -API 'NinjaOneSync' -message "NinjaOne user document $($WaveBatches[$i].Kind) failed for $($Customer.displayName). NinjaOne rejects the whole batch if any single document is invalid, so all $($WaveBatches[$i].Bodies.Count) user(s) in this batch were not written: $Reason" -Sev 'Error'
        }
    }
    Write-Information "User docs written: $($Stats.Written) | content unchanged $($Stats.SkipContent) | new $($Stats.Create), no map row $($Stats.UpdateNoMap), doc id changed $($Stats.UpdateDocMoved), doc edited in NinjaOne $($Stats.UpdateDocEdited), content changed $($Stats.UpdateChanged) | failed $($Stats.Failed), unsent $($Stats.Unsent) | changed fields: $(@(foreach ($Key in $Stats.ChangedFields.Keys) { "$Key=$($Stats.ChangedFields[$Key])" }) -join ', ')"
    if ($Stats.EditedSample) { Write-Information "User docs edited in NinjaOne since the last write, first: $($Stats.EditedSample)" }
    $Stats
}
