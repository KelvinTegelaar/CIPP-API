using namespace System.Net

Function Invoke-ListMailboxRules {
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


    if (!$Rows) {
        Push-OutputBinding -Name mbxrulequeue -Value $TenantFilter
        $GraphRequest = [PSCustomObject]@{
            Tenant   = 'Loading data. Please check back in 1 minute'
            Licenses = 'Loading data. Please check back in 1 minute'
        }
    } else {
        if ($TenantFilter -ne 'AllTenants') {
            $Table = Get-CIPPTable -TableName cachembxrules
            $Rows = Get-CIPPAzDataTableEntity @Table | Where-Object -Property Timestamp -GT (Get-Date).Addhours(-1)
            $GraphRequest = $Rows | Where-Object -Property Tenant -EQ $TenantFilter | ForEach-Object {
                $NewObj = $_.Rules | ConvertFrom-Json
                $NewObj | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $TenantFilter
                $NewObj
            }
        } else {
            $GraphRequest = New-ExoRequest -tenantid $tenantFilter -cmdlet 'Get-Mailbox' -Select 'userPrincipalName,GUID' | ForEach-Object {
                New-ExoRequest -Anchor $_.UserPrincipalName -tenantid $tenantFilter -cmdlet 'Get-InboxRule' -cmdParams @{Mailbox = $_.GUID }
            }
        }
    }
    #Remove all old cache
    #Remove-AzDataTableEntity @Table -Entity (Get-CIPPAzDataTableEntity @Table -Property PartitionKey, RowKey, Timestamp | Where-Object -Property Timestamp -LT (Get-Date).AddMinutes(-15))


    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })

}
