function Remove-CIPPGroupMember {
    <#
    .SYNOPSIS
    Removes members from a Microsoft 365 group.

    .DESCRIPTION
    Removes directory objects (users, groups, etc.) from Security Groups, Distribution
    Groups, or Mail-Enabled Security Groups. Resolves identities via Resolve-CIPPDirectoryId.

    .PARAMETER Headers
    The headers for the API request, typically containing authentication information.

    .PARAMETER TenantFilter
    The tenant identifier for the target tenant.

    .PARAMETER GroupType
    Optional fallback type when Graph/Exchange cannot classify the target group.

    .PARAMETER GroupId
    The unique identifier (GUID or name) of the group.

    .PARAMETER Member
    An array of member identifiers (object ids, UPNs, or mail addresses).

    .PARAMETER APIName
    The API operation name for logging purposes. Default: 'Remove Group Member'.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [string]$GroupType,

        [Parameter(Mandatory = $true)]
        [string]$GroupId,

        [Parameter(Mandatory = $true)]
        [string[]]$Member,

        [Parameter(Mandatory = $false)]
        [string]$APIName = 'Remove Group Member',

        $Headers
    )

    try {
        $Group = Get-CIPPGroupType -GroupId $GroupId -TenantFilter $TenantFilter -FallbackGroupType $GroupType
        $GroupName = $Group.DisplayName
        $ResolvedMembers = @(Resolve-CIPPDirectoryId -Identity $Member -TenantFilter $TenantFilter)

        $SuccessfulMembers = [System.Collections.Generic.List[string]]::new()
        $FailedMembers = [System.Collections.Generic.List[string]]::new()

        foreach ($Entry in $ResolvedMembers) {
            if (-not $Entry.Resolved -or -not $Entry.Id) {
                $FailedMembers.Add("$($Entry.Label) (directory object not found)")
            }
        }
        $ValidMembers = @($ResolvedMembers | Where-Object { $_.Resolved -and $_.Id })

        if ($Group.IsExchangeBacked) {
            $ExoBulkRequests = [System.Collections.Generic.List[object]]::new()
            $ExoLogs = [System.Collections.Generic.List[object]]::new()

            foreach ($Entry in $ValidMembers) {
                $OperationGuid = [Guid]::NewGuid().ToString()
                $ExoMember = $Entry.ExchangeIdentity ?? $Entry.Id
                $Params = @{ Identity = $GroupId; Member = $ExoMember; BypassSecurityGroupManagerCheck = $true }
                $ExoBulkRequests.Add(@{
                        CmdletInput   = @{
                            CmdletName = 'Remove-DistributionGroupMember'
                            Parameters = $Params
                        }
                        OperationGuid = $OperationGuid
                    })
                $ExoLogs.Add(@{
                        message       = "Removed member $($Entry.Label) from group $($GroupName)"
                        target        = $ExoMember
                        OperationGuid = $OperationGuid
                    })
            }

            if ($ExoBulkRequests.Count -gt 0) {
                $RawExoRequest = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray @($ExoBulkRequests)
                $ExoResults = Resolve-CippExoBulkResult -Response $RawExoRequest -Operations $ExoLogs

                foreach ($ExoResult in $ExoResults) {
                    $Entry = $ValidMembers | Where-Object {
                        ($_.ExchangeIdentity ?? $_.Id) -eq $ExoResult.Operation.target
                    } | Select-Object -First 1
                    $Label = $Entry.Label ?? $ExoResult.Operation.target
                    if ($ExoResult.Success) {
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $ExoResult.Operation.message -Sev 'Info'
                        $SuccessfulMembers.Add($Label)
                    } else {
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to remove member $Label from group $($GroupName): $($ExoResult.ErrorMessage)" -Sev 'Error'
                        $FailedMembers.Add("$Label ($($ExoResult.ErrorMessage))")
                    }
                }
            }
        } else {
            $RemovalRequests = foreach ($Entry in $ValidMembers) {
                @{
                    id     = $Entry.Id
                    method = 'DELETE'
                    url    = "/groups/$($GroupId)/members/$($Entry.Id)/`$ref"
                }
            }
            if (@($RemovalRequests).Count -gt 0) {
                $RemovalResults = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($RemovalRequests)
                foreach ($Result in $RemovalResults) {
                    $Entry = $ValidMembers | Where-Object { $_.Id -eq $Result.id } | Select-Object -First 1
                    $Label = $Entry.Label ?? $Result.id
                    if ($Result.status -lt 200 -or $Result.status -gt 299) {
                        $ErrorText = Get-NormalizedError -message ($Result.body.error.message ?? "Request failed with status $($Result.status)") | Select-Object -First 1
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to remove member $Label from group $($GroupName): $ErrorText" -Sev 'Error'
                        $FailedMembers.Add("$Label ($ErrorText)")
                    } else {
                        $SuccessfulMembers.Add($Label)
                    }
                }
            }
        }
        $Messages = [System.Collections.Generic.List[string]]::new()
        if ($SuccessfulMembers.Count -gt 0) {
            $Messages.Add("Successfully removed $($SuccessfulMembers -join ', ') from group $($GroupName).")
        }
        if ($FailedMembers.Count -gt 0) {
            $Messages.Add("Failed to remove $($FailedMembers -join '; ').")
        }
        $Results = $Messages -join ' '
        if ($SuccessfulMembers.Count -eq 0 -and $FailedMembers.Count -gt 0) {
            throw $Results
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev Info
        return $Results

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $MemberList = if ($ResolvedMembers) {
            ($ResolvedMembers | ForEach-Object { $_.Label ?? $_.Input }) -join ', '
        } else {
            ($Member -join ', ')
        }
        $Results = "Failed to remove $MemberList from group $($GroupName ?? $GroupId): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev Error -LogData $ErrorMessage
        throw $Results
    }
}
