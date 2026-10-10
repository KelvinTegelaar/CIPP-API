function Get-CIPPPartnerUserLookup {
    <#
    .SYNOPSIS
        Returns the partner (CIPP) tenant's users as a hashtable keyed by object id.
    .DESCRIPTION
        Audit records in a customer tenant name a partner (GDAP) identity by its object id in the
        partner tenant: user_<id>@<tenant>.onmicrosoft.com in Entra records, and
        <customer>.onmicrosoft.com\tenant: <partner tenant id>, object: <id> in Exchange records. This
        lookup turns that id back into the partner user. The answer is the same for every tenant, so
        it is memoised per worker for five minutes and cached for a day in the cacheauditloglookups
        table (PartitionKey '_partner', RowKey 'users'), refreshed from Graph when both are stale.
        The audit-log pipeline (Test-CIPPAuditLogRules) and the BEC run share it.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    if ($null -eq $script:PartnerUserMemo -or $script:PartnerUserMemo.Expires -le [datetime]::UtcNow) {
        $script:PartnerUserMemo = [PSCustomObject]@{
            Expires = [datetime]::UtcNow.AddMinutes(5)
            Lookup  = $null
        }
    } elseif ($null -ne $script:PartnerUserMemo.Lookup) {
        return $script:PartnerUserMemo.Lookup
    }

    $Table = Get-CIPPTable -tablename 'cacheauditloglookups'
    $OneDayAgo = (Get-Date).AddDays(-1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $Cached = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '_partner' and RowKey eq 'users' and Timestamp gt datetime'$OneDayAgo'"
    $Lookup = if ($Cached -and $Cached.Format -eq 'hashtable') {
        ($Cached.Data | ConvertFrom-Json -ErrorAction SilentlyContinue -AsHashtable) ?? @{}
    } else {
        $PartnerUsers = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$select=id,displayName,userPrincipalName,accountEnabled&`$top=999" -AsApp $true -NoAuthCheck $true
        $Fresh = @{}
        foreach ($PartnerUser in $PartnerUsers) {
            if (![string]::IsNullOrEmpty($PartnerUser.id)) { $Fresh[$PartnerUser.id] = $PartnerUser }
        }
        Add-CIPPAzDataTableEntity @Table -Entity @{
            PartitionKey = '_partner'
            RowKey       = 'users'
            Data         = [string]($Fresh | ConvertTo-Json -Compress)
            Format       = 'hashtable'
        } -Force
        $Fresh
    }
    $script:PartnerUserMemo.Lookup = $Lookup
    Write-Information "Partner user hashtable: $($Lookup.Count) partner users"
    return $Lookup
}
