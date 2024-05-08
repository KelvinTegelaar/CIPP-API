using namespace System.Net

Function Invoke-RemoveTenantAllowBlockList {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    try {
        $ExoRequest = @{
            tenantid  = $Request.query.tenantfilter
            cmdlet    = 'Remove-TenantAllowBlockListItems'
            cmdParams = @{
                Entries     = [string[]]$Request.query.entries
                ListType    = [string]$Request.query.listType
            }
        }

        New-ExoRequest @ExoRequest

        $result = "Successfully Removed $($Request.query.Entries) from Block/Allow list"

        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APIName -tenant $Request.query.tenantfilter -message "Removed $($Request.query.Entries) from Block/Allow list" -Sev 'Info'
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APIName -tenant $Request.query.tenantfilter -message "Blocklist removal API failed. $($_.Exception.Message)" -Sev 'Error'
        $result = "Failed to remove $($Request.query.Entries). $($_.Exception.Message)"
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
