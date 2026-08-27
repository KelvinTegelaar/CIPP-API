function Set-CIPPDBCacheGroups {
    <#
    .SYNOPSIS
        Caches all groups for a tenant

    .PARAMETER TenantFilter
        The tenant to cache groups for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching groups' -sev Debug

        $MemberBatchSize = 50
        $GroupSelect = 'id,createdDateTime,displayName,description,mail,mailEnabled,mailNickname,resourceProvisioningOptions,securityEnabled,visibility,organizationId,onPremisesSamAccountName,membershipRule,groupTypes,onPremisesSyncEnabled,assignedLicenses,licenseProcessingState'
        $GroupUri = "https://graph.microsoft.com/beta/groups?`$top=999&`$select=$GroupSelect&`$expand=owners(`$select=id,displayName,userPrincipalName)"

        # Stream groups in batches of $MemberBatchSize so peak memory is one batch of rows
        # plus their member lists, not the whole tenant. The writer is opened before the
        # pipeline on purpose: GetSteppablePipeline() captures whichever scope is live, so
        # opening it inside ForEach-Object captures the Graph call's scope, which is gone
        # by End() - the end block then fails with "is not recognized".
        $CachedCount = 0
        $PendingBatch = [System.Collections.Generic.List[object]]::new()
        $Writer = { Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Groups' -AddCount }.GetSteppablePipeline()
        $Writer.Begin($true)

        function Write-GroupBatch {
            param(
                [System.Collections.Generic.List[object]]$Batch,
                $PipelineWriter,
                [ref]$Count
            )

            if ($Batch.Count -eq 0) { return }

            $MemberRequests = $Batch | ForEach-Object {
                if ($_.id -and $_.groupTypes -notcontains 'DynamicMembership') {
                    [PSCustomObject]@{
                        id     = $_.id
                        method = 'GET'
                        url    = "/groups/$($_.id)/members?`$top=999&`$select=id,displayName,userPrincipalName"
                    }
                }
            }

            $MembersByGroupId = @{}
            if ($MemberRequests) {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Fetching group members for batch of $($Batch.Count)" -sev Debug
                $MemberResults = New-GraphBulkRequest -Requests @($MemberRequests) -tenantid $TenantFilter
                foreach ($Result in $MemberResults) {
                    if ($Result.id) { $MembersByGroupId[$Result.id] = $Result.body.value }
                }
                $MemberResults = $null
            }

            foreach ($Group in $Batch) {
                $groupType = if ($Group.groupTypes -contains 'Unified') { 'Microsoft 365' }
                elseif ($Group.mailEnabled -and $Group.securityEnabled) { 'Mail-Enabled Security' }
                elseif (-not $Group.mailEnabled -and $Group.securityEnabled) { 'Security' }
                elseif ([string]::IsNullOrEmpty($Group.groupTypes) -and $Group.mailEnabled -and -not $Group.securityEnabled) { 'Distribution List' }
                else { 'Unknown' }
                $calculatedGroupType = if ($Group.groupTypes -contains 'Unified') { 'm365' }
                elseif ($Group.mailEnabled -and $Group.securityEnabled) { 'security' }
                elseif (-not $Group.mailEnabled -and $Group.securityEnabled) { 'generic' }
                elseif ([string]::IsNullOrEmpty($Group.groupTypes) -and $Group.mailEnabled -and -not $Group.securityEnabled) { 'distributionList' }
                else { 'unknown' }

                $NoteProperties = [ordered]@{}
                if ($Group.id -and $Group.groupTypes -notcontains 'DynamicMembership') {
                    $NoteProperties['members'] = $MembersByGroupId[$Group.id]
                }
                $NoteProperties['primDomain'] = ($Group.mail -split '@' | Select-Object -Last 1)
                $NoteProperties['teamsEnabled'] = ($Group.resourceProvisioningOptions -contains 'Team')
                $NoteProperties['dynamicGroupBool'] = ($Group.groupTypes -contains 'DynamicMembership')
                $NoteProperties['groupType'] = $groupType
                $NoteProperties['calculatedGroupType'] = $calculatedGroupType

                $Group | Add-Member -NotePropertyMembers $NoteProperties -Force
                $Count.Value++
                $PipelineWriter.Process($Group)
            }

            $Batch.Clear()
            $MembersByGroupId = $null
        }

        try {
            New-GraphGetRequest -uri $GroupUri -tenantid $TenantFilter -Stream | ForEach-Object {
                $PendingBatch.Add($_)
                if ($PendingBatch.Count -ge $MemberBatchSize) {
                    Write-GroupBatch -Batch $PendingBatch -PipelineWriter $Writer -Count ([ref]$CachedCount)
                }
            }

            Write-GroupBatch -Batch $PendingBatch -PipelineWriter $Writer -Count ([ref]$CachedCount)

            if ($CachedCount -gt 0) {
                $Writer.End()
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $CachedCount groups with members and owners successfully" -sev Debug
            }
        } finally {
            $Writer.Dispose()
        }

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache groups: $($_.Exception.Message)" -sev Error
    }
}
