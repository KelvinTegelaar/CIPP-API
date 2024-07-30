function Invoke-ListAuditLogs {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Alert.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = 'ListAuditLogs'
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $TenantFilter = $Request.Query.TenantFilter
    $FilterConditions = [System.Collections.Generic.List[string]]::new()
    if ($TenantFilter) {
        $FilterConditions.Add("Tenant eq '$TenantFilter'")
    }

    if ($Request.Query.RelativeTime) {
        $RelativeTime = $Request.Query.RelativeTime

        if ($RelativeTime -match '(\d+)([dhm])') {
            $EndDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            switch ($Matches[2]) {
                'd' { $StartDate = (Get-Date).AddDays(-$Matches[1]).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
                'h' { $StartDate = (Get-Date).AddHours(-$Matches[1]).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
                'm' { $StartDate = (Get-Date).AddMinutes(-$Matches[1]).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
            }
        }
        $FilterConditions.Add("Timestamp ge '$StartDate' and Timestamp le '$EndDate'")
    } else {
        if ($Request.Query.StartDate) {
            if ($Request.Query.StartDate -match '^\d+$') {
                $Request.Query.StartDate = [DateTimeOffset]::FromUnixTimeSeconds($Request.Query.StartDate).DateTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            } else {
                $StartDate = (Get-Date $Request.Query.StartDate).ToString('yyyy-MM-ddTHH:mm:ssZ')
            }
            $FilterConditions.Add("Timestamp ge '$StartDate'")

            if ($Request.Query.EndDate) {
                if ($Request.Query.EndDate -match '^\d+$') {
                    $Request.Query.EndDate = [DateTimeOffset]::FromUnixTimeSeconds($Request.Query.EndDate).DateTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                } else {
                    $EndDate = (Get-Date $Request.Query.EndDate).ToString('yyyy-MM-ddTHH:mm:ssZ')
                }
                $FilterConditions.Add("Timestamp le '$EndDate'")
            }
        }
    }

    $Table = Get-CIPPTable -TableName 'AuditLogs'
    if ($FilterConditions) {
        $Table.Filter = $FilterConditions -join ' and '
    }
    $AuditLogs = Get-CIPPAzDataTableEntity @Table | ForEach-Object {
        $_.Data = try { $_.Data | ConvertFrom-Json } catch { $_.AuditData }
        $_
    }

    $Body = @{
        Results  = $AuditLogs
        Metadata = @{
            Count  = $AuditLogs.Count
            Filter = $Table.Filter ?? ''
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
