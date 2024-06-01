using namespace System.Net

Function Invoke-ExecOneDriveShortCut {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    Try {
        $MessageResult = New-CIPPOneDriveShortCut -username $Request.body.username -userid $Request.body.userid -TenantFilter $Request.Body.TenantFilter -URL $Request.body.input -ExecutingUser $request.headers.'x-ms-client-principal'
        $Results = [pscustomobject]@{ 'Results' = "$MessageResult" }
    } catch {
        $Results = [pscustomobject]@{'Results' = "Onedrive Shortcut creation failed: $($_.Exception.Message)" }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
