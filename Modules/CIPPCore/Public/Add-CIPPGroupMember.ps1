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

        $SuccessfulUsers = [System.Collections.Generic.List[string]]::new()
        $FailedUsers = [System.Collections.Generic.List[string]]::new()

        # Accept both human-readable labels (from Invoke-EditGroup / older callers) and
        # camelCase calculatedGroupType values (from the user template / add-edit-user form)
        $ExoGroupTypes = @('Distribution list', 'Distribution List', 'Mail-Enabled Security', 'distributionList', 'security')

        if ($GroupType -in $ExoGroupTypes) {
            $ExoBulkRequests = [System.Collections.Generic.List[object]]::new()
            $GuidToUpn = @{}

            foreach ($User in $Users) {
                $UserUpn = $User.body.userPrincipalName
                if (-not $UserUpn) { continue }
                $OpGuid = [guid]::NewGuid().ToString()
                $GuidToUpn[$OpGuid] = $UserUpn
                $Params = @{ Identity = $GroupId; Member = $UserUpn; BypassSecurityGroupManagerCheck = $true }
                $ExoBulkRequests.Add(@{
                        OperationGuid = $OpGuid
                        CmdletInput   = @{
                            CmdletName = 'Add-DistributionGroupMember'
                            Parameters = $Params
                        }
                    })
            }

            if ($ExoBulkRequests.Count -gt 0) {
                $RawExoRequest = @(New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray @($ExoBulkRequests))

                # Index responses by OperationGuid so each user is correlated by position, not by error.target
                $ResponseByGuid = @{}
                foreach ($Response in $RawExoRequest) {
                    if ($Response.OperationGuid) {
                        $ResponseByGuid[$Response.OperationGuid] = $Response
                    }
                }

                foreach ($OpGuid in $GuidToUpn.Keys) {
                    $UserUpn = $GuidToUpn[$OpGuid]
                    $Response = $ResponseByGuid[$OpGuid]

                    if ($Response -and $Response.error) {
                        $ErrorText = if ($Response.error -is [string]) { $Response.error } else { ($Response.error | Out-String).Trim() }
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to add member $($UserUpn) to $($GroupId): $ErrorText" -Sev 'Error'
                        $FailedUsers.Add($UserUpn)
                    } else {
                        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Added member $($UserUpn) to $($GroupId) group" -Sev 'Info'
                        $SuccessfulUsers.Add($UserUpn)
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
                $UserPrincipalName = $Users | Where-Object { $_.body.id -eq $Result.id } | Select-Object -ExpandProperty body | Select-Object -ExpandProperty userPrincipalName
                if ($Result.status -lt 200 -or $Result.status -gt 299) {
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to add member $($UserPrincipalName): $($Result.body.error.message)" -Sev 'Error'
                    $FailedUsers.Add($UserPrincipalName)
                } else {
                    $SuccessfulUsers.Add($UserPrincipalName)
                }
            }
        }

        if ($SuccessfulUsers.Count -eq 0 -and $FailedUsers.Count -gt 0) {
            $Results = "Failed to add user $($FailedUsers -join ', ') to $($GroupId)."
            throw $Results
        }

        $Results = "Successfully added user $($SuccessfulUsers -join ', ') to $($GroupId)."
        if ($FailedUsers.Count -gt 0) {
            $Results = "$Results Failed to add: $($FailedUsers -join ', ')."
        }
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
