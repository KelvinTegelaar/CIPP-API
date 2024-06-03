using namespace System.Net

Function Invoke-AddTenantAllowBlockList {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $blocklistobj = $Request.body

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    try {
        $ExoRequest = @{
            tenantid  = $Request.body.tenantid
            cmdlet    = 'New-TenantAllowBlockListItems'
            cmdParams = @{
                Entries                  = [string[]]$blocklistobj.entries
                ListType                 = [string]$blocklistobj.listType
                Notes                    = [string]$blocklistobj.notes
                $blocklistobj.listMethod = [bool]$true
            }
        }

        if ($blocklistobj.NoExpiration -eq $true) {
            $ExoRequest.cmdParams.NoExpiration = $true
        }

        New-ExoRequest @ExoRequest

        $result = "Successfully added $($blocklistobj.Entries) as type $($blocklistobj.ListType) to the $($blocklistobj.listMethod) list"
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APIName -tenant $Request.body.tenantid -message $result -Sev 'Info'
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $result = "Failed to create blocklist. Error: $ErrorMessage"
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APIName -tenant $Request.body.tenantid -message $result -Sev 'Error'
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
