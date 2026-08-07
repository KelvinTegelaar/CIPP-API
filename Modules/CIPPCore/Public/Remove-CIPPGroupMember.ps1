function Remove-CIPPGroupMember {
    <#
    .SYNOPSIS
    Removes members from a Microsoft 365 group.

    .DESCRIPTION
    Removes one or more members from Security Groups, Distribution Groups, or Mail-Enabled Security Groups.
    Uses bulk request operations for Exchange groups to improve performance.

    .PARAMETER Headers
    The headers for the API request, typically containing authentication information.

    .PARAMETER TenantFilter
    The tenant identifier for the target tenant.

    .PARAMETER GroupType
    The type of group. Valid values: 'Distribution list', 'Mail-Enabled Security', or standard security groups.

    .PARAMETER GroupId
    The unique identifier (GUID or name) of the group.

    .PARAMETER Member
    An array of member identifiers (user GUIDs or UPNs) to remove from the group.

    .PARAMETER APIName
    The API operation name for logging purposes. Default: 'Remove Group Member'.

    .EXAMPLE
    Remove-CIPPGroupMember -Headers $Headers -TenantFilter 'contoso.onmicrosoft.com' -GroupType 'Distribution list' -GroupId 'Sales-DL' -Member @('user1@contoso.com', 'user2@contoso.com') -APIName 'Remove DL Members'

    .EXAMPLE
    Remove-CIPPGroupMember -Headers $Headers -TenantFilter 'contoso.onmicrosoft.com' -GroupType 'Security' -GroupId '12345-guid' -Member @('user1-guid')
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
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
        # Same routing rule as Add-CIPPGroupMember: Graph cannot change membership on a classic
        # distribution list or a mail-enabled security group, so trust what Graph says the group is
        # rather than the type the caller happened to pass in.
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
                            CmdletName = 'Remove-DistributionGroupMember'
                            Parameters = $Params
                        }
                        OperationGuid = $OperationGuid
                    })
                $ExoLogs.Add(@{
                        message       = "Removed member $($User.body.userPrincipalName) from group $($GroupName)"
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
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to remove member $($ExoResult.Operation.target) from group $($GroupName): $($ExoResult.ErrorMessage)" -Sev 'Error'
                        $FailedUsers.Add("$($ExoResult.Operation.target) ($($ExoResult.ErrorMessage))")
                    }
                }
            }
        } else {
            $RemovalRequests = foreach ($User in $Users) {
                @{
                    id     = $User.body.id
                    method = 'DELETE'
                    url    = "/groups/$($GroupId)/members/$($User.body.id)/`$ref"
                }
            }
            $RemovalResults = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($RemovalRequests)
            foreach ($Result in $RemovalResults) {
                $UserPrincipalName = ($Users | Where-Object { $_.body.id -eq $Result.id }).body.userPrincipalName
                if ($Result.status -lt 200 -or $Result.status -gt 299) {
                    # Select-Object -First 1: Get-NormalizedError can return multiple strings
                    # when a message matches more than one of its translation patterns.
                    $ErrorText = Get-NormalizedError -message ($Result.body.error.message ?? "Request failed with status $($Result.status)") | Select-Object -First 1
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to remove member $UserPrincipalName from group $($GroupName): $ErrorText" -Sev 'Error'
                    $FailedUsers.Add("$UserPrincipalName ($ErrorText)")
                } else {
                    $SuccessfulUsers.Add($UserPrincipalName)
                }
            }
        }
        $Messages = [System.Collections.Generic.List[string]]::new()
        if ($SuccessfulUsers.Count -gt 0) {
            $Messages.Add("Successfully removed user $($SuccessfulUsers -join ', ') from group $($GroupName).")
        }
        if ($FailedUsers.Count -gt 0) {
            $Messages.Add("Failed to remove $($FailedUsers -join '; ').")
        }
        $Results = $Messages -join ' '
        if ($SuccessfulUsers.Count -eq 0 -and $FailedUsers.Count -gt 0) {
            throw $Results
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev Info
        return $Results

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $UserList = if ($Users) { ($Users.body.userPrincipalName -join ', ') } else { ($Member -join ', ') }
        $Results = "Failed to remove user $UserList from group $($GroupName ?? $GroupId): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev Error -LogData $ErrorMessage
        throw $Results
    }
}
