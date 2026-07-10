function Add-CIPPGroupMember {
    <#
    .SYNOPSIS
    Adds one or more members to a specified group in Microsoft Graph.

    .DESCRIPTION
    This function adds one or more members to a specified group in Microsoft Graph, supporting different group types such as Distribution lists and Mail-Enabled Security groups.

    .PARAMETER Headers
    The headers to include in the request, typically containing authentication tokens. This is supplied automatically by the API

    .PARAMETER GroupType
    The type of group to which the member is being added, such as Security, Distribution list or Mail-Enabled Security.

    .PARAMETER GroupId
    The unique identifier of the group to which the member will be added.

    .PARAMETER Member
    An array of members to add to the group.

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
        $Requests = @(
            foreach ($m in $Member) {
                if ($m -like '*#EXT#*') { $m = [System.Web.HttpUtility]::UrlEncode($m) }
                @{
                    id     = "users-$m"
                    url    = "users/$($m)?`$select=id,userPrincipalName"
                    method = 'GET'
                }
            }
            @{
                id     = 'group'
                url    = "groups/$($GroupId)?`$select=id,displayName"
                method = 'GET'
            }
        )
        $BulkResults = New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter
        $Users = @($BulkResults | Where-Object { $_.id -like 'users-*' })
        # Group display name for logging; falls back to the id if the lookup failed
        # (e.g. the group was addressed by mail rather than GUID).
        $GroupName = ($BulkResults | Where-Object { $_.id -eq 'group' }).body.displayName ?? $GroupId
        $SuccessfulUsers = [System.Collections.Generic.List[string]]::new()
        $FailedUsers = [System.Collections.Generic.List[string]]::new()

        if ($GroupType -eq 'Distribution list' -or $GroupType -eq 'Mail-Enabled Security') {
            $ExoBulkRequests = [System.Collections.Generic.List[object]]::new()
            $ExoLogs = [System.Collections.Generic.List[object]]::new()

            foreach ($User in $Users) {
                $Params = @{ Identity = $GroupId; Member = $User.body.userPrincipalName; BypassSecurityGroupManagerCheck = $true }
                $ExoBulkRequests.Add(@{
                        CmdletInput = @{
                            CmdletName = 'Add-DistributionGroupMember'
                            Parameters = $Params
                        }
                    })
                $ExoLogs.Add(@{
                        message = "Added member $($User.body.userPrincipalName) to group $($GroupName)"
                        target  = $User.body.userPrincipalName
                    })
            }

            if ($ExoBulkRequests.Count -gt 0) {
                $RawExoRequest = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray @($ExoBulkRequests)
                $LastError = $RawExoRequest | Select-Object -Last 1

                foreach ($ExoError in $LastError.error) {
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $ExoError -Sev 'Error'
                    throw $ExoError
                }

                foreach ($ExoLog in $ExoLogs) {
                    $ExoError = $LastError | Where-Object { $ExoLog.target -in $_.target -and $_.error }
                    if (!$LastError -or ($LastError.error -and $LastError.target -notcontains $ExoLog.target)) {
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $ExoLog.message -Sev 'Info'
                        $SuccessfulUsers.Add($ExoLog.target)
                    }
                }
            }
        } else {
            # Build one bulk request list; New-GraphBulkRequest handles internal chunking
            $AddRequests = foreach ($User in $Users) {
                @{
                    id      = $User.body.id
                    method  = 'POST'
                    url     = "/groups/$($GroupId)/members/`$ref"
                    body    = @{ '@odata.id' = ($ODataBindString -f $User.body.id) }
                    headers = @{ 'Content-Type' = 'application/json' }
                }
            }
            $AddResults = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($AddRequests)
            foreach ($Result in $AddResults) {
                $UserPrincipalName = ($Users | Where-Object { $_.body.id -eq $Result.id }).body.userPrincipalName
                if ($Result.status -lt 200 -or $Result.status -gt 299) {
                    # Select-Object -First 1: Get-NormalizedError can return multiple strings
                    # when a message matches more than one of its translation patterns.
                    $ErrorText = Get-NormalizedError -message ($Result.body.error.message ?? "Request failed with status $($Result.status)") | Select-Object -First 1
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to add member $UserPrincipalName to group $($GroupName): $ErrorText" -Sev 'Error'
                    $FailedUsers.Add("$UserPrincipalName ($ErrorText)")
                } else {
                    $SuccessfulUsers.Add($UserPrincipalName)
                }
            }
        }
        $Messages = [System.Collections.Generic.List[string]]::new()
        if ($SuccessfulUsers.Count -gt 0) {
            $Messages.Add("Successfully added user $($SuccessfulUsers -join ', ') to group $($GroupName).")
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
        $UserList = if ($Users) { ($Users.body.userPrincipalName -join ', ') } else { ($Member -join ', ') }
        $Results = "Failed to add user $UserList to group $($GroupName ?? $GroupId) - $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev 'error' -LogData $ErrorMessage
        throw $Results
    }
}
