function Add-CIPPGroupMember {
    <#
    .SYNOPSIS
    Adds one or more members to a specified group.

    .DESCRIPTION
    Adds directory objects (users, groups, etc.) to a group. Routes through Exchange for
    distribution lists and mail-enabled security groups, Graph for everything else.
    Resolves identities via Resolve-CIPPDirectoryId so callers can pass ids or UPNs/mail.

    .PARAMETER Headers
    The headers to include in the request, typically containing authentication tokens. This is supplied automatically by the API

    .PARAMETER GroupType
    Optional fallback type when Graph/Exchange cannot classify the target group.

    .PARAMETER GroupId
    The unique identifier of the group to which the member will be added.

    .PARAMETER Member
    An array of member identifiers (object ids, UPNs, or mail addresses).

    .PARAMETER TenantFilter
    The tenant identifier to filter the request.

    .PARAMETER APIName
    The name of the API operation being performed. Defaults to 'Add Group Member'.
    #>
    [CmdletBinding()]
    param(
        $Headers,
        [string]$GroupType,
        [string]$GroupId,
        [string[]]$Member,
        [string]$TenantFilter,
        [string]$APIName = 'Add Group Member'
    )
    try {
        $ODataBindString = 'https://graph.microsoft.com/v1.0/directoryObjects/{0}'
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
                            CmdletName = 'Add-DistributionGroupMember'
                            Parameters = $Params
                        }
                        OperationGuid = $OperationGuid
                    })
                $ExoLogs.Add(@{
                        message       = "Added member $($Entry.Label) to group $($GroupName)"
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
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to add member $Label to group $($GroupName): $($ExoResult.ErrorMessage)" -Sev 'Error'
                        $FailedMembers.Add("$Label ($($ExoResult.ErrorMessage))")
                    }
                }
            }
        } else {
            $AddRequests = foreach ($Entry in $ValidMembers) {
                @{
                    id      = $Entry.Id
                    method  = 'POST'
                    url     = "/groups/$($GroupId)/members/`$ref"
                    body    = @{ '@odata.id' = ($ODataBindString -f $Entry.Id) }
                    headers = @{ 'Content-Type' = 'application/json' }
                }
            }
            if (@($AddRequests).Count -gt 0) {
                $AddResults = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($AddRequests)
                foreach ($Result in $AddResults) {
                    $Entry = $ValidMembers | Where-Object { $_.Id -eq $Result.id } | Select-Object -First 1
                    $Label = $Entry.Label ?? $Result.id
                    if ($Result.status -lt 200 -or $Result.status -gt 299) {
                        $ErrorText = Get-NormalizedError -message ($Result.body.error.message ?? "Request failed with status $($Result.status)") | Select-Object -First 1
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to add member $Label to group $($GroupName): $ErrorText" -Sev 'Error'
                        $FailedMembers.Add("$Label ($ErrorText)")
                    } else {
                        $SuccessfulMembers.Add($Label)
                    }
                }
            }
        }
        $Messages = [System.Collections.Generic.List[string]]::new()
        if ($SuccessfulMembers.Count -gt 0) {
            $Messages.Add("Successfully added $($SuccessfulMembers -join ', ') to group $($GroupName).")
        }
        if ($FailedMembers.Count -gt 0) {
            $Messages.Add("Failed to add $($FailedMembers -join '; ').")
        }
        $Results = $Messages -join ' '
        if ($SuccessfulMembers.Count -eq 0 -and $FailedMembers.Count -gt 0) {
            throw $Results
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev 'Info'
        return $Results
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $MemberList = if ($ResolvedMembers) {
            ($ResolvedMembers | ForEach-Object { $_.Label ?? $_.Input }) -join ', '
        } else {
            ($Member -join ', ')
        }
        $Results = "Failed to add $MemberList to group $($GroupName ?? $GroupId) - $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev 'error' -LogData $ErrorMessage
        throw $Results
    }
}
