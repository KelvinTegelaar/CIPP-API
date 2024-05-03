using namespace System.Net

Function Invoke-AddTenantAllowBlockList {
    <#
    .FUNCTIONALITY
    Entrypoint
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
                Entries                     = [string[]]$blocklistobj.entries
                ListType                    = [string]$blocklistobj.listType
                Notes                       = [string]$blocklistobj.notes
                $blocklistobj.listMethod    = [bool]$true
            }
        }

        if ($blocklistobj.NoExpiration -eq $true) {
            $ExoRequest.cmdParams.NoExpiration = $true
        }

        New-ExoRequest @ExoRequest

        $result = "Successfully added $($blocklistobj.Entries) as type $($blocklistobj.ListType) to the $($blocklistobj.listMethod) list"

        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APIName -tenant $Request.body.tenantid -message "Added $($blocklistobj.Entries) as type $($blocklistobj.ListType) to the $($blocklistobj.listMethod) list" -Sev 'Info'
    } catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APIName -tenant $Request.body.tenantid -message "Blocklist creation API failed. $($_.Exception.Message)" -Sev 'Error'
        $result = "Failed to create blocklist. $($_.Exception.Message)"
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
