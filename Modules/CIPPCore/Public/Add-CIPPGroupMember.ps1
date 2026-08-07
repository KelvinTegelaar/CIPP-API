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
                url    = "groups/$($GroupId)?`$select=id,displayName,groupTypes,mailEnabled,securityEnabled"
                method = 'GET'
            }
        )
        $BulkResults = New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter
        $Users = @($BulkResults | Where-Object { $_.id -like 'users-*' })
        $GroupObject = ($BulkResults | Where-Object { $_.id -eq 'group' }).body
        # Group display name for logging; falls back to the id if the lookup failed
        # (e.g. the group was addressed by mail rather than GUID).
        $GroupName = $GroupObject.displayName ?? $GroupId
        # Graph cannot write membership to Exchange-backed groups: a classic distribution list or a
        # mail-enabled security group rejects members/$ref with "Cannot Update a mail-enabled
        # security groups and or distribution list". Callers pass a group type from the UI, but
        # templates and stored autocomplete options routinely carry none (or a stale one), so
        # prefer what Graph says the group actually is and only fall back to the caller's value
        # when the lookup told us nothing.
        $ResolvedGroupType = if ($null -ne $GroupObject.mailEnabled -or $null -ne $GroupObject.securityEnabled) {
            if ($GroupObject.groupTypes -contains 'Unified') { 'Microsoft 365' }
            elseif ($GroupObject.mailEnabled -and $GroupObject.securityEnabled) { 'Mail-Enabled Security' }
            elseif ($GroupObject.mailEnabled) { 'Distribution list' }
            else { 'Security' }
        } else {
            $GroupType
        }
        $SuccessfulUsers = [System.Collections.Generic.List[string]]::new()
        $FailedUsers = [System.Collections.Generic.List[string]]::new()

        if ($ResolvedGroupType -eq 'Distribution list' -or $ResolvedGroupType -eq 'Mail-Enabled Security') {
            $ExoBulkRequests = [System.Collections.Generic.List[object]]::new()
            $ExoLogs = [System.Collections.Generic.List[object]]::new()

            foreach ($User in $Users) {
                # Tag each operation so its result can be matched back exactly. New-ExoBulkRequest
                # stamps the OperationGuid onto both the error and the success record it returns.
                $OperationGuid = [Guid]::NewGuid().ToString()
                $Params = @{ Identity = $GroupId; Member = $User.body.userPrincipalName; BypassSecurityGroupManagerCheck = $true }
                $ExoBulkRequests.Add(@{
                        CmdletInput   = @{
                            CmdletName = 'Add-DistributionGroupMember'
                            Parameters = $Params
                        }
                        OperationGuid = $OperationGuid
                    })
                $ExoLogs.Add(@{
                        message       = "Added member $($User.body.userPrincipalName) to group $($GroupName)"
                        target        = $User.body.userPrincipalName
                        OperationGuid = $OperationGuid
                    })
            }

            if ($ExoBulkRequests.Count -gt 0) {
                $RawExoRequest = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray @($ExoBulkRequests)
                $ExoResults = Resolve-CippExoBulkResult -Response $RawExoRequest -Operations $ExoLogs

                foreach ($ExoResult in $ExoResults) {
                    if ($ExoResult.Success) {
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $ExoResult.Operation.message -Sev 'Info'
                        $SuccessfulUsers.Add($ExoResult.Operation.target)
                    } else {
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to add member $($ExoResult.Operation.target) to group $($GroupName): $($ExoResult.ErrorMessage)" -Sev 'Error'
                        $FailedUsers.Add("$($ExoResult.Operation.target) ($($ExoResult.ErrorMessage))")
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
