function Invoke-ListGraphReports {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Reports.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter
    $Type = $Request.Query.type ?? 'graph'
    $Report = $Request.Query.report
    $Period = $Request.Query.period ?? 'D30'

    if (-not $TenantFilter) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{ error = 'tenantFilter is required.' }
        }
    }

    $ValidTypes = @('graph', 'office')
    if ($Type -notin $ValidTypes) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{ error = "Invalid type '$Type'. Valid values: $($ValidTypes -join ', ')." }
        }
    }

    $ValidPeriods = @('D7', 'D30', 'D90', 'D180')
    if ($Period -notin $ValidPeriods) {
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{ error = "Invalid period '$Period'. Valid values: $($ValidPeriods -join ', ')." }
        }
    }

    try {
        if (-not $Report) {
            # Discovery mode — query the report roots to enumerate available reports
            if ($Type -eq 'office') {
                # reports.office.com OData service document returns an array of { name, kind, url }
                $TenantId = (Get-Tenants -TenantFilter $TenantFilter).customerId
                $ServiceDoc = New-GraphGetRequest -uri 'https://reports.office.com/odataux' -tenantid $TenantFilter -scope 'https://reports.office.com/.default'
                $Body = @($ServiceDoc | Select-Object name, kind, @{
                        Name       = 'uri'
                        Expression = { "https://reports.office.com/odataux/$($_.url)?tenantId=$TenantId" }
                    })
            } else {
                # GET /beta/reports returns function bindings as '#microsoft.graph.getFoo' keys
                # and navigation links as 'fooBar@navigationLink' keys
                # ConvertTo-Json/From-Json round-trip ensures we always get a single PSCustomObject
                $Raw = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/reports' -tenantid $TenantFilter -AsApp $true
                $RawObj = $Raw | ConvertTo-Json -Depth 5 -Compress | ConvertFrom-Json
                $Props = if ($RawObj) { $RawObj.PSObject.Properties.Name } else { @() }

                $Functions = $Props | Where-Object { $_ -like '#microsoft.graph.*' } | ForEach-Object {
                    $ReportName = $_ -replace '^#microsoft\.graph\.', ''
                    [pscustomobject]@{
                        name = $ReportName
                        type = 'function'
                        uri  = "https://graph.microsoft.com/beta/reports/$ReportName"
                    }
                }

                $NavLinks = $Props | Where-Object { $_ -like '*@navigationLink' } | ForEach-Object {
                    [pscustomobject]@{
                        name = $_ -replace '@navigationLink$', ''
                        type = 'navigationLink'
                        uri  = $RawObj.$_
                    }
                }

                $Body = @($Functions) + @($NavLinks) | Sort-Object name
            }
            $StatusCode = [HttpStatusCode]::OK
        } else {
            # Fetch mode — call the specified report and return JSON data
            if ($Type -eq 'office') {
                $TenantId = (Get-Tenants -TenantFilter $TenantFilter).customerId
                $Uri = "https://reports.office.com/odataux/$Report`?tenantId=$TenantId"
                Write-Information "Fetching office report: $Uri"
                $Data = New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -scope 'https://reports.office.com/.default'
            } else {
                # Most Graph usage reports are functions that require a period parameter.
                # Try period-based first, fall back to bare URI for navigation links / flat resources.
                $UriWithPeriod = "https://graph.microsoft.com/beta/reports/$Report(period='$Period')?`$format=application/json"
                try {
                    Write-Information "Fetching graph report: $UriWithPeriod"
                    $Data = New-GraphGetRequest -uri $UriWithPeriod -tenantid $TenantFilter -AsApp $true
                } catch {
                    $UriBare = "https://graph.microsoft.com/beta/reports/$Report"
                    Write-Information "Period-based fetch failed, retrying: $UriBare"
                    $Data = New-GraphGetRequest -uri $UriBare -tenantid $TenantFilter
                }
            }

            Write-LogMessage -headers $Headers -API $APIName -message "Retrieved report '$Report' for $TenantFilter" -Sev 'Info'
            $Body = @($Data)
            $StatusCode = [HttpStatusCode]::OK
        }
    } catch {
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to retrieve report: $($_.Exception.Message)" -Sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Body = @{ error = $_.Exception.Message }
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $Body
    }
}
