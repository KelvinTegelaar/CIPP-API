using namespace System.Net

function Invoke-RemoveTenantAllowBlockList {
    <#
    .SYNOPSIS
    Remove items from tenant allow/block list for spam filtering
    
    .DESCRIPTION
    Removes specified items from the tenant allow/block list for spam filtering using Exchange Online PowerShell.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.ReadWrite
        
    .NOTES
    Group: Email & Exchange
    Summary: Remove Tenant Allow Block List
    Description: Removes specified items from the tenant allow/block list for spam filtering using Exchange Online PowerShell with logging of success and failure.
    Tags: Email,Exchange,Spam Filter,Allow Block List
    Parameter: tenantFilter (string) [body] - Target tenant identifier
    Parameter: Entries (array) [body] - Array of entries to remove from the list
    Parameter: ListType (string) [body] - Type of list (Sender, Url, FileHash, IP)
    Response: Returns an object with the following properties:
    Response: - Results (string): Success or error message
    Response: On success: "Successfully removed [entries] with type [ListType] from Block/Allow list" with HTTP 200 status
    Response: On error: Error message with HTTP 403 status
    Example: {
      "Results": "Successfully removed sender@example.com with type Sender from Block/Allow list"
    }
    Error: Returns error details if the operation fails to remove allow/block list items.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter
    $Entries = $Request.Body.Entries
    $ListType = $Request.Body.ListType

    try {

        Write-Host "List type is $listType"
        $ExoRequest = @{
            tenantid  = $TenantFilter
            cmdlet    = 'Remove-TenantAllowBlockListItems'
            cmdParams = @{
                Entries  = @($Entries)
                ListType = $ListType
            }
        }

        $Results = New-ExoRequest @ExoRequest
        Write-Host $Results

        $Result = "Successfully removed $($Entries) with type $ListType from Block/Allow list"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to remove $($Entries) type $ListType. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{
                'Results' = $Result
                # 'Request' = $ExoRequest
            }
        })
}
