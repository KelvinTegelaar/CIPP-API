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

    if ($Request.Query.LogId) {
        $FilterConditions.Add("RowKey eq '$($Request.Query.LogId)'")
    } else {
        if ($TenantFilter -and $TenantFilter -ne 'AllTenants') {
            $FilterConditions.Add("Tenant eq '$TenantFilter'")
        }

        if (!$Request.Query.StartDate -and !$Request.Query.EndDate -and !$Request.Query.RelativeTime) {
            $Request.Query.StartDate = (Get-Date).AddDays(-7).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            $Request.Query.EndDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        }

        if ($Request.Query.RelativeTime) {
            $RelativeTime = $Request.Query.RelativeTime

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
            if ($Request.Query.StartDate) {
                if ($Request.Query.StartDate -match '^\d+$') {
                    $StartDate = [DateTimeOffset]::FromUnixTimeSeconds([int]$Request.Query.StartDate).DateTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                } else {
                    $StartDate = (Get-Date $Request.Query.StartDate).ToString('yyyy-MM-ddTHH:mm:ssZ')
                }
                $FilterConditions.Add("Timestamp ge datetime'$StartDate'")

                if ($Request.Query.EndDate) {
                    if ($Request.Query.EndDate -match '^\d+$') {
                        $EndDate = [DateTimeOffset]::FromUnixTimeSeconds([int]$Request.Query.EndDate).DateTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                    } else {
                        $EndDate = (Get-Date $Request.Query.EndDate).ToString('yyyy-MM-ddTHH:mm:ssZ')
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
    $AuditLogs = Get-CIPPAzDataTableEntity @Table | ForEach-Object {
        $_.Data = try { $_.Data | ConvertFrom-Json } catch { $_.AuditData }
        $_ | Select-Object @{n = 'LogId'; exp = { $_.RowKey } }, @{ n = 'Timestamp'; exp = { $_.Data.RawData.CreationTime } }, Tenant, Title, Data
    }

    $Body = @{
        Results  = @($AuditLogs)
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
