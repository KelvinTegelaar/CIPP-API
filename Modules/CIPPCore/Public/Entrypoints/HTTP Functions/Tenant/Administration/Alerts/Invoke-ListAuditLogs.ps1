function Invoke-ListAuditLogs {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Alert.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $LogID = $Request.Query.LogId
    $StartDate = $Request.Query.StartDate
    $EndDate = $Request.Query.EndDate
    $RelativeTime = $Request.Query.RelativeTime
    $FilterConditions = [System.Collections.Generic.List[string]]::new()

    if ($LogID) {
        $FilterConditions.Add("RowKey eq '$($LogID)'")
    } else {
        if ($TenantFilter -and $TenantFilter -ne 'AllTenants') {
            $FilterConditions.Add("Tenant eq '$TenantFilter'")
        }

        if (!$StartDate -and !$EndDate -and !$RelativeTime) {
            $StartDate = (Get-Date).AddDays(-7).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            $EndDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        }

        if ($RelativeTime) {

            if ($RelativeTime -match '(\d+)([dhm])') {
                $EndDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                $Interval = [Int32]$Matches[1]
                switch ($Matches[2]) {
                    'd' { $StartDate = (Get-Date).AddDays(-$Interval).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
                    'h' { $StartDate = (Get-Date).AddHours(-$Interval).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
                    'm' { $StartDate = (Get-Date).AddMinutes(-$Interval).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
                }
            }
            $FilterConditions.Add("Timestamp ge datetime'$StartDate' and Timestamp le datetime'$EndDate'")
        } else {
            if ($StartDate) {
                if ($StartDate -match '^\d+$') {
                    $StartDate = [DateTimeOffset]::FromUnixTimeSeconds([int]$StartDate).DateTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                } else {
                    $StartDate = (Get-Date $StartDate).ToString('yyyy-MM-ddTHH:mm:ssZ')
                }
                $FilterConditions.Add("Timestamp ge datetime'$StartDate'")

                if ($EndDate) {
                    if ($EndDate -match '^\d+$') {
                        $EndDate = [DateTimeOffset]::FromUnixTimeSeconds([int]$EndDate).DateTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                    } else {
                        $EndDate = (Get-Date $EndDate).ToString('yyyy-MM-ddTHH:mm:ssZ')
                    }
                    $FilterConditions.Add("Timestamp le datetime'$EndDate'")
                }
            }
        }
    }

    $Table = Get-CIPPTable -TableName 'AuditLogs'
    if ($FilterConditions) {
        $Table.Filter = $FilterConditions -join ' and '
    }

    $Tenants = Get-Tenants -IncludeErrors

    $AuditLogs = Get-CIPPAzDataTableEntity @Table | Where-Object { $Tenants.defaultDomainName -contains $_.Tenant } | ForEach-Object {
        $_.Data = try { $_.Data | ConvertFrom-Json } catch { $_.AuditData }
        $_ | Select-Object @{n = 'LogId'; exp = { $_.RowKey } }, @{ n = 'Timestamp'; exp = { $_.Data.RawData.CreationTime } }, Tenant, Title, Data
    }

    $Body = @{
        Results  = @($AuditLogs | Sort-Object -Property Timestamp -Descending)
        Metadata = @{
            Count  = $AuditLogs.Count
            Filter = $Table.Filter ?? ''
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
