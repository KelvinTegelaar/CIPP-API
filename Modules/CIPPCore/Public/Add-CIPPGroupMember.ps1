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
        if ($Member -like '*#EXT#*') { $Member = [System.Web.HttpUtility]::UrlEncode($Member) }
        $ODataBindString = 'https://graph.microsoft.com/v1.0/directoryObjects/{0}'
        $Requests = foreach ($m in $Member) {
            @{
                id     = $m
                url    = "users/$($m)?`$select=id,userPrincipalName"
                method = 'GET'
            }
        }
        $Users = New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter

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
                        message = "Added member $($User.body.userPrincipalName) to $($GroupId) group"
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
            $SuccessfulUsers = [system.collections.generic.list[string]]::new()
            foreach ($Result in $AddResults) {
                if ($Result.status -lt 200 -or $Result.status -gt 299) {
                    $FailedUsername = $Users | Where-Object { $_.body.id -eq $Result.id } | Select-Object -ExpandProperty body | Select-Object -ExpandProperty userPrincipalName
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to add member $($FailedUsername): $($Result.body.error.message)" -Sev 'Error'
                } else {
                    $UserPrincipalName = $Users | Where-Object { $_.body.id -eq $Result.id } | Select-Object -ExpandProperty body | Select-Object -ExpandProperty userPrincipalName
                    $SuccessfulUsers.Add($UserPrincipalName)
                }
            }
        }
        $UserList = ($SuccessfulUsers -join ', ')
        $Results = "Successfully added user $UserList to $($GroupId)."
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev 'Info'
        return $Results
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $UserList = if ($Users) { ($Users.body.userPrincipalName -join ', ') } else { ($Member -join ', ') }
        $Results = "Failed to add user $UserList to $($GroupId) - $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev 'error' -LogData $ErrorMessage
        throw $Results
    }
}
