using namespace System.Net

Function Invoke-ExecResetMFA {
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

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $UserID = $Request.Query.ID
    try {
        Write-Host "Getting auth methods for $UserID"
        $AuthMethods = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$UserID/authentication/methods" -tenantid $TenantFilter -AsApp $true
        $Requests = [System.Collections.Generic.List[object]]::new()
        foreach ($Method in $AuthMethods) {
            if ($Method.'@odata.type' -and $Method.'@odata.type' -ne '#microsoft.graph.passwordAuthenticationMethod') {
                $MethodType = ($Method.'@odata.type' -split '\.')[-1] -replace 'Authentication', ''
                $Requests.Add(@{
                        id     = "$MethodType-$($Method.id)"
                        method = 'DELETE'
                        url    = ('users/{0}/authentication/{1}s/{2}' -f $UserID, $MethodType, $Method.id)
                    })
            }
        }
        if (($Requests | Measure-Object).Count -eq 0) {
            $Results = [pscustomobject]@{'Results' = "No MFA methods found for user $($Request.Query.ID)" }
            Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = $Results
                })
            return
        }

        $Results = New-GraphBulkRequest -Requests $Requests -tenantid $TenantFilter -asapp $true -erroraction stop


        if ($Results.status -eq 204) {
            $Results = [pscustomobject]@{'Results' = "Successfully completed request. User $($Request.Query.ID) must supply MFA at next logon" }
        } else {
            $FailedAuthMethods = (($Results | Where-Object { $_.status -ne 204 }).id -split '-')[0] -join ', '
            $Results = [pscustomobject]@{'Results' = "Failed to reset MFA methods for $FailedAuthMethods" }
        }
    } catch {
        $Results = [pscustomobject]@{'Results' = "Failed to reset MFA methods for $($Request.Query.ID): $(Get-NormalizedError -message $_.Exception.Message)" }
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to reset MFA for user $($Request.Query.ID): $($_.Exception.Message)" -Sev 'Error' -LogData (Get-CippException -Exception $_)
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
