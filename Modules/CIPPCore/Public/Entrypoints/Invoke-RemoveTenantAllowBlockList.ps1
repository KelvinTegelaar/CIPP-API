using namespace System.Net

Function Invoke-RemoveTenantAllowBlockList {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.ReadWrite
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
    } catch {
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
