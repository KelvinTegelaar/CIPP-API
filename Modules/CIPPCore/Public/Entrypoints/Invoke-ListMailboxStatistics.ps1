using namespace System.Net

Function Invoke-ListMailboxStatistics {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    try {

        $GraphRequest = if ($TenantFilter -ne 'AllTenants') {
            New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/getMailboxUsageDetail(period='D7')" -tenantid $TenantFilter | ConvertFrom-Csv | Select-Object @{ Name = 'UPN'; Expression = { $_.'User Principal Name' } },
            @{ Name = 'displayName'; Expression = { $_.'Display Name' } },
            @{ Name = 'MailboxType'; Expression = { $_.'Recipient Type' } },
            @{ Name = 'LastActive'; Expression = { $_.'Last Activity Date' } },
            @{ Name = 'UsedGB'; Expression = { [math]::round($_.'Storage Used (Byte)' / 1GB, 2) } },
            @{ Name = 'QuotaGB'; Expression = { [math]::round($_.'Prohibit Send/Receive Quota (Byte)' / 1GB, 2) } },
            @{ Name = 'ItemCount'; Expression = { $_.'Item Count' } },
            @{ Name = 'HasArchive'; Expression = { If (($_.'Has Archive').ToLower() -eq 'true') { [bool]$true } else { [bool]$false } } }
            $StatusCode = [HttpStatusCode]::OK
        } else {
            $Table = Get-CIPPTable -TableName 'cachereports'
            $Rows = Get-CIPPAzDataTableEntity @Table | Where-Object -Property Timestamp -GT (Get-Date).AddHours(-1)
            if (!$Rows) {
                $Queue = New-CippQueueEntry -Name 'Reports' -Link '/email/reports/mailbox-statistics?customerId=AllTenants'
                Push-OutputBinding -Name mailboxstats -Value "reports/getMailboxUsageDetail(period='D7')?`$format=application/json"
                [PSCustomObject]@{
                    Tenant = 'Loading data for all tenants. Please check back after the job completes'
                }
                $StatusCode = [HttpStatusCode]::OK
            } else {
                $Rows.Data | ConvertFrom-Json | Select-Object *, @{ Name = 'UPN'; Expression = { $_.'UserPrincipalName' } },
                @{ Name = 'MailboxType'; Expression = { $_.'RecipientType' } },
                @{ Name = 'LastActive'; Expression = { $_.'LastActivityDate' } },
                @{ Name = 'UsedGB'; Expression = { [math]::round($_.'storageUsedInBytes' / 1GB, 2) } },
                @{ Name = 'QuotaGB'; Expression = { [math]::round($_.'prohibitSendReceiveQuotaInBytes' / 1GB, 2) } }
                $StatusCode = [HttpStatusCode]::OK
            }
        }


    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        }) -clobber

}
