function Remove-CIPPGroupMember(
    [string]$ExecutingUser,
    [string]$GroupType, 
    [string]$GroupId,
    [string]$Member, 
    [string]$TenantFilter,
    [string]$APIName = 'Remove Group Member'
) {
    try {
        if ($member -like '*#EXT#*') { $member = [System.Web.HttpUtility]::UrlEncode($member) }
        $MemberIDs = 'https://graph.microsoft.com/v1.0/directoryObjects/' + (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($member)" -tenantid $TenantFilter).id 
        $addmemberbody = "{ `"members@odata.bind`": $(ConvertTo-Json @($MemberIDs)) }"
        if ($GroupType -eq 'Distribution list' -or $GroupType -eq 'Mail-Enabled Security') {
            $Params = @{ Identity = $GroupId; Member = $member; BypassSecurityGroupManagerCheck = $true }
            New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-DistributionGroupMember' -cmdParams $params -UseSystemMailbox $true 
        } else {
            New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($GroupId)/members/$($Member)/`$ref" -tenantid $TenantFilter -type DELETE -body '{}' -Verbose
        }
        $Message = "Successfully removed user $($Member) from $($GroupId)."
        Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
        return $message
    } catch {
        $message = "Failed to remove user $($Member) from $($GroupId): $($_.Exception.Message)"
        Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message $message -Sev 'error'
        return $message 
    }

}
