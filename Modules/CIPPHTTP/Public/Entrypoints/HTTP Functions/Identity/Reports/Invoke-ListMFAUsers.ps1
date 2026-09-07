function Invoke-ListMFAUsers {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    .DESCRIPTION
        Lists users and their MFA registration status for a tenant. Supports UseReportDB=true query parameter to retrieve cached data from the reporting database for significantly better performance, especially when querying AllTenants. When manualPagination is also set, one page is returned per request as { Results, Metadata } with a continuation token in Metadata.nextLink.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    # Serve from the reporting database cache instead of live Graph. Much faster, especially for AllTenants.
    $UseReportDB = $Request.Query.UseReportDB -eq $true
    # Return one page per request as { Results, Metadata } with a continuation token in Metadata.nextLink; cached reads only.
    $ManualPagination = $Request.Query.manualPagination -and [System.Convert]::ToBoolean($Request.Query.manualPagination)
    try {
        # If UseReportDB is specified, retrieve from report database
        if ($UseReportDB) {
            try {
                if ($ManualPagination) {
                    # Rows per page, clamped between 250 and 10000. Defaults to 5000.
                    $PageSize = 5000
                    if ($Request.Query.PageSize -as [int]) {
                        $PageSize = [Math]::Min([Math]::Max([int]$Request.Query.PageSize, 250), 10000)
                    }
                    # Continuation token from the previous page's Metadata.nextLink; opaque to callers.
                    $Page = Get-CIPPMFAStateReport -TenantFilter $TenantFilter -PageSize $PageSize -ContinuationToken $Request.Query.nextLink -ErrorAction Stop
                    $Metadata = @{}
                    if ($Page.NextToken) { $Metadata.nextLink = $Page.NextToken }
                    return ([HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::OK
                            Body       = [PSCustomObject]@{
                                Results  = @($Page.Items)
                                Metadata = $Metadata
                            }
                        })
                }
                $GraphRequest = Get-CIPPMFAStateReport -TenantFilter $TenantFilter -ErrorAction Stop
                $StatusCode = [HttpStatusCode]::OK
            } catch {
                Write-Host "Error retrieving MFA state from report database: $($_.Exception.Message)"
                $StatusCode = [HttpStatusCode]::InternalServerError
                $GraphRequest = $_.Exception.Message
            }

            return ([HttpResponseContext]@{
                    StatusCode = $StatusCode
                    Body       = @($GraphRequest)
                })
        }

        # Original cache table logic
        if ($TenantFilter -ne 'AllTenants') {
            $GraphRequest = Get-CIPPMFAState -TenantFilter $TenantFilter
        } else {
            $Table = Get-CIPPTable -TableName cachemfa

            $Rows = Get-CIPPAzDataTableEntity @Table | Where-Object -Property Timestamp -GT (Get-Date).AddHours(-2)
            if (!$Rows) {
                $TenantList = Get-Tenants -IncludeErrors
                $Queue = New-CippQueueEntry -Name 'MFA Users - All Tenants' -Link '/identity/reports/mfa-report?customerId=AllTenants' -TotalTasks ($TenantList | Measure-Object).Count
                Write-Information ($Queue | ConvertTo-Json)
                $GraphRequest = [PSCustomObject]@{
                    UPN = 'Loading data for all tenants. Please check back in a few minutes'
                }
                $Batch = $TenantList | ForEach-Object {
                    $_ | Add-Member -NotePropertyMembers ([ordered]@{
                            FunctionName = 'ListMFAUsersQueue'
                            QueueId      = $Queue.RowKey
                        })
                    $_
                }
                if (($Batch | Measure-Object).Count -gt 0) {
                    $InputObject = [PSCustomObject]@{
                        OrchestratorName = 'ListMFAUsersOrchestrator'
                        Batch            = @($Batch)
                        SkipLog          = $true
                    }
                    #Write-Host ($InputObject | ConvertTo-Json)
                    Start-CIPPOrchestrator -InputObject $InputObject

                }
            } else {
                Write-Information 'Getting cached MFA state for all tenants'
                Write-Information "Found $($Rows.Count) rows in cache"
                $Rows = $Rows | Select-CippAllowedTenantData -TenantProperty 'Tenant'
                $Rows = foreach ($Row in $Rows) {
                    if ($Row.CAPolicies -and $Row.CAPolicies -is [string]) {
                        $Row.CAPolicies = try { $Row.CAPolicies | ConvertFrom-Json -ErrorAction Stop } catch { @() }
                    } elseif (-not $Row.CAPolicies) {
                        $Row | Add-Member -NotePropertyName CAPolicies -NotePropertyValue @() -Force
                    }
                    if ($Row.MFAMethods -and $Row.MFAMethods -is [string]) {
                        $Row.MFAMethods = try { $Row.MFAMethods | ConvertFrom-Json -ErrorAction Stop } catch { @() }
                    } elseif (-not $Row.MFAMethods) {
                        $Row | Add-Member -NotePropertyName MFAMethods -NotePropertyValue @() -Force
                    }
                    $Row
                }
                $GraphRequest = $Rows
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })


}
