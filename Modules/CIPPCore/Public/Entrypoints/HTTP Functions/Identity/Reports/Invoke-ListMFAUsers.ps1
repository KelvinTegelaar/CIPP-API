function Invoke-ListMFAUsers {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $UseReportDB = $Request.Query.UseReportDB

    try {
        # If UseReportDB is specified, retrieve from report database
        if ($UseReportDB -eq 'true') {
            try {
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
                    $_ | Add-Member -NotePropertyName FunctionName -NotePropertyValue 'ListMFAUsersQueue'
                    $_ | Add-Member -NotePropertyName QueueId -NotePropertyValue $Queue.RowKey
                    $_
                }
                if (($Batch | Measure-Object).Count -gt 0) {
                    $InputObject = [PSCustomObject]@{
                        OrchestratorName = 'ListMFAUsersOrchestrator'
                        Batch            = @($Batch)
                        SkipLog          = $true
                    }
                    #Write-Host ($InputObject | ConvertTo-Json)
                    $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
                    Write-Host "Started permissions orchestration with ID = '$InstanceId'"
                }
            } else {
                $Rows = foreach ($Row in $Rows) {
                    if ($Row.CAPolicies -and $Row.CAPolicies -is [string]) {
                        $Row.CAPolicies = try { $Row.CAPolicies | ConvertFrom-Json } catch { @() }
                    } elseif (-not $Row.CAPolicies) {
                        $Row.CAPolicies = @()
                    }
                    if ($Row.MFAMethods -and $Row.MFAMethods -is [string]) {
                        $Row.MFAMethods = try { $Row.MFAMethods | ConvertFrom-Json } catch { @() }
                    } elseif (-not $Row.MFAMethods) {
                        $Row.MFAMethods = @()
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
