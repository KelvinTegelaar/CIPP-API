function Add-CIPPGroupMember(
    $Headers,
    [string]$GroupType,
    [string]$GroupId,
    [string]$Member,
    [string]$TenantFilter,
    [string]$APIName = 'Add Group Member'
) {
    try {
        if ($Member -like '*#EXT#*') { $Member = [System.Web.HttpUtility]::UrlEncode($Member) }
        $MemberIDs = 'https://graph.microsoft.com/v1.0/directoryObjects/' + (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($Member)" -tenantid $TenantFilter).id
        $AddMemberBody = "{ `"members@odata.bind`": $(ConvertTo-Json @($MemberIDs)) }"
        if ($GroupType -eq 'Distribution list' -or $GroupType -eq 'Mail-Enabled Security') {
            $Params = @{ Identity = $GroupId; Member = $Member; BypassSecurityGroupManagerCheck = $true }
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Add-DistributionGroupMember' -cmdParams $Params -UseSystemMailbox $true
        } else {
            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($GroupId)" -tenantid $TenantFilter -type patch -body $AddMemberBody -Verbose
        }
        $Results = "Successfully added user $($Member) to $($GroupId)."
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev 'Info'
        return $Results
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to add user $($Member) to $($GroupId) - $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev 'error' -LogData $ErrorMessage
        throw $Results
    }
}
