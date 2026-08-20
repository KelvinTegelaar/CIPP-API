function Remove-CIPPGroupOwner {
    <#
    .SYNOPSIS
    Removes one or more owners from a specified group.

    .DESCRIPTION
    Removes owners via Graph for Microsoft 365 and Security groups, or updates the
    ManagedBy list via Exchange for Distribution Lists and Mail-Enabled Security groups.
    Resolves identities to Graph object ids so ManagedBy compare/write matches ListGroups/EditGroup.

    .PARAMETER Headers
    Request headers for logging. Supplied automatically by the API.

    .PARAMETER GroupId
    The unique identifier of the group.

    .PARAMETER Owner
    An array of owner identifiers (user GUIDs or UPNs) to remove.

    .PARAMETER TenantFilter
    The tenant identifier.

    .PARAMETER APIName
    The API operation name for logging. Default: 'Remove Group Owner'.
    #>
    [CmdletBinding()]
    param(
        $Headers,
        [Parameter(Mandatory = $true)]
        [string]$GroupId,
        [Parameter(Mandatory = $true)]
        [string[]]$Owner,
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$APIName = 'Remove Group Owner'
    )

    try {
        $Group = Get-CIPPGroupType -GroupId $GroupId -TenantFilter $TenantFilter
        $GroupName = $Group.DisplayName
        $ResolvedOwners = @(Resolve-CIPPDirectoryId -Identity $Owner -TenantFilter $TenantFilter)

        $SuccessfulUsers = [System.Collections.Generic.List[string]]::new()
        $FailedUsers = [System.Collections.Generic.List[string]]::new()

        if ($Group.IsExchangeBacked) {
            $CurrentOwnersRaw = @(
                New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DistributionGroup' -cmdParams @{ Identity = $GroupId } -UseSystemMailbox $true |
                    Select-Object -ExpandProperty ManagedBy
            )
            $CurrentResolved = @(Resolve-CIPPDirectoryId -Identity $CurrentOwnersRaw -TenantFilter $TenantFilter)

            $RemoveIdSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($OwnerInfo in $ResolvedOwners) {
                $Label = $OwnerInfo.UserPrincipalName ?? $OwnerInfo.DisplayName ?? $OwnerInfo.Input
                if (-not $OwnerInfo.Resolved -or -not $OwnerInfo.Id) {
                    $FailedUsers.Add("$Label (user not found)")
                    continue
                }
                $null = $RemoveIdSet.Add($OwnerInfo.Id)
            }

            $NewManagedBy = [System.Collections.Generic.List[string]]::new()
            $RemovedLabels = [System.Collections.Generic.List[string]]::new()
            $CurrentIdSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

            foreach ($Entry in $CurrentResolved) {
                if ($Entry.Resolved -and $Entry.Id) {
                    $null = $CurrentIdSet.Add($Entry.Id)
                    if ($RemoveIdSet.Contains($Entry.Id)) {
                        $Label = $Entry.UserPrincipalName ?? $Entry.DisplayName ?? $Entry.Input
                        $RemovedLabels.Add($Label)
                        continue
                    }
                    $NewManagedBy.Add($Entry.Id)
                } else {
                    # Unresolved current owner: only drop if the raw ManagedBy string was requested.
                    if ($Owner -contains $Entry.Input) {
                        $RemovedLabels.Add($Entry.Input)
                    } else {
                        $NewManagedBy.Add($Entry.Input)
                    }
                }
            }

            foreach ($OwnerInfo in $ResolvedOwners) {
                if ($OwnerInfo.Resolved -and $OwnerInfo.Id -and -not $CurrentIdSet.Contains($OwnerInfo.Id)) {
                    $Label = $OwnerInfo.UserPrincipalName ?? $OwnerInfo.DisplayName ?? $OwnerInfo.Input
                    $FailedUsers.Add("$Label (not an owner)")
                }
            }

            foreach ($Label in $RemovedLabels) { $SuccessfulUsers.Add($Label) }

            if ($SuccessfulUsers.Count -gt 0) {
                $OperationGuid = [Guid]::NewGuid().ToString()
                $ExoBulkRequests = @(@{
                        CmdletInput   = @{
                            CmdletName = 'Set-DistributionGroup'
                            Parameters = @{ Identity = $GroupId; ManagedBy = @($NewManagedBy); BypassSecurityGroupManagerCheck = $true }
                        }
                        OperationGuid = $OperationGuid
                    })
                $ExoLogs = @(@{
                        message       = "Removed owners $($SuccessfulUsers -join ', ') from group $($GroupName)"
                        target        = $GroupId
                        OperationGuid = $OperationGuid
                    })
                $RawExoRequest = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray @($ExoBulkRequests)
                $ExoResults = Resolve-CippExoBulkResult -Response $RawExoRequest -Operations $ExoLogs

                foreach ($ExoResult in $ExoResults) {
                    if ($ExoResult.Success) {
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $ExoResult.Operation.message -Sev 'Info'
                    } else {
                        $SuccessfulUsers.Clear()
                        foreach ($Label in $RemovedLabels) {
                            $FailedUsers.Add("$Label ($($ExoResult.ErrorMessage))")
                        }
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to remove owners from group $($GroupName): $($ExoResult.ErrorMessage)" -Sev 'Error'
                    }
                }
            }
        } else {
            $RemovalRequests = foreach ($OwnerInfo in $ResolvedOwners) {
                if (-not $OwnerInfo.Resolved -or -not $OwnerInfo.Id) { continue }
                @{
                    id     = $OwnerInfo.Id
                    method = 'DELETE'
                    url    = "/groups/$($GroupId)/owners/$($OwnerInfo.Id)/`$ref"
                }
            }
            foreach ($OwnerInfo in $ResolvedOwners) {
                if (-not $OwnerInfo.Resolved -or -not $OwnerInfo.Id) {
                    $Label = $OwnerInfo.UserPrincipalName ?? $OwnerInfo.DisplayName ?? $OwnerInfo.Input
                    $FailedUsers.Add("$Label (user not found)")
                }
            }
            if (@($RemovalRequests).Count -gt 0) {
                $RemovalResults = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($RemovalRequests)
                foreach ($Result in $RemovalResults) {
                    $OwnerInfo = $ResolvedOwners | Where-Object { $_.Id -eq $Result.id } | Select-Object -First 1
                    $Label = $OwnerInfo.UserPrincipalName ?? $OwnerInfo.DisplayName ?? $OwnerInfo.Input ?? $Result.id
                    if ($Result.status -lt 200 -or $Result.status -gt 299) {
                        $ErrorText = Get-NormalizedError -message ($Result.body.error.message ?? "Request failed with status $($Result.status)") | Select-Object -First 1
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to remove owner $Label from group $($GroupName): $ErrorText" -Sev 'Error'
                        $FailedUsers.Add("$Label ($ErrorText)")
                    } else {
                        $SuccessfulUsers.Add($Label)
                    }
                }
            }
        }

        $Messages = [System.Collections.Generic.List[string]]::new()
        if ($SuccessfulUsers.Count -gt 0) {
            $Messages.Add("Successfully removed owner $($SuccessfulUsers -join ', ') from group $($GroupName).")
        }
        if ($FailedUsers.Count -gt 0) {
            $Messages.Add("Failed to remove $($FailedUsers -join '; ').")
        }
        $Results = $Messages -join ' '
        if ($SuccessfulUsers.Count -eq 0 -and $FailedUsers.Count -gt 0) {
            throw $Results
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev 'Info'
        return $Results
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $UserList = if ($ResolvedOwners) {
            ($ResolvedOwners | ForEach-Object { $_.UserPrincipalName ?? $_.Input }) -join ', '
        } else {
            ($Owner -join ', ')
        }
        $Results = "Failed to remove owner $UserList from group $($GroupName ?? $GroupId) - $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev 'error' -LogData $ErrorMessage
        throw $Results
    }
}
