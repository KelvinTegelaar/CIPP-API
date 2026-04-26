function Set-CIPPDBCacheTeamsActivity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [string]$QueueId
    )

    try {
        $Type = 'TeamsUserActivityUser'
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Caching Teams activity: $Type" -sev Debug

        $TeamsActivity = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/get$($Type)Detail(period='D30')" -tenantid $TenantFilter | ConvertFrom-Csv | Select-Object @{ Name = 'UPN'; Expression = { $_.'User Principal Name' } },
        @{ Name = 'LastActive'; Expression = { $_.'Last Activity Date' } },
        @{ Name = 'TeamsChat'; Expression = { $_.'Team Chat Message Count' } },
        @{ Name = 'CallCount'; Expression = { $_.'Call Count' } },
        @{ Name = 'MeetingCount'; Expression = { $_.'Meeting Count' } }

        $DbType = "TeamsActivity$Type"
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type $DbType -Data @($TeamsActivity)
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type $DbType -Data @($TeamsActivity) -Count
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Teams activity: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}
