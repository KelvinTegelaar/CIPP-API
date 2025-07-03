using namespace System.Net

function Invoke-ListTenantAllowBlockList {
    <#
    .SYNOPSIS
    List tenant allow/block list items for spam filtering
    
    .DESCRIPTION
    Retrieves tenant allow/block list items for spam filtering including sender, URL, file hash, and IP address lists using Exchange Online PowerShell.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.Read
        
    .NOTES
    Group: Email & Exchange
    Summary: List Tenant Allow Block List
    Description: Retrieves tenant allow/block list items for spam filtering including sender, URL, file hash, and IP address lists using Exchange Online PowerShell with parallel processing.
    Tags: Email,Exchange,Spam Filter,Allow Block List
    Parameter: tenantFilter (string) [query] - Target tenant identifier
    Response: Returns an array of allow/block list items with the following properties:
    Response: - ListType (string): Type of list (Sender, Url, FileHash, IP)
    Response: - Standard properties from Get-TenantAllowBlockListItems cmdlet
    Response: On success: Array of list items with HTTP 200 status
    Response: On error: Error message with HTTP 403 status
    Example: [
      {
        "ListType": "Sender",
        "Identity": "sender-123",
        "Address": "sender@example.com",
        "Entry": "sender@example.com",
        "ListSubType": "Sender",
        "Description": "Blocked sender"
      },
      {
        "ListType": "IP",
        "Identity": "ip-123",
        "IPAddress": "192.168.1.1",
        "Entry": "192.168.1.1",
        "ListSubType": "IP",
        "Description": "Blocked IP address"
      }
    ]
    Error: Returns error details if the operation fails to retrieve allow/block list items.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $ListTypes = 'Sender', 'Url', 'FileHash', 'IP'
    try {
        $Results = $ListTypes | ForEach-Object -Parallel {
            Import-Module CIPPCore
            $TempResults = New-ExoRequest -tenantid $using:TenantFilter -cmdlet 'Get-TenantAllowBlockListItems' -cmdParams @{ListType = $_ }
            $TempResults | Add-Member -MemberType NoteProperty -Name ListType -Value $_
            $TempResults | Select-Object -ExcludeProperty *'@data.type'*, *'(DateTime])'*
        } -ThrottleLimit 5

        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $Results = $ErrorMessage
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })
}
