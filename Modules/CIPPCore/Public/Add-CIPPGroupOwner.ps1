function Add-CIPPGroupOwner {
    <#
    .SYNOPSIS
    Adds one or more owners to a specified group.

    .DESCRIPTION
    Adds owners via Graph for Microsoft 365 and Security groups, or updates the
    ManagedBy list via Exchange for Distribution Lists and Mail-Enabled Security groups.
    Resolves identities to Graph object ids so ManagedBy compare/write matches ListGroups/EditGroup.

    .PARAMETER Headers
    Request headers for logging. Supplied automatically by the API.

    .PARAMETER GroupId
    The unique identifier of the group.

    .PARAMETER Owner
    An array of owner identifiers (user GUIDs or UPNs) to add.

    .PARAMETER TenantFilter
    The tenant identifier.

    .PARAMETER APIName
    The API operation name for logging. Default: 'Add Group Owner'.
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
        [string]$APIName = 'Add Group Owner'
    )

    try {
        $ODataBindString = 'https://graph.microsoft.com/v1.0/directoryObjects/{0}'
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
            # Keep unresolved ManagedBy entries as-is so a failed lookup cannot strip an owner.
            $NewManagedBy = [System.Collections.Generic.List[string]]::new()
            $CurrentIdSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($Entry in $CurrentResolved) {
                if ($Entry.Resolved -and $Entry.Id) {
                    $null = $CurrentIdSet.Add($Entry.Id)
                    $NewManagedBy.Add($Entry.Id)
                } else {
                    $NewManagedBy.Add($Entry.Input)
                }
            }

            foreach ($OwnerInfo in $ResolvedOwners) {
                $Label = $OwnerInfo.UserPrincipalName ?? $OwnerInfo.DisplayName ?? $OwnerInfo.Input
                if (-not $OwnerInfo.Resolved -or -not $OwnerInfo.Id) {
                    $FailedUsers.Add("$Label (user not found)")
                    continue
                }
                if ($CurrentIdSet.Contains($OwnerInfo.Id)) {
                    $FailedUsers.Add("$Label (already an owner)")
                    continue
                }
                $NewManagedBy.Add($OwnerInfo.Id)
                $null = $CurrentIdSet.Add($OwnerInfo.Id)
                $SuccessfulUsers.Add($Label)
            }

            if ($SuccessfulUsers.Count -gt 0) {
                $OperationGuid = [Guid]::NewGuid().ToString()
                $ExoBulkRequests = @(@{
                        CmdletInput   = @{
                            CmdletName = 'Set-DistributionGroup'
                            Parameters = @{ Identity = $GroupId; ManagedBy = @($NewManagedBy | Sort-Object -Unique); BypassSecurityGroupManagerCheck = $true }
                        }
                        OperationGuid = $OperationGuid
                    })
                $ExoLogs = @(@{
                        message       = "Added owners $($SuccessfulUsers -join ', ') to group $($GroupName)"
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
                        foreach ($OwnerInfo in $ResolvedOwners) {
                            $Label = $OwnerInfo.UserPrincipalName ?? $OwnerInfo.DisplayName ?? $OwnerInfo.Input
                            $FailedUsers.Add("$Label ($($ExoResult.ErrorMessage))")
                        }
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to add owners to group $($GroupName): $($ExoResult.ErrorMessage)" -Sev 'Error'
                    }
                }
            }
        } else {
            $AddRequests = foreach ($OwnerInfo in $ResolvedOwners) {
                if (-not $OwnerInfo.Resolved -or -not $OwnerInfo.Id) { continue }
                @{
                    id      = $OwnerInfo.Id
                    method  = 'POST'
                    url     = "/groups/$($GroupId)/owners/`$ref"
                    body    = @{ '@odata.id' = ($ODataBindString -f $OwnerInfo.Id) }
                    headers = @{ 'Content-Type' = 'application/json' }
                }
            }
            foreach ($OwnerInfo in $ResolvedOwners) {
                if (-not $OwnerInfo.Resolved -or -not $OwnerInfo.Id) {
                    $Label = $OwnerInfo.UserPrincipalName ?? $OwnerInfo.DisplayName ?? $OwnerInfo.Input
                    $FailedUsers.Add("$Label (user not found)")
                }
            }
            if (@($AddRequests).Count -gt 0) {
                $AddResults = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($AddRequests)
                foreach ($Result in $AddResults) {
                    $OwnerInfo = $ResolvedOwners | Where-Object { $_.Id -eq $Result.id } | Select-Object -First 1
                    $Label = $OwnerInfo.UserPrincipalName ?? $OwnerInfo.DisplayName ?? $OwnerInfo.Input ?? $Result.id
                    if ($Result.status -lt 200 -or $Result.status -gt 299) {
                        $ErrorText = Get-NormalizedError -message ($Result.body.error.message ?? "Request failed with status $($Result.status)") | Select-Object -First 1
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to add owner $Label to group $($GroupName): $ErrorText" -Sev 'Error'
                        $FailedUsers.Add("$Label ($ErrorText)")
                    } else {
                        $SuccessfulUsers.Add($Label)
                    }
                }
            }
        }

        $Messages = [System.Collections.Generic.List[string]]::new()
        if ($SuccessfulUsers.Count -gt 0) {
            $Messages.Add("Successfully added owner $($SuccessfulUsers -join ', ') to group $($GroupName).")
        }
        if ($FailedUsers.Count -gt 0) {
            $Messages.Add("Failed to add $($FailedUsers -join '; ').")
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
        $Results = "Failed to add owner $UserList to group $($GroupName ?? $GroupId) - $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev 'error' -LogData $ErrorMessage
        throw $Results
    }
}
