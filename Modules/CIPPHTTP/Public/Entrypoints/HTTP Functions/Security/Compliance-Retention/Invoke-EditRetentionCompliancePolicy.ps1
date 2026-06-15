Function Invoke-EditRetentionCompliancePolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.RetentionCompliancePolicy.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $Identity = $Request.Query.Identity ?? $Request.Body.Identity ?? $Request.Body.Name
    $State = $Request.Query.State ?? $Request.Body.State

    try {
        $Params = @{
            Identity = $Identity
        }

        if ($State) {
            $Params['Enabled'] = ($State -eq 'enable' -or $State -eq $true -or $State -eq 'true')
        }

        if ($Request.Body.parameters) {
            $Request.Body.parameters.PSObject.Properties | ForEach-Object {
                if ($_.Name -ne 'Identity') { $Params[$_.Name] = $_.Value }
            }
        }

        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-RetentionCompliancePolicy' -cmdParams $Params -Compliance -AsApp -useSystemMailbox $true
        $Result = "Updated Retention compliance policy $Identity"
        Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed updating Retention compliance policy $Identity. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })

}
