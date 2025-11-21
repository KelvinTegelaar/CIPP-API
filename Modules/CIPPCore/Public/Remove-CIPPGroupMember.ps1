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
        $Requests = foreach ($m in $Member) {
            if ($m -like '*#EXT#*') { $m = [System.Web.HttpUtility]::UrlEncode($m) }
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
                            CmdletName = 'Remove-DistributionGroupMember'
                            Parameters = $Params
                        }
                    })
                $ExoLogs.Add(@{
                        message = "Removed member $($User.body.userPrincipalName) from $($GroupId) group"
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
            $RemovalRequests = foreach ($User in $Users) {
                @{
                    id     = $User.body.id
                    method = 'DELETE'
                    url    = "/groups/$($GroupId)/members/$($User.body.id)/`$ref"
                }
            }
            $RemovalResults = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($RemovalRequests)
            foreach ($Result in $RemovalResults) {
                if ($Result.status -ne 204) {
                    throw "Failed to remove member $($Result.id): $($Result.body.error.message)"
                }
            }
        }
        $UserList = ($Users.body.userPrincipalName -join ', ')
        $Results = "Successfully removed user $UserList from $($GroupId)."
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev Info
        return $Results

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $UserList = if ($Users) { ($Users.body.userPrincipalName -join ', ') } else { ($Member -join ', ') }
        $Results = "Failed to remove user $UserList from $($GroupId): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev Error -LogData $ErrorMessage
        throw $Results
    }
}
