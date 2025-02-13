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
    Write-LogMessage -headers $Request.Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    try {

        $listType = switch -Wildcard ($request.body.entries) {
            '*@*' { 'Sender'; break }
            '*.*' { 'Url'; break }
            default { 'FileHash' }
        }
        Write-Host "List type is $listType"
        $ExoRequest = @{
            tenantid  = $Request.body.tenantfilter
            cmdlet    = 'Remove-TenantAllowBlockListItems'
            cmdParams = @{
                Entries  = @($Request.body.entries)
                ListType = $ListType
            }
        }

        $Results = New-ExoRequest @ExoRequest
        Write-Host $Results

        $result = "Successfully removed $($Request.body.entries) from Block/Allow list"
        Write-LogMessage -headers $Request.Headers -API $APIName -tenant $Request.query.tenantfilter -message $result -Sev 'Info'
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $result = "Failed to remove $($Request.body.entries). Error: $ErrorMessage"
        Write-LogMessage -headers $Request.Headers -API $APIName -tenant $Request.query.tenantfilter -message $result -Sev 'Error'
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{
                'Results' = $result
                'Request' = $ExoRequest
            }
        })
}
