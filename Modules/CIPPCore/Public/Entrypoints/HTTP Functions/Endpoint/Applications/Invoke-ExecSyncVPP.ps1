function Invoke-ExecSyncVPP {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Application.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev Debug

    $TenantFilter = $Request.Body.tenantFilter ?? $Request.Query.tenantFilter
    try {
        # Get all VPP tokens and sync them
        $VppTokens = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceAppManagement/vppTokens' -tenantid $TenantFilter | Where-Object { $_.state -eq 'valid' }

        if ($null -eq $VppTokens -or $VppTokens.Count -eq 0) {
            $Result = 'No VPP tokens found'
            Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Info
        } else {
            $SyncCount = 0
            foreach ($Token in $VppTokens) {
                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceAppManagement/vppTokens/$($Token.id)/syncLicenses" -tenantid $TenantFilter
                $SyncCount++
            }
            $Result = "Successfully started VPP sync for $SyncCount tokens"
            Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Info
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = 'Failed to start VPP sync'
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })

}
