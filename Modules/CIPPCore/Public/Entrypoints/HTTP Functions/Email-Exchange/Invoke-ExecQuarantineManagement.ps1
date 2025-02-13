using namespace System.Net

Function Invoke-ExecQuarantineManagement {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'


    # Interact with query parameters or the body of the request.
    Try {
        $TenantFilter = $Request.Body.tenantFilter
        $params = @{
            Identity     = $Request.Body.Identity
            AllowSender  = [boolean]$Request.Body.AllowSender
            ReleaseToAll = [boolean]$Request.Body.Type
            ActionType   = $Request.Body.Type
        }

        New-ExoRequest -tenantid $TenantFilter -cmdlet 'Release-QuarantineMessage' -cmdParams $Params
        $Results = [pscustomobject]@{'Results' = "Successfully processed $($Request.Body.Identity)" }
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $TenantFilter -message "Successfully processed Quarantine ID $($Request.Body.Identity)" -Sev 'Info'
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $TenantFilter -message "Quarantine Management failed: $($_.Exception.Message)" -Sev 'Error' -LogData $_
        $Results = [pscustomobject]@{'Results' = "Failed. $($_.Exception.Message)" }
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
