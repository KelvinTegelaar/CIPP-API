function Remove-CIPPGroupMember(
    $Headers,
    [string]$GroupType,
    [string]$GroupId,
    [string]$Member,
    [string]$TenantFilter,
    [string]$APIName = 'Remove Group Member'
) {
    try {
        if ($Member -like '*#EXT#*') { $Member = [System.Web.HttpUtility]::UrlEncode($Member) }
        # $MemberIDs = 'https://graph.microsoft.com/v1.0/directoryObjects/' + (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($Member)" -tenantid $TenantFilter).id
        # $AddMemberBody = "{ `"members@odata.bind`": $(ConvertTo-Json @($MemberIDs)) }"
        if ($GroupType -eq 'Distribution list' -or $GroupType -eq 'Mail-Enabled Security') {
            $Params = @{ Identity = $GroupId; Member = $Member; BypassSecurityGroupManagerCheck = $true }
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-DistributionGroupMember' -cmdParams $Params -UseSystemMailbox $true
        } else {
            $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/groups/$($GroupId)/members/$($Member)/`$ref" -tenantid $TenantFilter -type DELETE -body '{}' -Verbose
        }
        $Results = "Successfully removed user $($Member) from $($GroupId)."
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev Info
        return $Results

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to remove user $($Member) from $($GroupId): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev Error -LogData $ErrorMessage
        throw $Results
    }
}
