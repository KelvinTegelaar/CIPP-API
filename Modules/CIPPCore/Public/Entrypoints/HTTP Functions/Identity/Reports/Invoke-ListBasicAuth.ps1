using namespace System.Net

Function Invoke-ListBasicAuth {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.AuditLog.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # XXX; This function seems to be unused in the frontend. -Bobby


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $currentTime = Get-Date -Format 'yyyy-MM-ddTHH:MM:ss'
    $ts = (Get-Date).AddDays(-30)
    $endTime = $ts.ToString('yyyy-MM-ddTHH:MM:ss')
    ##Create Filter for basic auth sign-ins
    $filters = "createdDateTime ge $($endTime)Z and createdDateTime lt $($currentTime)Z and (clientAppUsed eq 'AutoDiscover' or clientAppUsed eq 'Exchange ActiveSync' or clientAppUsed eq 'Exchange Online PowerShell' or clientAppUsed eq 'Exchange Web Services' or clientAppUsed eq 'IMAP4' or clientAppUsed eq 'MAPI Over HTTP' or clientAppUsed eq 'Offline Address Book' or clientAppUsed eq 'Outlook Anywhere (RPC over HTTP)' or clientAppUsed eq 'Other clients' or clientAppUsed eq 'POP3' or clientAppUsed eq 'Reporting Web Services' or clientAppUsed eq 'Authenticated SMTP' or clientAppUsed eq 'Outlook Service')"
    if ($TenantFilter -ne 'AllTenants') {

        try {
            $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/auditLogs/signIns?api-version=beta&filter=$($filters)" -tenantid $TenantFilter -ErrorAction Stop | Select-Object userPrincipalName, clientAppUsed, Status | Sort-Object -Unique -Property userPrincipalName
            $response = $GraphRequest
            Write-LogMessage -headers $Headers -API $APIName -message 'Retrieved basic authentication report' -Sev 'Debug' -tenant $TenantFilter

            # Associate values to output bindings by calling 'Push-OutputBinding'.
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = @($response)
                })
        } catch {
            Write-LogMessage -headers $Headers -API $APIName -message "Failed to retrieve basic authentication report: $($_.Exception.message) " -Sev 'Error' -tenant $TenantFilter
            # Associate values to output bindings by calling 'Push-OutputBinding'.
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = '500'
                    Body       = $(Get-NormalizedError -message $_.Exception.message)
                })
        }
    } else {
        $Table = Get-CIPPTable -TableName cachebasicauth
        $Rows = Get-CIPPAzDataTableEntity @Table | Where-Object -Property Timestamp -GT (Get-Date).AddHours(-1)
        if (!$Rows) {
            $TenantList = Get-Tenants -IncludeErrors
            $Queue = New-CippQueueEntry -Name 'Basic Auth - All Tenants' -TotalTasks ($TenantList | Measure-Object).Count
            $InputObject = [PSCustomObject]@{
                OrchestratorName = 'BasicAuthOrchestrator'
                QueueId          = $Queue.RowKey
                QueueFunction    = @{
                    FunctionName = 'GetTenants'
                    TenantParams = @{
                        IncludeErrors = $true
                    }
                    DurableName  = 'ListBasicAuthAllTenants'
                }
                SkipLog          = $true
            }
            Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)

            $GraphRequest = [PSCustomObject]@{
                MetaData = 'Loading data for all tenants. Please check back in 10 minutes'
            }

            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = @($GraphRequest)
                })
        } else {
            $GraphRequest = $Rows
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = @($GraphRequest)
                })
        }
    }

}
