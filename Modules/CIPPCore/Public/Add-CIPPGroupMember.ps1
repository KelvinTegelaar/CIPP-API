function Add-CIPPGroupMember(
    [string]$ExecutingUser,
    [string]$GroupType, 
    [string]$GroupId,
    [string]$Member, 
    [string]$TenantFilter,
    [string]$APIName = 'Add Group Member'
) {
    try {
        if ($member -like '*#EXT#*') { $member = [System.Web.HttpUtility]::UrlEncode($member) }
        $MemberIDs = 'https://graph.microsoft.com/v1.0/directoryObjects/' + (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($member)" -tenantid $TenantFilter).id 
        $addmemberbody = "{ `"members@odata.bind`": $(ConvertTo-Json @($MemberIDs)) }"
        if ($GroupType -eq 'Distribution list' -or $GroupType -eq 'Mail-Enabled Security') {
            $Params = @{ Identity = $GroupId; Member = $member; BypassSecurityGroupManagerCheck = $true }
            New-ExoRequest -tenantid $TenantFilter -cmdlet 'Add-DistributionGroupMember' -cmdParams $params -UseSystemMailbox $true 
        } else {
            New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($GroupId)" -tenantid $TenantFilter -type patch -body $addmemberbody -Verbose
        }
        $Message = "Successfully added user $($Member) to $($GroupId)."
        Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
        return $message
        return
    } catch {
        $message = "Failed to add user $($Member) to $($GroupId): $($_.Exception.Message)"
        Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message $message -Sev 'error'
        return $message 
    }

}
